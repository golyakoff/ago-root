# 25-29 · Seat pricing in code still implements the superseded grid

- **Stage**: 25
- **Status**: ready
- **Depends on**: `ago-business` decision `0012` (2026-09-07) is the current grid; it supersedes `0008`
- **Found**: 2026-09-09, while building `25-20`'s owner price-list screen

## What is actually true

`ago-chat`'s billing code (`BillingOptions.PricePerSeatRub`, `SubscriptionTierBands`, built by
`13-02`/`13-08`) implements `ago-business` decision `0008`'s grid: a flat 590₽ per seat, 3–100-seat
tier bands. `ago-business`'s current decision, `0012` (2026-09-07), supersedes `0008` and prices
Business differently — 490₽ base for up to 3 seats, +200₽ per seat beyond that (capped at 5 seats),
plus a separate +500₽ charge per Administrator seat beyond the first two. The code has no concept of
the per-administrator charge at all, and its per-seat number and band shape are both the old grid's.

This was invisible until `25-20` built a screen that reads the code's own numbers back out loud — the
drift was real before that screen existed, just unobserved.

## Scope

- Bring `BillingOptions`/`SubscriptionTierBands` (or wherever seat pricing is actually computed and
  charged — check `CreateCheckoutSessionHandler`, `ProcessSubscriptionRenewalHandler`, and anywhere
  else that reads these values before assuming the fix is contained to the two types named above) into
  agreement with `ago-business 0012`'s actual numbers: 490₽/3 seats base, +200₽/seat up to 5, +500₽ per
  Administrator seat beyond the first two.
- `25-25` (Administrator seats have no limit of their own) is closely related but not the same
  question — that item is about *how many* Administrator seats an account may hold; this item is about
  *what one costs* once `25-25`'s own limit mechanism exists to charge against. Read `25-25` before
  starting, since the per-administrator charge this item needs to add has nowhere to attach until an
  Administrator seat is a countable, limited thing.

## Where this is likely to go wrong

- **This changes what real (or eventually real) customers are charged.** Treat a change here with the
  same care CLAUDE.md gives any billing-adjacent decision — verify against `ago-business 0012` itself,
  not against this item's own restatement of it, before writing a number into code.
- **`25-20`'s own price-list screen reads these values live** — once this item lands, that screen's own
  numbers change without any edit to the screen itself, which is the intended effect and worth
  confirming rather than assuming.

## Done when

- [ ] `ago-chat`'s seat-pricing configuration matches `ago-business 0012`'s actual numbers, verified
      against that document directly.
- [ ] The per-Administrator-beyond-two charge exists and is charged, once `25-25`'s own limit mechanism
      makes an Administrator seat something to charge against.
- [ ] `25-20`'s owner price-list screen reflects the corrected numbers with no change to that screen's
      own code.
