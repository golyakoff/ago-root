# 25-43 · Pricing becomes owner-editable data, not a deploy

- **Stage**: 25
- **Status**: ready
- **Depends on**: `25-29` (the current formula this item moves off of compile-time constants),
  `25-20` (the owner's own price-list screen, today read-only, the natural home for the write side)
- **Found**: 2026-09-10, the author's own request, while `25-29`/`25-41`/`25-42` were still fresh —
  every one of them just hand-corrected a number that lives in code or `appsettings`, and the next
  price change would need the identical PR-and-redeploy cycle again

## What is actually true today

Every real Rouble figure this product charges lives in one of two places, and both need a code
change and a redeploy to move: `BillingOptions.BaseSeatPriceRub`/`PricePerExtraSeatRub` (config,
bound at startup, `ValidateOnStart()`, ships no default on purpose) and `SubscriptionTierBands`'s own
compile-time constants (`BaseSeats`, `MinSeats`, `MaxSeats`, `FreeAdminsIncluded`,
`BusinessAdminsIncluded`). `25-29` corrected these once, by hand, against `ago-business 0012`; the
next time the business changes a price, the same PR-review-merge-redeploy cycle runs again for a
fact that has nothing to do with the code's own correctness.

## The author's own instruction

**All tariffs come out of constants and become a platform-owner setting.** When a price changes:
**everything already paid for in advance keeps running at the price it was actually charged; only a
new charge — a new purchase, or the next renewal — picks up the changed price.** Nothing already paid
is ever retroactively repriced.

## Why this is not a small config-vs-code swap

The grandfathering requirement is the actual design problem, and it is the same shape this codebase
has already solved once: `adr/0114` made a tenant's own consent-document text **data with a version**,
specifically so a wording correction is one call rather than a deploy, and specifically so an
existing acceptance stays valid against the version it was actually given — a later edit never
rewrites what already happened. A price is the identical shape: a currently-effective value the
platform owner can change, and a historical charge that must keep reading whatever value was current
*when it was charged*, never the value that is current *now*.

**The mechanism that already makes this true for free, if built correctly**: `ProcessSubscriptionRenewalHandler`
and `CreateCheckoutSessionHandler` already only compute a charge at the moment they actually charge —
neither one re-derives or re-validates a past charge. If the price they read at that moment comes from
owner-editable data instead of a compile-time constant, an already-paid period is untouched by
construction, because nothing ever revisits it. **The risk this item exists to guard against is the
opposite direction**: a naive implementation that stores "the current price" as a single mutable row
would tempt a future change into reading that row for something other than a live charge — a report,
a historical statement, an already-issued invoice's own display — and silently reprice the past. The
fix is the same one `adr/0114` already took: never overwrite a price, publish a new version instead,
and let every historical read that needs "what did this charge, when" pin itself to a version rather
than to "whatever the row says today."

## Scope

- **Every tariff number this product charges** — seat base/marginal price, the per-Administrator
  charge `25-41` is building a purchase path for, and any future tier or option price — becomes
  versioned, owner-published data, following `adr/0114`'s own shape (a version, an effective
  instant, no in-place edit of a published value — a correction is a new version).
- **A platform-owner surface to publish a new price version** — `25-20`'s existing price-list screen
  is currently read-only; this is the natural place a write action belongs, following whatever UI
  precedent `24-02`'s own document-publish action already established for the identical "publish a
  new version" shape.
- **Every real charge site reads the currently-effective version at the moment it charges** —
  `CreateCheckoutSessionHandler`, `ProcessSubscriptionRenewalHandler`, and wherever `25-41`'s own
  Administrator purchase path lands — never a cached or cross-request-stale copy for a decision that
  moves money (`CLAUDE.md` rule 8).
- **A completed charge remembers which price version it was actually charged under** — so a later
  price change can never be observed to have altered a period a tenant already paid for, and so
  `25-20`'s own screen (or a future billing-history view) can show "what this specific charge was"
  honestly rather than recomputing it from whatever is current now.

## Where this is likely to go wrong

- **Do not let "the current price" be a single row a write overwrites in place.** That is exactly the
  shape that reprices history the moment a report or a stale cache reads it at the wrong instant —
  the entire reason this item cites `adr/0114`'s versioning shape rather than a simpler key-value
  settings table.
- **A tenant mid-renewal when the price changes is not a special case to invent a rule for** — the
  renewal reads whatever version is effective at the instant it fires, the same as any other charge.
  Nothing here needs a grace period or a manual reconciliation; the ordinary "read fresh, at the
  moment of the decision" discipline already produces the correct, honest answer.
- **This item does not decide who may publish a version, beyond "the platform owner"** — a future
  question about delegating this to `ago-business` directly (skipping an engineer entirely) is real
  and is explicitly out of scope here; this item only moves the number out of code, not out of the
  owner's own hands into someone else's.
- **Sequencing with `25-41`**: building `25-41`'s Administrator-purchase migration against the
  *current* hardcoded-constant shape, only to redo it once this item lands, is real rework — read
  this item's own state before starting `25-41`'s own migration and decide which lands first, rather
  than discovering the collision mid-build.

## Out of scope

- Writing or deciding what any specific price *is* — that stays `ago-business`'s and the platform
  owner's, this item only builds the mechanism that lets a decision already made become effective
  without a deploy.
- A tenant-facing "price is changing soon" notice, or any commercial policy about how much notice a
  price change needs — a real question, not this item's to answer.

## Done when

- [ ] Every real tariff number (seat base/marginal, per-Administrator, any other priced resource) is
      owner-editable data, published as a new version rather than edited in place — no compile-time
      constant or `appsettings` value decides a real charge any more.
- [ ] A platform owner can publish a new price version without a code change or a redeploy.
- [ ] Every charge site reads the currently-effective version at the moment it charges, proven by a
      test that changes the effective price mid-flow and shows the charge already in progress is
      unaffected while the next one picks up the new value.
- [ ] A completed charge can be read back showing the exact price version it was charged under, proven
      by a test that changes the price after a charge and shows the historical charge's own record is
      unchanged.
