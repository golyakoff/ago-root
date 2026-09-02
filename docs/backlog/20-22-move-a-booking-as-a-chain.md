# Move a booking, as a chain

- **Stage**: 20
- **Status**: ready
- **Decided by**: `adr/0090` — the chain shape, and why `adr/0086` is preserved rather than replaced.
- **Delivers the mechanism `20-17` needs.** That item is the same operation with a different trigger:
  moving a booking when the *tenant re-cuts the horizon* (`20-16`), rather than because a client asked.
  One mechanism, two callers; `20-17` stays deferred and consumes this when it is picked up.
- **Depends on**: `20-20`.

## The requirement

A client telephones and asks to move their appointment. Today the operator's only options are cancel
and re-book, which loses the link between the two and makes the client's history a lie: somebody who
moved one appointment three times looks identical to somebody who booked and cancelled three times.

The author also asked for a **count of moves**, for a concrete reason: a client who has rescheduled
five times has consumed disproportionate attention and should not later attract priority or a discount.

## The collision this item exists inside

`adr/0086` decided a booking has **no identity of its own**: `events.booking_id` points at another
event row — the run's anchor — and it explicitly *rejected* minting a booking id as "a column and a
concept for nothing the anchor's id doesn't already have."

That was right when written, and rescheduling is exactly what it did not anticipate: move the time and
the anchor becomes a different row, so by construction it is a different booking. `adr/0090` resolves
this **without reopening `0086`**: a move creates a new booking that references the one it replaced,
the previous one is withdrawn with a reason saying so, and the move count is the chain's length.

Rejected there, and not to be revisited here: giving bookings their own identity (reaches into the
claim path, the confirmation sweep and a migration), and a bare counter on the customer (loses the
distinction between five moves of one appointment and five appointments moved once each).

## Scope

- **A move operation**: release the current slot run, claim the new one, link the new booking to the
  old. It must be **atomic in the sense that matters** — a move that releases the old slot and then
  fails to claim the new one must leave the client booked where they were, not nowhere.
- **A new `CancellationReason`** for the withdrawn side, so a moved-away booking is not indistinguishable
  from a cancelled one. Today the enum has exactly two values, both operator-initiated
  (`RejectedByOperator`, `CancelledByOperator`).
- **The chain readable in both directions**: this booking's history ("moved from Thursday"), and this
  customer's move count.
- **A multi-slot booking moves as a unit** (`adr/0086`), not slot by slot.

## Out of scope

- **Letting the client move their own booking.** Whether that ever exists is undecided; this is the
  operator's action.
- **Any policy** that uses the move count — priority, discounts, refusal. The count is *recorded* here;
  what it means is a business decision the author has not made.
- `20-17`'s re-cut trigger and its per-booking decision screen.

## Done when

- [ ] A booking can be moved to a different slot, and the client's history shows one appointment that
      moved rather than two unrelated records.
- [ ] A move whose new slot cannot be claimed leaves the original intact — **proven by forcing the
      failure**, not by reading the code. This is the one that costs a real client a real appointment
      if it is wrong.
- [ ] The move count is derivable per booking *and* per customer, and the two answers differ correctly
      for the five-moves-of-one versus five-single-moves case.
- [ ] A moved-away booking is distinguishable from a cancelled one in the data, not only in the UI.
- [ ] A booking spanning several consecutive slots moves as one thing.
- [ ] `adr/0086`'s anchor identity is untouched — its own tests still pass unmodified.

## Open questions

- **Does a move re-open the confirmation requirement?** If the original booking had a confirmed phone
  and a confirmation deadline that passed, does the moved one inherit that, or start again? Inheriting
  is friendlier; starting again is more honest about the client having agreed to a *different* time.
- **How far can a booking move before it is really a new booking?** Moving by an hour is obviously a
  move; moving by three months may be something else. Probably no limit is right, but it is worth one
  sentence rather than silence.
