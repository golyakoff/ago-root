# ADR-0126: The calendar's own reveal record is a dedicated table, confirmation is gated on `CustomerRead` alone, and the rung's projection commits in one save

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 23 (`23-12`)

## Context

`adr/0123` decided the account side of the contact-visibility rung: the wire contract
(`ContactVisibilityChanged`), that rung three is absent from the type system, and that the account
side's own reveal record (`contact_reveals`) is a dedicated table rather than a widened
`AccessRecordKind`. It explicitly left the calendar side open: "`ago-calendar` consumes nothing yet...
There is also no console screen for the rung itself or for the reveal audit trail" — `23-12` is the
item that builds that half, in a different repository with a different database and no
`access_records`-shaped table to widen or decline to widen in the first place.

Three questions came up building `23-12` that `23-11`'s backlog file named as open and `adr/0123`
did not answer, because they are questions about *this* product's own schema and its own read of
`decisions.md` §5, not about the event crossing the boundary:

1. Does this product need its own equivalent of `contact_reveals`, and if so, what shape?
2. §5 says "I called and it is them"... "lives only on rungs one and two — somebody who cannot see a
   number cannot confirm it by calling." What does that mean as a gate, given this product's own
   `ContactVisibility` has only two members and both let a `CustomerRead` holder see the number?
3. `22-07`'s `ModuleQuantityGrantedConsumer` commits its own write in two saves, because it holds a
   lock across a read-decide-write. Does the rung projection need the same shape?

## Decision

**A dedicated `contact_phone_reveals` table, modelled on `contact_reveals`'s own shape, not on any
existing calendar structure — because there is no existing calendar structure this could widen.**
This product has no `access_records`-equivalent audit table at all; `adr/0123`'s own choice not to
widen `AccessRecordKind` rests on an argument this product has no analogous target for, so the
question reduces to "build one" rather than "widen which one." `contact_phone_reveals` takes the
identical shape `adr/0123` gives `contact_reveals`: raw Npgsql, no aggregate, no foreign key on
`tenant_id` or `customer_id` (the same `adr/0111`/`adr/0112`/`adr/0113` reasoning — a reveal record
must survive whatever erases the customer or the tenant it names, or the one question it exists to
answer would lose its own evidence to the process the question is about), keyset-paged by
`(tenant_id, id)`, its own 365-day prune job (`ContactPhoneRevealPruneJob`, matching
`ContactRevealPruneJobOptions.RetentionWindow`'s own 365 days for the identical reasoning: a reveal
is evidence of an ordinary, lawful read, not proof of a lawful basis, and the window is long enough
to answer "did anyone reveal this in the past year" and short enough not to become an indefinite
personal-data store about an operator).

**Confirming "I called and it is them" is gated on `Permission.CustomerRead` alone — not a
rung-keyed check — because under today's type system there is no rung where a `CustomerRead` holder
cannot see the number.** §5's sentence reads as a per-rung refusal, but `ContactVisibility.Visible`
shows the number plainly and `ContactVisibility.MaskedWithReveal` shows it the moment a reveal is
called — both are "can see it," one directly and one on demand. The rung that sentence is actually
describing is rung three (`Never`), and `adr/0123`/this product's own `ContactVisibility` deliberately
do not add it to the enum (§5's own instruction, taken literally). So `Permission.CustomerRead` is the
whole of what §5 asks for today: it is the one gate that already distinguishes "can see this tenant's
numbers at all" from "cannot." A second, rung-keyed check would have nothing to discriminate on until
rung three is real, and adding one now would be exactly the kind of ahead-of-its-subscriber plumbing
this codebase already avoids for the rung's own third member.

**The rung's own projection commits in one save, the `RoleAssignmentsChangedConsumer` shape, not the
`ModuleQuantityGrantedConsumer` shape.** `IWorkerQuotaGrantStore.ApplyAsync` needs a lock across a
read-decide-write because a worker-quota grant reads its own current value to decide what to
deactivate. A rung has nothing to decide from its prior value — it is displayed, never counted
against or compared — so `IContactVisibilityProjectionStore.StageAsync` stages a full replace with no
read-decide-write to protect, and `ContactVisibilityChangedConsumer` commits it together with its own
inbox record in the identical one-save shape `RoleAssignmentsChangedConsumer` already uses for the
identical reason.

## Consequences

**Positive.** The reveal record answers the audit-view requirement `decisions.md` §5's amendment
states — individual reveals, never an aggregated count a staff-comparison screen could quote — on its
own terms, gated on `Permission.CalendarConfigure` rather than `CustomerRead`, the identical
"every operator who can reveal is not thereby trusted to see the whole tenant's reveal history"
refusal `ago-chat`'s own `GetContactRevealsForSiteHandler` states for its sibling read. Confirmation
needs no second, currently-meaningless gate to maintain. The projection needs no lock nobody reads
under.

**Negative, stated rather than discovered.** `contact_phone_reveals` is a second small table with its
own prune job in a second repository, alongside `contact_reveals`'s own copy in `ago-chat` — two
tables answering the identical question in two databases, accepted because a reveal is inherently
per-product (each product masks its own store) and there is no shared database to hold one row for
both. The `CustomerRead`-only confirm gate is a decision this ADR states plainly rather than lets a
future reader assume was rung-aware: if rung three is ever built, `ConfirmOperatorVerifiedPhoneHandler`
needs a second look, not an assumption that today's single gate already covers it.

## Alternatives considered

**No calendar-side reveal record at all, relying on the account-side `contact_reveals` alone.**
Rejected: that table answers "did anyone reveal a chat contact detail," not "did anyone reveal a
calendar customer's phone" — the two stores are genuinely different data in different databases, and
a reveal of one leaves no trace of the other.

**Gate confirmation on the rung being `Visible` specifically, refusing it under `MaskedWithReveal`.**
Rejected: that would refuse a confirmation from an operator who *just revealed the number through this
exact request flow* — the masked rung's whole point is reveal-then-act, and refusing the "act" half
because the rung is masked would defeat the reveal it just granted.

**Two-save consumer shape, matching `ModuleQuantityGrantedConsumer` for uniformity with the other
cross-boundary consumer this stage added.** Rejected: uniformity with a shape whose reason (a lock)
does not apply here would be cargo-culting the wrong precedent; `RoleAssignmentsChangedConsumer` is
the closer analogue because both project a value with no read-decide-write.
