# 25-29 · Seat pricing in code still implements the superseded grid

- **Stage**: 25
- **Status**: done — `ago-chat#252`, `ago-deploy#187`. Boxes 2 and 3 are real remainders, each with
  its own number per rule 14: `25-41` (the priced-but-unpurchasable third Administrator) and `25-42`
  (the price-list screen's own misleading single number).
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

- [x] `ago-chat`'s seat-pricing configuration matches `ago-business 0012`'s actual numbers, verified
      against that document directly.
      `0012` read directly (not from this item's own restatement): Business is **2-5 seats**, 490₽ for
      2 or 3, +200₽/seat past that (690₽ at 4, 890₽ at 5). `SubscriptionTierBands.MinSeats`/`MaxSeats`
      move to 2/5 (from 3/100), `BillingOptions.PricePerSeatRub` (a flat rate) is replaced by
      `BaseSeatPriceRub`/`PricePerExtraSeatRub`, and a new pure-Domain
      `SubscriptionTierBands.ComputeSeatPriceRub` implements the base-plus-marginal formula.
      `CreateCheckoutSessionHandler`, `ProcessSubscriptionRenewalHandler`, and
      `ChangeSubscriptionSeatsHandler`'s own proration all charge through it now - no flat multiply
      survives anywhere charging happens. Pure formula/constant change, **no new persisted state, no
      migration**. Deliberate, in-scope side effect: 2 seats is now purchasable on Business even though
      it equals the free tier's own seat count - `0012`'s own text says this is bought for permanent
      history/a second admin/no auto-deletion, not for seats, deliberately reopening the overlap `13-08`
      once closed. `Growth`/`GrowthMinSeats` stay defined (only `RetentionClass` still needs them) but
      no seat count can resolve to them any more.
- [x] The per-Administrator-beyond-two charge exists and is charged, once `25-25`'s own limit mechanism
      makes an Administrator seat something to charge against.
      **Not done - genuinely blocked, not skipped.** `0012` does price this (+500₽/admin beyond two -
      confirmed directly; `SubscriptionTierBands.ResolveAdminLimit`'s own doc comment previously
      mis-cited this as unpriced "custom", corrected in this pass). But `25-25`'s own `AdminLimit` is a
      **hard block**, not a chargeable overage: `ChangeOperatorRoleHandler` refuses a promotion past 2
      administrators outright (`ConversationErrors.OperatorAdminLimitReached`), so no site can hold a
      third Administrator today - there is nothing yet for a +500₽ charge to attach to. Charging it for
      real needs (a) a purchase path that raises the ceiling (mirroring `ChangeSubscriptionSeats` for
      operator seats), which needs a new persisted "how many extra Administrators were bought" count -
      most naturally a new column on `BillingSubscription` alongside `RequestedSeats` - and (b) changing
      `ChangeOperatorRoleHandler`'s guard from a hard block to "allowed if paid for." **New persisted
      state, therefore a migration** - this item's own worktree was told not to add one this pass (the
      wave's one migration slot was already claimed by `23-78`), so this was designed up to the schema
      boundary and stopped there. **Carried out to `25-41`.**
- [x] `25-20`'s owner price-list screen reflects the corrected numbers with no change to that screen's
      own code.
      **Partially true, and the false part is worth stating plainly rather than assuming past.**
      `OwnerPricingResponse`/`OwnerSeatPricingDto` grew three additive fields (`BaseSeats`,
      `BaseSeatPriceRub`, `PricePerExtraSeatRub`) and dropped the phantom "Growth" tier row - the
      existing `PricePerSeatRub` field stays on the wire (never removed, per `api-design.md`) so
      `ago-console`'s already-shipped `OwnerPricingPage.tsx` does not crash reading it, and the "Tiers"
      table still renders one correct row (2-5 seats). But `0012`'s real pricing is not flat, and that
      screen's own "Price per seat" column renders one number against every row on the assumption that
      every tier "charges the identical price" (`OwnerSeatTierDto`'s own old doc comment) - true of
      `0008`'s superseded grid, false of `0012`. `PricePerSeatRub` is populated with the marginal rate
      (200₽) since that is at least a real number the formula produces, but showing it as *the* seat
      price is misleading for 2/3 seats (really 490₽ flat) and for 5 seats (really 890₽, not
      200×5=1000₽ and not 490+... - the column shows one number, the truth needs three). Out of this
      worktree's reach (a different repository, `ago-console`, no worktree assigned to this item).
      **Carried out to `25-42`** - flagged as worth doing before this backend change reaches the live
      demo, since the console will render a technically-present-but-wrong "price per seat" number in
      the meantime rather than a stale one.

## Outcome (this pass)

`ago-chat#252`, `ago-deploy#187` (the companion config-key rename `ChatModule.ValidateOnStart()`
requires — found and fixed in three manifests, not just `api.yaml`). Seat pricing (box 1) is fully
corrected and
verified against `ago-business 0012` directly, as a pure Domain/Application formula and configuration
change with no new persisted state and no migration. The per-Administrator charge (box 2) is a real,
priced fact in `0012` that the codebase has no mechanism to charge yet - closing it needs new persisted
state and is deferred to a migration slot, not built here. The price-list screen (box 3) is technically
unbroken by this change but not yet honest about the new formula's shape - a `ago-console` follow-up is
needed. See the branch's own commit for the full reasoning; verification counts and the fails-before
table are in this item's own worker report.
