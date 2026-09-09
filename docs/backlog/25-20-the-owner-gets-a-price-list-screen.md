# 25-20 · The owner gets a price list screen

- **Stage**: 25
- **Status**: ready
- **Depends on**: `ago-business`'s tariff grid (`docs/decisions/0012-*.md`) is the source of truth for
  every number this screen shows
- **Found**: 2026-09-09, the author's own request

## What is actually true

Every price this system charges — the tier grid, per-seat and per-administrator costs, channel
entitlements, the AI add-ons, storage — exists only in `ago-business`'s own decision documents. Nobody
signed in as the platform owner can see the current numbers in the product itself; reading them means
opening a private repository.

## Scope

- A new owner-only screen, reachable only by the platform owner (the same authorization boundary
  `/owner`'s other screens already use), listing every currently-paid capability and its price:
  tiers, per-seat/per-administrator costs, each channel's entitlement price, the AI add-ons, storage
  pricing beyond the included allowance.
- **Read-only for now.** This item does not build editing or a write path — it surfaces what
  `ago-business`'s grid already says, in the product, for the owner to check against reality. Whether
  prices become owner-configurable in the product itself (rather than fixed in deployment
  configuration) is a separate, larger question this item does not answer.
- Source the numbers from wherever the backend already resolves a price for billing purposes (`22-32`,
  `23-86`, or whatever deployment configuration already carries the grid) — not retyped from the
  `ago-business` document by hand, which would drift from the code's own numbers the first time either
  changes.

## Out of scope

- Showing prices to a *tenant* before they buy, on any purchase or upgrade screen. The author's own
  words: that is a separate item, once this one exists.
- Any write path for changing a price from this screen.

## Done when

- [ ] An owner-only screen lists every currently-paid capability and its price, read from the same
      source the billing/entitlement code itself uses — not a hand-copied number.
- [ ] The screen is unreachable by anyone other than the platform owner, proven by a test.
