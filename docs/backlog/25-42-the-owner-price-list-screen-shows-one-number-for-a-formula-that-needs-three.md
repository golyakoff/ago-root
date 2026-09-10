# 25-42 · The owner price-list screen shows one number for a formula that needs three

- **Stage**: 25
- **Status**: done — pending PR number (see `## Outcome` below)
- **Depends on**: `25-20` (built the screen), `25-29` (corrected the formula the screen now
  misrepresents)
- **Found**: 2026-09-09, carried out of `25-29` at landing rather than left inside it (rule 14/15 —
  a console-side rendering fix is a different repository and a different promise than the backend
  formula correction)

## What is actually true

`25-29` corrected `ago-chat`'s seat pricing to `ago-business 0012`'s real, non-flat formula: 490₽
base for 2–3 seats, +200₽ for each seat past that (690₽ at 4, 890₽ at 5). `GetPricingForOwnerHandler`/
`OwnerPricingResponse` grew three additive fields (`BaseSeats`, `BaseSeatPriceRub`,
`PricePerExtraSeatRub`) carrying that formula honestly over the wire.

`ago-console`'s already-shipped `OwnerPricingPage.tsx` was not touched by `25-29` (a different
repository, no worktree assigned to that item) and still reads the legacy `PricePerSeatRub` field,
kept on the wire only for compatibility. Its "Tiers" table renders one "Price per seat" number against
the whole Business row, on the old assumption (`OwnerSeatTierDto`'s own doc comment) that every seat
in a tier costs the same — true of the superseded flat grid, **false of `0012`**. Today that column
shows the marginal rate (200₽) against every row, which reads as "every seat costs 200₽" — wrong for
2 or 3 seats (really 490₽ flat) and wrong for 5 (really 890₽ total, not 200×5).

## Scope

- Read the three new fields (`BaseSeats`, `BaseSeatPriceRub`, `PricePerExtraSeatRub`) instead of the
  legacy flat `PricePerSeatRub`.
- Show the real shape: a base charge for the first `BaseSeats` seats, then a per-seat charge for each
  seat past that — not a single "price per seat" number implying a flat rate.
- Do not remove `PricePerSeatRub` from the API call itself; it stays on the wire for other consumers
  per `api-design.md`'s own "never remove a field" rule — this item only changes what the screen reads
  and renders, not the contract.

## Where this is likely to go wrong

- **Don't invent a new flat number to keep the old column shape.** The whole point is that a single
  number is dishonest for this formula; the fix is showing the formula, not a better-chosen single
  number.
- **This is display-only.** Nothing about how pricing is computed or charged changes here — that is
  `25-29`, already landed.

## Done when

- [x] The price-list screen shows the real base-plus-marginal formula for Business, not a single
      misleading per-seat number.
- [x] A tenant reading the screen at 2, 3, 4, or 5 seats sees the correct total for each, matching
      `ago-business 0012` directly.
- [x] Nothing about `25-29`'s own backend formula or the wire contract changes.

## Outcome

Shipped as an `ago-console` PR (worktree `ago-console-25-42`, branch
`fix/25-42-owner-price-list-shows-the-real-formula`) — see the managing session's own commit-prep
block for the exact commit. Console-only, as scoped; nothing in `ago-chat` changed.

**What changed.** `ownerApi.ts`'s `OwnerSeatPricing` gained `baseSeats`/`baseSeatPriceRub`/
`pricePerExtraSeatRub` (additive; `pricePerSeatRub` stays on the wire, unread by this screen now).
`OwnerPricingPage.tsx`'s "Seats" panel: the description states the formula in prose ("₽490.00 for
the first 3 seats, then +₽200.00 per seat beyond that"), and the table changed from one row per
*tier* (`Starter`, `2–5`, a single misleading `₽200.00`) to one row per *seat count* (`2`→₽490.00,
`3`→₽490.00, `4`→₽690.00, `5`→₽890.00) — `SubscriptionTierBands.ComputeSeatPriceRub`'s own formula
restated client-side (`baseSeatPriceRub + max(0, seats − baseSeats) × pricePerExtraSeatRub`), built
generically from `tiers[].minSeats..maxSeats` rather than hardcoded to today's single 2–5 band, so a
future second band needs no rendering change.

**Test fixture finding.** `ownerPricingPage.test.tsx`'s own `REAL_PRICING` fixture and its first test
had never been updated for `25-29` — they still asserted the superseded `0008`-era shape (`₽590.00`
flat, two tiers `Starter 3–9`/`Growth 10–100`), which is exactly the display bug this item exists to
fix. Fixed as part of this change; the old test would otherwise have kept passing against the bug it
was nominally covering.

**Verification** (`ago-console-25-42`): `tsc -b --noEmit` clean, `eslint src ux-gate` clean,
`vitest run` 1174/1174 across 111 files (unchanged total — one test rewritten, none added or
removed net), `vite build` clean. Fails-before: the rewritten test run against the pre-fix component
failed on the missing formula text (`"Starter 2–5 ₽200.00"` — the exact wrong number the item
describes), then passed after restoring the fix.
