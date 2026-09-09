# 25-20 · The owner gets a price list screen

- **Stage**: 25
- **Status**: done — `ago-chat#243` + `ago-console#185`; see the honest finding below about what the
  screen actually surfaces
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

## What the screen actually found, built while building it

Only per-seat pricing has any real backing in code or deployment config
(`BillingOptions.PricePerSeatRub`, `SubscriptionTierBands`). Channel entitlements, AI add-ons and
storage-overage pricing have **zero** configuration anywhere — not merely unconfigured on this
deployment, but no configuration *key* for a billing option's price exists in the codebase at all
(`IBillingOptionEntitlementProvider` resolves only what a paid option turns on, never what it costs,
by `23-86`'s own design). The screen states this plainly rather than fabricating numbers or showing an
unexplained blank.

**A second, separate finding, not fixed here**: the code's own seat-pricing numbers are themselves
stale against `ago-business`'s current grid. `0012` (2026-09-07, supersedes `0008`) prices Business at
490₽ base for up to 3 seats + 200₽/seat beyond that (capped at 5) plus a 500₽/admin-beyond-2 charge the
code has no concept of; the code still implements `0008`'s superseded flat 590₽/seat, 3–100-seat bands
(`13-02`/`13-08`, built before `0012` existed). This screen makes that drift visible to the owner for
the first time — which is the item's whole point — but does not fix the pricing logic itself. Flagged
as a separate follow-up rather than folded in here, since fixing the actual billing calculation is a
larger, differently-scoped change than a read-only display screen.

## Done when

- [x] An owner-only screen lists every currently-paid capability and its price, read from the same
      source the billing/entitlement code itself uses — not a hand-copied number. Per-seat pricing is
      real; channel/AI/storage pricing is shown honestly as not-yet-configured anywhere in the system.
- [x] The screen is unreachable by anyone other than the platform owner, proven by a test.
