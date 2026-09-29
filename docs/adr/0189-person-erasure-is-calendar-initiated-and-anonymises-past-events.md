# ADR-0189: Person erasure is calendar-initiated, anonymises past events, and never recomputes analytics

- **Status**: Accepted
- **Date**: 2026-09-29
- **Stage**: 26
- **Inverts**: the erasure-direction sketch in ADR-0184's own Consequences ("person erasure deletes
  one Person in chat and cascades the calendar's operational record + events by id").
- **Extends**: ADR-0184 (chat owns the Person; the calendar references it).

## Context

Issue 1815 asked one blast-radius question for client deletion (`26-275`): full person erasure
(Option A — chat's Person, its conversations, its messages, plus the calendar's own operational
record) or a calendar-only "forget" that leaves chat's copy of the person intact (Option B). The
author chose Option A on 2026-09-29, with one explicit constraint: **erasure must not recompute
analytics** — the existing `ago_analytics` rollups, funnel and no-show aggregates that already include
this client's history stay exactly as they are.

Slice #1 already added the `customer:erase` permission (Admin-only, identical string in both products'
`Permission.cs`, adr/0093). This slice is the calendar's own half of the erasure: refuse it, or do it
and tell chat to cascade.

**Two decisions had to be made that ADR-0184 did not anticipate.**

First: *which product decides whether erasure may happen at all.* A real client-deletion flow needs a
guard — a person with a live future booking should not vanish out from under an appointment that is
about to happen. That guard is a read of live event state (`events.status`, `events.starts_at`) that
only the calendar's own database holds. ADR-0184's own Consequences sketched the opposite order — chat
deletes the Person first, then cascades to the calendar. That order would require chat to ask the
calendar, synchronously, "does this person have a future booking" before it dares delete — a
server-to-server read on the write path that CLAUDE.md rule 8 forbids outright (rule 8: a write
decision — and refusing an erasure is one — comes from the database inside the transaction, never a
remote call, and never a cache). The only way to keep the guard rule-8-legal is to evaluate it where
the fact already lives.

Second: *what happens to the person's own past events*, given the no-recompute constraint. Deleting
the `PersonRecord` row outright is not simply a matter of removing one table's row: `events.person_id`
carries a real foreign key to `person_records` (`EventConfiguration`'s own remarks — added precisely so
a future bug pointing `person_id` at nothing would fail loudly at the database). Every historical event
this person was ever booked into references that row, so the row cannot be deleted while any event
still points at it — something has to happen to those events first.

## Decision

**1. Calendar-initiated, not chat-initiated.** `DELETE /api/v1/console/contacts/{personId}`
(`ErasePersonHandler`) is the entry point. It checks `customer:erase`, then refuses (409
`person_erase.future_bookings`) if this person has any event with
`Status ∈ {Booked, PendingConfirmation} AND StartsAt > now` — evaluated inside the same transaction as
the erasure itself, never as a courtesy pre-read (the identical atomic-guard idiom
`WorkerRepository.DeleteIfNeverBookedAsync` already uses for an analogous "may this row be deleted, or
does live booking state say no" question). Only once the guard passes does the calendar erase its own
`PersonRecord` and publish `PersonErased{PersonId, AccountId, OccurredAt, CorrelationId}` for chat to
consume in slice #3 and cascade to the Person, its conversations and its messages (Option A, per issue
1815). **This runs in the opposite direction from ADR-0184's own sketch** — the calendar tells chat, not
chat tells the calendar — because the guard's own fact is calendar-owned and rule 8 will not let it be
asked for remotely.

**2. Anonymise the person's own past events; never hard-delete them, and never recompute anything.**
Every event this person ever touched, except a currently-live future booking, has its `person_id`
column set to `NULL` in the same transaction as the `PersonRecord` delete. Status, worker, service,
times and everything else on the row is untouched — an aggregate-by-service, by-worker or by-date is
byte-for-byte unchanged, because none of those group by person. Only the one column that identified
this person is cleared, which also happens to be exactly what satisfies the foreign key: nulling
`person_id` on every referencing row is a precondition for the `PersonRecord` delete to succeed at all,
not a separate step done for its own sake. No "recompute analytics" event is published alongside this,
and none is needed — `ago_analytics`'s own rollups (ADR-0186) are precomputed and read nothing from
`person_records` or `events.person_id`, so they are physically incapable of changing as a side effect
of this write.

**Anonymise-in-place was not infeasible and needed no fallback.** The FK does force *something* to
happen to referencing events before the person row can go, but nothing forces that something to be a
delete: an `UPDATE ... SET person_id = NULL` satisfies the constraint identically to removing the rows,
while a hard delete of historical events would have been the one operation that *could* silently change
a future analytics recompute (fewer source rows to aggregate over) — exactly what the author's
constraint rules out. Anonymisation was therefore not a compromise found after a delete path failed; it
is the only one of the two options that satisfies "don't recompute" and "no identifying data left" at
once.

**3. The guard's own statement never touches a row it must not touch, regardless of timing.** The
anonymising `UPDATE`'s own `WHERE` clause excludes `status IN ('Booked','PendingConfirmation') AND
starts_at > now` unconditionally — not "as of when the guard was checked", but as an unconditional
predicate the database itself evaluates when the statement runs. Combined with the guarded `DELETE
... WHERE NOT EXISTS (...)` immediately after, in the same transaction, this makes a concurrent booking
claim landing in the gap harmless: either it commits before our statements run (correctly re-checked by
the guard's own fresh snapshot) or after (our transaction already committed or rolled back a *whole*
outcome, so there is nothing left mid-flight to corrupt). A blocked attempt therefore leaves genuinely
nothing changed — the anonymising update rolls back along with the refused delete.

**4. `contact_phone_reveals` is left untouched — an existing, not a new, exemption.** That table
carries no foreign key to `person_records` by design (`23-12`'s own migration remarks: "this record
must survive whatever erases the customer"), the identical evidentiary-survival reasoning ADR-0111
already gives for `acceptance_records` surviving a subject's own erasure. This ADR does not change that
— a reveal audit row naming an erased person is expected, not a leak of anything the person still
controls.

**5. `events.origin_conversation_id` is left untouched too.** It is an opaque reference to a chat
conversation, not itself personal data about the erased person, and chat's own erasure (slice #3)
handles that conversation directly. Once chat erases it, this column becomes a dangling reference to
nothing — the same accepted trade-off ADR-0101 and ADR-0111 already name for their own tables, applied
here to a column nobody reads once its target is gone.

## Consequences

**Positive.** The guard is a real, rule-8-legal database read, not a remote call chat would otherwise
need on a path CLAUDE.md forbids it from taking. Every existing and future analytics rollup keeps
reading identical source rows before and after an erasure — "don't recompute" is true by construction,
not by discipline. The erasure is transactionally all-or-nothing: a blocked attempt is indistinguishable
from one that was never tried.

**Negative, named rather than hidden.** A `person_records` row can, in the one narrow race where an
operator books the *exact* person id being erased at the *exact* instant an admin erases it, be
recreated immediately after this transaction commits (the erase's own lock is scoped to statements, not
to a longer-lived advisory lock spanning both actors) — an inherent hazard of two independent human
actors targeting the same identity simultaneously, not different in kind from the dangling-reference
residuals ADR-0101 and ADR-0111 already accept for their own tables, and not solved by this ADR.
Anonymised events keep their `starts_at`/`worker_id`/`service_id` forever with no person to attribute
them to — an intentional, permanent gap between "who was this" and "what happened", which is the whole
point of the erasure. `PersonErased` carries no acknowledgement channel; if chat's own cascade
(slice #3) fails, the calendar's own side has already committed and does not retry a cascade it cannot
observe — the same at-least-once, fire-and-forget posture every other outbox event in this product
already has (rule 5 puts the burden of idempotent, eventually-successful consumption on chat, not on a
synchronous round trip here).

## Alternatives considered

- **Chat-initiated erasure (ADR-0184's own original sketch).** Rejected: requires a synchronous
  server-to-server read of the calendar's own live event state to run the future-bookings guard before
  chat dares delete its Person — a rule-8 violation on the one path CLAUDE.md is least willing to bend
  on.
- **Hard-delete the person's past events along with the `PersonRecord`.** Rejected per the author's own
  stated constraint: fewer source rows for a future analytics recompute to aggregate over is exactly
  the silent change "don't recompute" rules out, even though no recompute is triggered *today* — this
  ADR is explicit that the anonymise choice is what keeps a *future* recompute honest too, not only
  today's absence of one.
- **A `PersonErased`-triggered analytics recompute or backfill.** Rejected outright by the author's own
  decision on issue 1815; not implemented, not staged, not left as a TODO.
- **`ON DELETE SET NULL` on the `events.person_id` foreign key**, so a bare `DELETE FROM person_records`
  would cascade the nulling automatically. Rejected: it would silently null `person_id` on a *live
  future* booking too, the one row this entire item exists to protect from disappearing out from under
  an appointment about to happen — the guard has to run before any nulling happens, which only
  application-level SQL, not a DB-level cascade, can express.
