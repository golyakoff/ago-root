# 25-101 · A platform owner can price a communication channel

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-14, the author asking why the existing owner pricing screen has nothing for
  channels — traced to a real gap, not a missing button: the price catalog itself has no entry a
  channel could ever be priced against.

## What is actually true

`adr/0151` already settled that channels are entitlement-gated and appear "in the price list" — and
`BillingSubscription`'s own remarks already model a purchased option (which a connected channel is
one instance of) as **flat-priced, no seat count, no tier band**: *"an option is priced flat, not by
seats (`adr/0151`'s own price-list reading: 'channels at +100 RUB each')"*. The domain shape for a
single, uniform per-channel price already exists, conceptually, in a doc comment.

**`PricedResourceKeys.All`** (`src/Ago.Chat.Domain/PricedResourceKeys.cs`) is the actual mechanism —
the closed, code-defined list of every `PriceKey` the platform owner's own pricing screen can show
and publish a Rouble figure for. Today it lists exactly four entries: base seats, extra seats, extra
Administrators, and download overage (`25-84`'s own `DownloadOveragePricing.OveragePerGigabyteKey`).
**No channel key exists.** `OwnerPricingPage.tsx` (`ago-console`) is already fully generic over this
list — it renders `pricing.pricedResources.map(...)`, nothing hardcoded — so a platform owner cannot
set a channel's price not because the screen refuses it, but because there is nothing in the catalog
for the screen to render.

**One price, not one per channel kind.** `ChannelEntitlementOptionKeys.cs` already maps every
`ChannelKind` (Telegram, Max, Sms, WhatsApp, Vk, Avito, Email) to its own `BillingOptionKey` for
*entitlement* purposes (`"channel-" + kind`) — but entitlement and price are deliberately separate
axes (`adr/0151`: "the deployment declares what an option turns on; it never declares what it
costs"). The author's own decision here: **a single, uniform price for "one channel," independent of
which specific channel kinds exist or how many there are** — matching `ago-business/0008`'s own
Telegram/MAX figures already being identical, and matching this item's job being the mechanism, not
a business number.

## Why this is worth its own number, and its own scope

This item is deliberately narrower than "a tenant can buy a channel." It builds only the half the
platform owner needs first in the causal chain the author stated: **the owner sets the price before
anyone can buy anything at it.** Wiring a tenant-facing purchase flow that reads this price and grants
the entitlement is a second, larger promise — its own design questions (immediate charge like
`25-41`'s Administrator purchase, or a hosted-checkout session like the seat flow; whether every
channel kind should count against the same one-channel allowance or scale with how many are
connected) are the business's own call, not assumed here, and not filed yet pending that answer.

## Scope

- Add one new `PriceKey` for a channel add-on, in its own small file following `25-84`'s own
  `DownloadOveragePricing.cs` precedent (a dedicated home for a flat, non-seat-banded price,
  rather than folding it into `SubscriptionTierBands`, which is seat-band arithmetic).
- Register it in `PricedResourceKeys.All` with a label a platform owner will actually understand
  (e.g. "price per connected channel beyond the widget itself").
- **Carry the published price through to the public landing page**, reusing the pipeline `docs/
  runbooks/landing-prices.md` (`ago-chat`) already documents rather than building a new one:
  `tools/update-landing-prices-from-db.sh` queries `priced_resources`/`published_price_versions` by
  key and needs no change — it is already generic over whatever `PricedResourceKeys` lists. What
  does need a change is `ago-landing`: `pricing.html`'s own "Not priced, because not built" table
  already carries an explicit, unpriced "More incoming channels" row
  (`data-i18n="pricingpage.soon.channels"`) waiting for exactly this — move it into the real,
  priced table with a `data-price="<the new key>"` element, the same convention every other priced
  row already uses (`agoRenderPrices` in `i18n.js` fills any element carrying a `data-price`
  attribute that matches a key in `prices.json`; it does not need new code, only new markup).
- **Fix `docs/runbooks/landing-prices.md`'s own closing section while touched** — it currently reads
  "Nothing yet — the pricing section that would read this file has not been built," which is stale:
  `agoRenderPrices` already exists and already reads `prices.json`. Docs are part of the deliverable
  (CLAUDE.md); leaving a wrong sentence next to the change that makes it wrong is not an option.
- Confirm end to end that a platform owner can publish a real Rouble figure for it through the
  existing `OwnerPricingPage` — no console changes should be needed, since that screen is already
  generic over this list; if one turns out to be needed, that is itself worth stating plainly.
- Out of scope, deliberately: anything that reads this price to charge a tenant or grant a channel
  entitlement. No `BillingSubscription` option row, no checkout, no console purchase control. This
  item's own Done-when is satisfied by the owner being able to set and see the number, nothing more.

## Done when

- [ ] `PricedResourceKeys.All` carries a channel add-on price key, and a platform owner can publish a
      real price for it through the existing pricing screen — proven against a real (or faked,
      matching this codebase's established test shape) publish call, not merely that the key exists
      in code.
- [ ] Once published, the price reaches the public landing page: `tools/update-landing-prices-from-db.sh`
      picks it up with no code change (confirm this by actually running it against a real published
      price, not by assuming the query is generic), `pricing.html`'s channel row moves out of the
      "not priced, because not built" table into the real priced table via a `data-price` element, and
      `landing-prices.md`'s stale closing sentence is corrected.
