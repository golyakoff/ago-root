# ADR-0090: An operator creates bookings directly, and a reschedule is a chain rather than an edit

- **Status**: Accepted
- **Date**: 2026-09-02
- **Extends**: `adr/0086` (its anchor-id booking identity is preserved, not replaced — see below),
  `20-09` (whose verified-phone rule was decided for one origin and now meets a third)
- **Related**: `adr/0079`/`14-14` (the evidence rule for contact details), `20-10` (the phone-
  verification primitive this reuses)

## Context

Every booking today originates in one of two places: a chat conversation (`20-07`'s module flow) or
the public booking API — and the latter ships disabled. The console can `reject`, `cancel` and
`no-show` an **existing** booking; there is no path by which an operator creates one.

That was adequate while AGO Calendar had no user. It is not adequate for the first real tenant, whose
shape was described directly: a single-person business where the owner is also the only operator, and
where clients arrive **by telephone and in person about as often as through the website**. Under the
current model she cannot enter a booking for someone who just called her. The product's primary
workflow has no implementation.

This ADR settles the three decisions that path forces, all of which were argued through rather than
assumed, and two of which reversed a position taken earlier in the same conversation.

## Decision 1 — an operator-created booking is a third origin, and it is never blocked on verification

**An operator may create a customer and a booking directly, and the booking is valid immediately with
an unverified phone number.**

`20-09` requires a verified phone before a booking confirms, and decided that rule was **chat-only**.
That decision was taken when this third origin did not exist, so the rule has to be extended or not
extended deliberately rather than by default.

It is **not** extended. Not because the risk disappears — an early draft of this ADR argued that it
did, on the grounds that the owner is the gatekeeper, and the author rejected that argument correctly:
*a griefer can telephone, take a slot and not turn up, and the grid is blocked exactly the same way.*
What actually changes is narrower: the operator has caller ID and a conversation as signals the public
widget does not, and — decisively — **she cannot wait.** She is on the phone. A booking that cannot be
created until a code round-trips is a booking that does not get created.

So verification moves off the critical path and becomes a **property the booking may acquire**, with
its absence carrying consequences elsewhere (Decision 1b).

### 1b — the confirmation message is the verification, and a rejected alternative

The first proposal here was that she send a code *during* the call and have the client read it back.
The author rejected it on operational grounds that are obviously right in hindsight: **she will not be
in the system while talking.** She will talk, hang up, and enter the booking afterwards — so the code
would arrive after the call ended, and recovering the flow would mean asking the client to telephone
again. Worse than not verifying.

The shape that survives: when a delivery provider exists, booking creation sends the client a written
confirmation — *"you are booked for Thursday 15:00, confirm: <link>"* — and **acknowledging it is what
verifies the number**. No second call, no extra step asked of anyone, and the message is one the tenant
wants regardless, because a written confirmation is itself the cheapest reduction in no-shows.

An unverified number is then **a signal rather than a failure**: a booking whose confirmation was never
acknowledged is a riskier booking, and that feeds the same reputation model the no-show policy uses.

**This cannot gate the launch**, and the sequencing is stated so nobody discovers it later: no SMS
provider is chosen yet (`14-15`, the author's own decision). Until one exists, operator-created
bookings simply carry unverified numbers. The model must not preclude the upgrade; nothing waits for it.

## Decision 2 — a phone number is correctable, and correcting it clears its own verification

`Customer.Phone` is immutable today and `PhoneVerifiedAt` is set once (`??=`). For a workflow where a
number is heard over a telephone and typed by hand, **a mistyped digit is the most likely daily error
in the entire product**, and there is currently no way to fix one.

An operator may correct it, and **the correction clears `PhoneVerifiedAt`**. Verification is evidence
about a *value*, not about a person; changing the value destroys the evidence, and carrying the old
proof forward onto a new number would be exactly the silent falsehood `14-14` exists to prevent.

### 2b — reputation attaches to the customer, never to the phone number

Raised by the author and worth recording as a rule rather than an aside: **a telephone number can be
reclaimed by the carrier and reissued to a different person.** A number that accumulated no-shows and
was then reassigned would carry a stranger's history, and a blocklist keyed on numbers would punish
somebody who has done nothing.

So every reputation fact — no-shows, late cancellations, reschedule count — belongs to the `Customer`,
and a number is only ever an attribute of one. There is to be no tenant-wide or system-wide list of bad
numbers.

## Decision 3 — a reschedule is a chain of bookings, not a mutated one

The requirement is *"the same booking, moved"*, plus a count of how often a given client has moved
things, because somebody who has rescheduled five times has consumed disproportionate attention.

This collides with `adr/0086` head-on. That ADR decided a booking has **no identity of its own**:
`events.booking_id` points at another event row — the run's anchor — and it explicitly *rejected* a
freshly minted booking id as "a column and a concept for nothing the anchor's id doesn't already have".
That reasoning was correct when it was written, and rescheduling is precisely the requirement it did
not anticipate: move the time and the anchor becomes a different row, so by construction it is a
different booking.

**`adr/0086` is preserved.** A reschedule creates a new booking that carries a reference to the one it
replaced; the previous booking is withdrawn with a reason saying so. The reschedule count is the length
of that chain.

Weighed and rejected:

- **Give bookings their own identity** — revisiting what `0086` declined. Cleanest expression of "the
  same booking", and it reaches into the claim path, the confirmation sweep and a migration. Too much
  for what it buys, and it would re-open a decision that is right for every other reason.
- **A counter on the customer only, with no link between bookings.** Cheapest, and it loses the
  distinction that motivated the request: five moves of *one* appointment is a different customer from
  five appointments moved once each over a year. The chain yields both readings; a bare counter yields
  neither well.

The chain also preserves the history itself, which the tenant wants for a reason nobody had to argue —
her card should be able to say *"moved from Thursday"*, not merely *"moved: 3"*.

## Consequences

- **Positive**: the tenant's primary intake — telephone and walk-in — becomes expressible at all.
- **Positive**: verification stops being a gate and becomes a gradient, which is both more honest and
  more useful, since the signal feeds a policy rather than blocking a workflow.
- **Positive**: `adr/0086` stands, and the reschedule history is richer than the counter that was asked
  for.
- **Negative**: three origins now create bookings, and each must independently satisfy Calendar's own
  invariants (`adr/0059`/`adr/0086`'s claim, `adr/0049`'s no-overlap). A third caller is a third chance
  to bypass a rule by not going through the same use case, and the guard against that is that all three
  go through one handler, not three.
- **Negative**: the reschedule chain makes "how many bookings does this customer have" ambiguous unless
  every read decides whether it means links or chains. Reads must be explicit about which they count.
- **Consequence for `20-09`**: unchanged in its own scope, now explicitly not universal. Two of three
  origins require a verified phone; the operator-created one does not, and this ADR is why.

## Deliberately not decided here

**The visit-outcome model** — an explicit "attended", a per-visit revenue amount, and how a
late cancellation differs from a silent no-show — is designed but blocked on one question the author
has not yet answered: **whether the revenue figure is a private note or something the tenant will rely
on as an account.** That answer changes the shape of money in this domain, and money is a step, not a
field: it reaches prepayment (`already named by the author as coming`), rounding, currency and
immutability. It is left out rather than guessed at.

What is already known and will not change: the significant axis for a cancellation is **how long before
the appointment** it happened, not merely that it happened — cancelling ten minutes ahead loses the slot
just as thoroughly as silence does. The facts needed for that (when, and at whose initiative) are
recorded today only in domain events and not on the booking row, so the *recording* is urgent even
though the *policy* is not.
