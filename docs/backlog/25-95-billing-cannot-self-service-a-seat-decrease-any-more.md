# 25-95 · Billing cannot self-service a seat decrease any more

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-14, building `25-23` — replacing `BillingPage`'s direct-edit absolute seat field
  with an add-only quantity stepper (the shape the author asked for, an e-commerce "quantity + add"
  control rather than "type your new total") removed the one control that could express a *decrease*.

## What is actually true

Before `25-23`, an owner could type a smaller absolute number into the old seat field and
`ChangeSubscriptionSeatsHandler`'s own downgrade branch would schedule it — the backend path is
untouched and still works today, a scheduled downgrade still renders through
`billingPendingDowngradeBody`, and cancelling outright is still offered. What is gone is the
*console control* that lets an owner reach the downgrade branch at all: `BillingPage`'s new stepper
only ever adds to the current seat count (`seatLimit + seatsToAdd`, always `>= 0`), so there is no
UI path left to request fewer seats than are held today, short of cancelling the whole subscription.

## Why this is worth its own number

`25-23`'s own Scope asked for the field to become "a read-only summary plus an add-seats stepper" —
correctly built, and correct for the *buy more* case this item was actually about. The self-service
downgrade path was a side effect of the old field's shape, never named in `25-23`'s own Scope as
something to preserve, so its loss is a real, found gap rather than a bug in that item's own
implementation — CLAUDE.md rule 15's own "one ticket, one thing": wiring a decrease control back in
is a second promise, not a fix to the first.

## Scope

- Decide the shape: a second, separate "reduce seats" control (its own quantity-to-remove stepper,
  mirroring the add control's own honesty about what is being requested), or a return of some form of
  absolute-total control specifically for the decrease direction. Either is fine; state which and why.
- The decision must account for what a downgrade actually does server-side (scheduled, not
  immediate — `ChangeSubscriptionSeatsHandler`'s own policy) so the control doesn't imply an instant
  change the backend doesn't make.

## Done when

- [ ] An owner can request fewer seats than they currently hold, from the console, without cancelling
      the whole subscription.
- [ ] The control is honest about timing — a decrease schedules rather than applies immediately, if
      that is still the backend's own policy, and the control says so.
