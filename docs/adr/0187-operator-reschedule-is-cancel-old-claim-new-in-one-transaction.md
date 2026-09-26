# ADR-0187: Per-booking operator reschedule is cancel-old + claim-new in one transaction, not an in-place move

- **Status**: Accepted
- **Date**: 2026-09-26
- **Stage**: Stage 26 (booking-lifecycle operator actions, `26-175`)

## Context

The author asked for an operator action that moves one confirmed booking to a new time
(«Перенести оператором»). The AGO Calendar data model constrains how that can be expressed
(`ago-calendar` `Ago.Calendar.Domain/Event.cs`, read in the `26-175` design pass):

- **One `events` row is simultaneously a free slot and the booking that took it.** A booking is a
  *run* of consecutive rows sharing a `BookingId` anchor.
- The target time is **not a mutable field on the booking** — it already exists as its own
  `Available` grid rows, materialised ahead of time, positioned by a per-worker no-overlap **GiST
  exclusion constraint** (`ex_events_worker_no_overlap`, `adr/0049`).
- **There is deliberately no transition back to `Available`.** A cancelled row stays `Cancelled`
  as history; the materialiser only ever fills days that have no rows at all (`adr/0053`). Whether a
  freed slot should be re-offered is an unmade product decision (`20-04`), owned by nobody yet.
- Claiming a slot is a **contended, racy** write, so it runs as raw atomic compare-and-set SQL
  inside the write transaction (`BookingStore.ClaimSlotSql`; rule 8 — a write decision is never
  pre-read or cached). The operator transitions (`Reject`/`Cancel`/`MarkNoShow`) are ordinary
  single-actor aggregate writes protected by `xmin`.
- Per `adr/0093`, every calendar permission string must match `ago-chat`'s catalogue byte-for-byte
  and is granted account-side on the seeded Operator role.
- Raw events are about to be retained write-only for analytics (`adr/0186`): whatever a state change
  emits today is what future reports see, so the event stream's shape is a long-lived contract even
  before a consumer exists.

These forces — not convenience — decide the shape below.

## Decision

**An operator reschedule is `cancel-old` + `claim-new`, committed in one transaction. It is not an
in-place mutation of the booking's time.** For v1 the move is **same worker, same service,
time-only**; the new run lands directly in **`Booked`** (an operator placing an appointment is the
confirmation authority — it skips the veto window, consistent with a manual Confirm).

Concretely, in one transaction:

1. resolve the old run by `BookingId`; require `Booked` and the caller's tenant;
2. compute the new run at the target start over the target day's grid (same worker, same service, so
   run length / buffer are unchanged) — a courtesy read that only decides *which ids to claim*;
3. **claim the new run atomically** — the same compare-and-set `IBookingStore` uses
   (`… WHERE id = ANY(@newIds) AND status='Available' AND starts_at > @now`, requiring
   rows-affected `= @newIds.Length`). If the target was taken in the race the whole transaction rolls
   back and the reschedule fails with "slot no longer available" — **the old booking stays `Booked`,
   untouched**;
4. `Cancel` the old run (`Booked → Cancelled`, `CancelledByOperator`), carrying the same `PersonId`,
   `ServiceId`, `OriginConversationId`, and phone onto the new run;
5. emit exactly one integration event (see below).

This spans an EF load-mutate-save (the cancel) and a raw atomic `UPDATE` (the claim) in one
transaction, so it needs a **new port `IBookingRescheduleStore.TryRescheduleAsync`** — no existing
port owns both statements. This is the precedent `ExpiredBookingConfirmer` already sets (raw claim +
EF transition on one connection/transaction) and the same "the transaction has to belong to
something" reasoning `IBookingStore` gives for being one port rather than two.

**Permission.** A new, distinct `booking:reschedule` (`adr/0016` granularity — a tenant may let a
senior operator move an appointment without granting it to a junior, independently of who may
cancel). Per `adr/0093` this costs three matching entries: `Ago.Chat.Domain.Permission`, the seeded
Operator role in `RegisterSiteHandler.OperatorRolePermissions`, and `Ago.Calendar.Domain.Permission`.

**Event — one clean `BookingRescheduled`, carrying the old→new link, emitted now.** The reschedule
stages exactly one integration event, `BookingRescheduled(bookingId /* new */, previousBookingId,
tenantId, calendarId, personId, previousStartsAt, newStartsAt, newEndsAt, localDate, occurredAt,
correlationId)`, in the same transaction (rule 4). It does **not** emit the `BookingConfirmed` /
`BookingPendingStateChanged("Booked")` pair the ordinary confirm path stages for the new run, and it
does not emit a `Cancelled` signal for the old run. This is a deliberate departure from the
`26-175` design pass's "defer the contract until it has a consumer" recommendation, made by the
author on 2026-09-26 for one reason: the raw event stream is **retained from day one** (`adr/0186`),
and a reschedule expressed as the default `Cancelled` + fresh `BookingConfirmed` pair is
indistinguishable in that retained history from a real cancellation plus a brand-new booking. A
dedicated event with the old→new link keeps the retained analytics honest before any consumer is
built (the future `20-05` SMS consumer and the `ago-analytics` ingest are the eventual readers). The
`old→new` link is mandatory on the event; a consumer is not built in this item.

**Deferred, explicitly: a stable external booking identifier.** Booking identity *changes* across a
reschedule (the new run is a new `BookingId`; §Consequences). A stable, reschedule-surviving external
id — the thing a customer-facing "manage my booking" link or an iCal/CalDAV `UID` would need — is
**not** introduced now. When client-facing booking management or external-calendar sync is built, the
answer is a **reschedule-chain root id** carried alongside `BookingId`; the `BookingRescheduled`
event's `previousBookingId` link is what makes reconstructing that chain possible after the fact. The
door is left open on purpose; it is not opened in this item.

The freed old slot keeps today's behaviour — `Cancelled`, not re-offered as `Available`, identical to
a plain cancel. Whether cancel/reschedule should re-open a slot is `20-04`'s standing question and
gets its own number, not this item.

## Consequences

**Positive.**
- No new domain state and no new transition method: reschedule composes `Cancel` and the atomic
  claim, both already proven under their races. The composition adds no new race — only the
  requirement that the two commit together.
- Rule 8 holds unchanged: new-slot availability is decided by the claim's own `WHERE` inside the
  write transaction; a stale courtesy read costs at most the ordinary "slot no longer available".
- **Cross-worker / cross-service reschedule stays cheap later**: `claim-new` can target any slot in
  the grid, so lifting the v1 same-worker/same-service limit is a handler change, not a model change.
  An in-place-mutation model could never move a booking to another worker — the row is bound to its
  worker by the GiST constraint.
- Retained analytics are clean from the first reschedule: one `BookingRescheduled` with an old→new
  link, never a cancel/new-booking pair a report would have to correlate or, worse, miscount.

**Negative / now-owed.**
- **Booking identity is not stable across a reschedule.** The moved booking is a new row with a new
  `BookingId`. Anything external that ever keys on the booking id — a printed/SMS'd reference, a
  self-service link, an iCal `UID` — would break on a reschedule until the deferred chain-root id is
  built. This is the single real flexibility given up, and it is recoverable (the event's
  `previousBookingId` preserves the chain), not lost.
- Reschedule does **not** improve slot utilisation: the vacated time is not re-offered (it inherits
  plain cancel's behaviour). This ADR entrenches "cancelled row = terminal, slot stays dead" — the
  in-place path would have forced building `vacate → Available`, half of `20-04`; we deliberately do
  not build it here.
- A second store/port (`IBookingRescheduleStore`) to maintain, spanning EF + raw Npgsql, with a
  concurrency test surface (claim-loses-race leaves old booking intact; cancel races the sweep).
- A new permission string to keep in lock-step across two repositories (`adr/0093`); drift is a
  latent auth bug caught only by the mirror check.
- `BookingRescheduled` is a published contract with no consumer yet — accepted here (against the
  usual "no consumer-less contract" posture) specifically because the retained-events argument
  outweighs it; the event must carry `previousBookingId` from the start or the analytics reason for
  emitting it is lost.

## Alternatives considered

- **In-place move — mutate `StartsAt`/`EndsAt`/`LocalDate` on the existing rows.** The intuitive
  "same booking, new time", and what the author first pictured. Rejected because the model cannot
  express it honestly: the target interval already exists as its own `Available` rows (mutating onto
  it either doubles rows for that interval or fights the GiST exclusion), and vacating the original
  interval requires the `Available` transition the aggregate deliberately does not offer (`20-04`).
  It would also desync the materialised grid from `MaterializeFrom`/`RecutFrom` bookkeeping. Its one
  advantage — a stable booking id — is the deferred chain-root id's job instead, and it cannot do
  cross-worker moves at all.
- **Reuse `booking:cancel` instead of a new permission.** Defensible (reschedule *contains* a
  cancel) and cheaper cross-repo. Rejected: it forfeits the independent grant `adr/0016`'s
  granularity argument calls for — moving an appointment and cancelling it are different trusts.
- **Emit the default `Cancelled` + `BookingConfirmed` pair and let a future consumer correlate
  them.** The `26-175` design pass's recommendation, and the standing "don't stage a contract nobody
  reads" posture (`RejectBookingHandler`). Rejected by the author for the retained-events reason
  above: correlation after the fact is fragile, and a miscorrelated pair silently corrupts the
  cancellation metric `adr/0186` will compute.
- **Introduce the stable chain-root id now.** Rejected as YAGNI for v1 — no client-facing booking
  management or external-calendar sync exists yet; the `previousBookingId` link preserves the ability
  to add it as a mechanical, non-breaking change when a real reader appears.
- **New run back to `PendingConfirmation` with a fresh veto window.** Rejected: the operator just
  placed the appointment; a window to change one's mind about an action just taken is incoherent, and
  `Event.Confirm` clears the deadline unconditionally anyway.
