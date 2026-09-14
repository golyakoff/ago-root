# 25-96 · The console cannot buy extra Administrator seats

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-14, building `25-23` — `BillingPage` now shows Administrator seats as their own
  panel (used, limit, included-in-tier, purchased-extra), but nothing on the screen can move the last
  number. `25-41`'s own purchase endpoint
  (`POST .../billing/subscriptions/{id}/administrators`) exists and is exercised by its own backend
  tests, and is unused by the console entirely.

## What is actually true

`25-23`'s own Scope was explicit that it "reads" the Administrator facts `25-41` already wrote —
displaying them was the whole ask, and it is correctly done: `status.adminLimit`,
`status.adminsUsed`, `status.extraAdministratorsPurchased` all render in their own panel. Nothing in
that item's own Scope asked for a purchase control, so this is not a regression in `25-23`'s own
work — it is the natural next step the display makes visible for the first time: a tenant can now
*see* they are at their Administrator limit, with no button anywhere on the same screen to change
that fact, unlike the Operator-seat panel right beside it.

## Why this is worth its own number

CLAUDE.md rule 15 — wiring a second purchase endpoint into the same screen `25-23` already changed
once tonight is a second promise, correctly left out of that item rather than expanding its own
blast radius. `25-41`'s own item never claimed the console half either — it built and proved the
endpoint, not its own UI.

## Scope

- A purchase control for extra Administrator seats, on `BillingPage` or wherever fits the existing
  Operator-seat purchase flow's own shape (`25-23`'s add-seats stepper is the immediate precedent to
  follow or deliberately diverge from — state which).
- Reuses `25-41`'s existing endpoint; no new backend work expected unless building the console half
  surfaces a real gap in what that endpoint already returns.

## Done when

- [ ] An owner can purchase additional Administrator seats from the console, through `25-41`'s
      existing endpoint, proven against a real (or faked, matching this codebase's own established
      test shape) call — not merely that the button exists.
- [ ] The purchased count and the resulting limit refresh on the same screen after a successful
      purchase, the same "never claim success before the server confirms it" discipline `BillingPage`
      already holds for the Operator-seat path.
