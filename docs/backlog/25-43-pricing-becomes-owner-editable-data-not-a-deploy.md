# 25-43 · Pricing becomes owner-editable data, not a deploy

- **Stage**: 25
- **Status**: done — `ago-chat#256`, `ago-console#194`. Three open questions answered by
  the author, 2026-09-10, recorded below.
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

**Stated explicitly, because it changes the shape**: this is for **every** paid resource, not only
the ones that already have a settled number today. The author's own reason for wanting this dynamic
in the first place — not having to decide real figures before the business actually opens — only
holds if adding a new sellable thing later needs no schema change and no redeploy of its own, the
identical problem this item already exists to solve for a *changed* number.

## The three questions, and they are the author's — all answered 2026-09-10

**1. Who registers a new priceable resource — code, or the owner directly?** Decided: **code
registers the resource's own key** (a developer adds it, the same moment they build whatever feature
it prices), **the owner only ever sets or changes the Rouble figure for a key that already exists.**
A fully owner-driven catalogue (inventing an entirely new SKU with no code change at all) was
considered and rejected — real freedom, at the cost of nothing in the system ever being sure a given
key actually corresponds to a real, built capability.

**2. Can a resource exist with no price at all? Decided: yes, and it is the ordinary case, not an
edge one.** "No price set" means **built, not yet for sale** — a developer can ship a priceable
resource's own key the day the feature ships, entirely independent of whether the business has
decided to charge for it yet, or how much. A resource is never required to carry a placeholder number
just to exist.

**3. Do the tariff plans themselves (Free/Business, the seat ladder/bands) become owner data too, or
only the numbers inside them? Decided: only the numbers.** `SubscriptionTierBands`'s own shape — the
plan names, `MinSeats`/`MaxSeats`/`BaseSeats`, which band a seat count resolves to — **stays in
code**; it is the logic that decides eligibility and grouping, not a number. Only the Rouble figures
attached to an already-defined key move to owner data. Reopening the ladder's own shape as data too
was considered and set aside as real, separate scope with no bearing on this item's own promise.

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

- **One generic, string-keyed price mechanism — not a named field per resource.** `BaseSeatPriceRub`,
  `PricePerExtraSeatRub`, and whatever `25-41`'s own Administrator charge would otherwise have added
  as a third named property are exactly the shape that needs a schema/code change for every new
  priced thing. Instead: a resource key (a plain string a developer chooses when they build the
  feature — `"seat-base"`, `"seat-extra"`, `"admin-extra"`, and whatever a future AI add-on or
  channel names itself) maps to a versioned price, following `adr/0114`'s own shape (a version, an
  effective instant, no in-place edit of a published value — a correction is a new version). A new
  priceable thing needs a new key, never a new column or a new C# property.
- **A key with no published version is valid and expected** — "not yet for sale," per the second
  decision above. Every charge site must treat "no price found for this key" as a real, refuse-to-
  charge outcome, never a crash and never a silent zero.
- **A platform-owner surface to publish a new price version for an existing key** — `25-20`'s existing
  price-list screen is currently read-only; this is the natural place a write action belongs,
  following whatever UI precedent `24-02`'s own document-publish action already established for the
  identical "publish a new version" shape. This surface only ever picks among keys the code has
  already registered — it does not let the owner type an arbitrary new key into existence, per the
  first decision above.
- **`SubscriptionTierBands`'s own shape stays in code** — plan names, seat-band boundaries, which
  band a seat count resolves to. Only the Rouble figure attached to each already-defined key becomes
  owner data, per the third decision above.
- **Every real charge site reads the currently-effective version, by key, at the moment it charges** —
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
- **"No price for this key" must refuse the charge cleanly, never crash and never charge zero.** A
  key that exists in code but has never had a version published is the ordinary state for something
  "built, not yet for sale" — every charge site must read that as a real, named refusal a caller can
  act on, not an unhandled exception or (far worse) a successful charge of nothing.
- **The key itself is still a developer's decision, not the owner's.** Do not build a screen that
  lets the platform owner type a brand-new key into existence — the first decision above is explicit
  that a key without a corresponding built feature is meaningless, and a screen that allows one
  invites exactly that.

## Out of scope

- Writing or deciding what any specific price *is* — that stays `ago-business`'s and the platform
  owner's, this item only builds the mechanism that lets a decision already made become effective
  without a deploy.
- A tenant-facing "price is changing soon" notice, or any commercial policy about how much notice a
  price change needs — a real question, not this item's to answer.

## Done when

- [x] Every real tariff number (seat base/marginal, per-Administrator, any other priced resource) is
      owner-editable data, keyed generically and published as a new version rather than edited in
      place — no compile-time constant or `appsettings` value decides a real charge any more, and a
      new priced resource never needs a schema change to become priceable.
      *(Seat base/marginal — the only two real tariff numbers that exist in code today — are fully
      converted: `BillingOptions.BaseSeatPriceRub`/`PricePerExtraSeatRub` are removed outright, not
      deprecated. "Per-Administrator" has no charge site to convert yet — that is `25-41`'s own,
      still-unbuilt item — so this box is satisfied for every tariff that is real today; `25-41` gets
      the mechanism already built, at the cost of registering one more key, never a new column.)*
- [x] A platform owner can publish a new price version for an existing key without a code change or a
      redeploy — and cannot invent a new key from that same surface.
- [x] A key with no published version refuses any charge attempt cleanly and namedly, proven by a
      test — never a crash, never a zero-amount charge.
- [x] Every charge site reads the currently-effective version, by key, at the moment it charges,
      proven by a test that changes the effective price mid-flow and shows the charge already in
      progress is unaffected while the next one picks up the new value.
- [x] A completed charge can be read back showing the exact price version it was charged under, proven
      by a test that changes the price after a charge and shows the historical charge's own record is
      unchanged.

## Outcome

Shipped as `ago-chat#256` and `ago-console#194`, both independently re-verified (exact test counts
below) before merging. No `ago-deploy` change was needed (the mechanism reads Postgres,
not configuration) and no ADR was written — this item explicitly reapplies `adr/0114`'s own already-decided
versioning shape to a second domain rather than making a new architectural decision; `25-29` needed no ADR
for the identical reason when it first hand-corrected these numbers.

**Mechanism**: `PricedResource`/`PublishedPriceVersion` (`Ago.Chat.Domain`) mirror `Document`/
`PublishedDocumentVersion` structurally — an aggregate root holding `LastSequence` and an EF Core
optimistic-concurrency token (`xmin`), owning an insert-only, never-mutated list of published child
versions. `PriceKey` mirrors `ModuleKey`'s shape-only validation; the *closed registry* of legitimate
keys (`PricedResourceKeys.IsKnown`, currently `seat-base`/`seat-extra`) is checked in exactly one place,
`PublishPriceVersionHandler`, never in the value object or the aggregate's own factory — every other
reader of an already-legitimate `PriceKey` stays free of that check.

**Where this needed to go further than `adr/0114`'s own shape**: `ChangeSubscriptionSeatsHandler`'s
upgrade proration reads two *different* methods for "old" vs "new" price — `FindVersionAsync` against
the subscription's own stored `BaseSeatPriceVersion`/`ExtraSeatPriceVersion` for what the tenant is
already paying, and `FindCurrentAsync` for what the upgraded seat count will cost going forward. Reading
`FindCurrentAsync` for *both* (the natural-looking shortcut) would have silently repriced an
already-paid period the moment the catalog's price changed between a charge and a later upgrade — found
while wiring the handler, not from a failing test; a dedicated regression test
(`HandleAsync_WhenThePriceChangesAfterTheLastChargeButBeforeThisUpgrade_...`) now pins the correct
behaviour and was proven to fail against the naive version.

**Migration** (`Stage25AddPricedResourceCatalog`, applied and verified against the local Postgres):
creates `priced_resources`/`published_price_versions` and two new `billing_subscriptions` columns
(`base_seat_price_version`/`extra_seat_price_version`), seeds `v1` for both seat keys at the exact
figures `25-29` already hand-corrected to (490₽/200₽), and backfills every pre-existing base
subscription row's own two new columns to `1` (an option row's own convention stays `0`,
"meaningless for an option row") — without the backfill, the very next seat-count upgrade for an
already-`Succeeded` subscription would resolve `FindVersionAsync(key, 0)` to `null` and throw, a real
regression on data this deployment already has, not a theoretical one.

**Console**: `OwnerPricingPage.tsx` gained a "Priced resources" panel and `PricedResourcePanel`
component — one form per registered key, closed behind a toggle once a version already exists,
mirroring `DocumentsPage.ConsentDocumentPanel`'s own shape. `25-42`'s own seat-formula display bug on
this same page was left untouched, as instructed. Found and fixed while writing this panel's own
tests: the success/error alerts originally lived inside the auto-collapsing form (copied verbatim from
`ConsentDocumentPanel`), which means they would never paint for a key that already had a version —
`ConsentDocumentPanel`'s own tests never catch this because they only ever publish a document's *first*
version, where the form never auto-collapses at all. The alerts now render outside the collapsible
region.

**Wire compatibility**: `OwnerPricingResponse`/`OwnerSeatPricingDto`'s existing fields (including the
already-known-stale `PricePerSeatRub`/`25-42` display bug) are unchanged; `PricedResources` is a new,
additive field. The new write route is `POST /api/v1/owner/prices/{key}/versions`.

**Verification**: `ago-chat` — `dotnet format --verify-no-changes` clean; `dotnet build -c Release`
0 warnings/0 errors; `dotnet test -c Release`: Domain.Tests 616/616, Application.Tests 1067/1067,
Architecture.Tests 44/44, Integration.Tests 1095/1095 (against a real Postgres container),
Concurrency.Tests 73/75 (2 pre-existing, unrelated skips), FakeCrm.Tests 21/21. `ago-console` —
`tsc -b --noEmit` clean, `eslint` clean, `vitest run` 1174/1174 across 111 files, `vite build` clean.
Every new behavioural test proven against a deliberately-reintroduced bug first (fails-before), then
against the real fix.
