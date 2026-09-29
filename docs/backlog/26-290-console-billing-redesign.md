# 26-290 — Redesign the console billing page around three user cases

**Status:** design (this document is the deliverable; no code in this item)
**Author trigger (2026-09-29):** after the first real test purchase worked, `office.agochat.ru/settings/billing`
is confusing — lots of empty space, still needs scrolling, and it is essentially two "buy" buttons,
while what a real user actually needs is missing.

Redesign around exactly three questions a paying tenant asks:

1. **What's paid now, and until when.**
2. **What can I buy, and for how much.**
3. **Next charge: how much, when — and can I pay early.**

---

## 0. What is on the page today, and why it reads as empty-and-scrolly

`ago-console/src/pages/BillingPage.tsx` renders a vertical `ago-stack` of **six** `Panel`s, each a
column of `<p><strong>label</strong>: value</p>` rows:

- **Plan panel** — `tierDisplayName` + a stack of status `Alert`s (pending / failed / past-due /
  cancel-requested / pending-downgrade).
- **Operator seats panel** — eight rows: seats used, seat limit, free seats, purchasable range, base
  price, base seats, extra-seat price, billing-period days.
- **Administrator seats panel** — five rows.
- **Add seats panel** — a stepper + "Добавить".
- **Reduce seats panel** — a stepper + "Уменьшить" (only when `Succeeded`).
- **Add-administrator panel** — a stepper + "Добавить".
- Plus a quiet cancel panel.

That is ~20 label/value rows and up to five stacked forms, one under another, each in its own bordered
card with its own padding. The "empty space + scrolling + two buy buttons" complaint is exactly this
shape: the information density is low (one fact per line), the *purchasable* actions are buried below a
wall of read-only pricing facts, and nothing answers "what will I be charged next, and when." The fix
is not more data — it is **regrouping the data that already exists into three dense cards** and adding
the two facts that are genuinely missing (connected-channel count, next-charge amount).

There is also a **real functional gap**: the connected-channel add-on purchase (`26-278`) shipped
backend-only. `billingApi.ts` has **no** `purchaseChannelAddOn` client function and `BillingPage.tsx`
has **no** channel-purchase control at all. Case 2 must add it.

---

## 1. Case 1 — "What's paid now, and until when"

A single **Current plan** card, read at a glance. Every field below is already on the wire from
`GET /api/v1/sites/{siteId}/billing/status` (`GetBillingStatus.BillingStatusDto`) **except the last
one**.

| Field shown | Source (today) | Notes |
|---|---|---|
| Tier name | `tierDisplayName` | "Solo" / "Business" — never the raw `tier` enum. |
| Status badge | `latestSubscription.status` | `Pending` / `Succeeded` / `Failed` / `PastDue` / `Lapsed`, rendered as active / past-due / pending badges. `null` subscription ⇒ free tier. |
| Operator seats | `seatsUsed` / `seatLimit` | "used of limit"; `seatPricing.freeSeatsIncluded` as the sub-label "N included free". |
| Administrators | `adminsUsed` / `adminLimit` | included-in-tier = `adminLimit − extraAdministratorsPurchased`; bought beyond = `extraAdministratorsPurchased`. |
| **Connected channels** | **MISSING — see below** | count of purchased channel add-on option rows. |
| Paid until | `latestSubscription.currentPeriodEnd` | ISO-8601 → render in the viewer's IANA zone (`formatDateStamp`, already imported). |
| Scheduled changes | `cancelRequested`, `pendingSeatCount` / `pendingTier` | keep the existing "cancels on …" / "downgrades to N at renewal" notices, folded into this card as small inline notes rather than separate full-width `Alert` panels. |

### What is missing for Case 1

**Connected-channel count is not exposed.** The status DTO carries nothing about the site's channel
add-ons, and `IBillingSubscriptionRepository` has no method that lists or counts a site's *option*
subscriptions — only `GetBaseForSiteAsync` (the one base row). Channel add-ons are separate
`BillingSubscription` rows with `IsOption == true` and an `OptionKey` of `channel-<kind>`
(`ChannelEntitlementOptionKeys.For`). So showing "N channels connected / which kinds" requires a
**backend addition**:

- add `Task<IReadOnlyList<BillingSubscription>> ListOptionsForSiteAsync(SiteId, CancellationToken)`
  (or a narrower projection — count + kinds + each option's `CurrentPeriodEnd`) to
  `IBillingSubscriptionRepository` and its Postgres adapter, and
- extend `BillingStatusDto` with a `channels` block (count, and per-kind rows for the next-charge and
  connected-list display).

This is additive per `api-design.md` ("add within a version, never remove or rename"), the identical
move `25-23` already made when it added the Administrator/seat-pricing fields. **It is cut out of
slice 1** (see §5) — slice 1 shows channels only if the count is cheaply derivable, otherwise defers
the channel *display* to the same slice that adds the channel *purchase* preview.

Everything else in Case 1 ships with **zero backend change**.

---

## 2. Case 2 — "What can I buy, and for how much"

A single **Add to your plan** card: a compact list of the buyable dimensions, each with its unit
price and a one-line prorated preview, each with its own inline stepper + buy button. This replaces
the three separate stepper panels (add seats / add admin / — and the currently-absent add-channel).

| Buyable | Unit price (source) | Endpoint | Proration shape |
|---|---|---|---|
| + Operator seat | `seatPricing.baseSeatPriceRub` (490) covers `baseSeats` (3); `seatPricing.pricePerExtraSeatRub` (200) each seat beyond | `POST …/checkout-sessions` (first purchase → ЮKassa redirect) or `POST …/subscriptions/{id}/seats` (change in place) | banded: `ComputeSeatPriceRub(seats, base, extra)`, delta `× remainingDays / periodDays` |
| + Administrator | `adminExtraPriceRub` (1000, flat) | `POST …/subscriptions/{id}/administrators` | flat: `(newCount·new − oldCount·old) × remainingDays / periodDays` |
| + Channel | **`channel-addon` price (100) — MISSING from DTO** | `POST …/subscriptions/{baseId}/channels` (**no console client fn yet**) | flat, no old price: `full × remainingDays / periodDays` |

Keep the existing "reduce seats" (scheduled downgrade, no charge) and "cancel" as a small secondary
area — they are not "buy" actions and should not compete with Case 2 for attention.

### The prorated "you pay X now, included until <date>" preview

**No preview endpoint exists.** Proration is computed inside each purchase handler at purchase time
(`PurchaseAdministratorSlotHandler`, `PurchaseChannelAddOnHandler`, `ChangeSubscriptionSeatsHandler`)
and only ever returned *after* the charge, as `proratedAmountRub` on the success response. There is no
read that answers "what would I pay if I bought this now" before committing.

Two ways to produce the preview:

**(a) Client-side, from the catalog + period end.** The client already receives `baseSeatPriceRub`,
`pricePerExtraSeatRub`, `adminExtraPriceRub`, `currentPeriodEnd`. Given the current clock it can
compute `remainingDays / periodDays` and multiply. **This works cleanly only for the channel add-on**
(flat, no old-price term). It is *unsafe* for seats and administrators:

  - Seats need `ComputeSeatPriceRub`'s **banded** formula (base covers 3, extra above). Re-implementing
    it in TypeScript re-copies a Domain formula — the exact drift `25-23`'s "От 2 до 100 мест" stale
    copy is the cautionary tale for.
  - Administrators need the **old price version** the subscription was last charged at
    (`BillingSubscription.AdminExtraPriceVersion`, netted in `PurchaseAdministratorSlotHandler`). That
    version is **not on the wire** and must not be — so the admin delta is not computable client-side
    at all.

**(b) A server-side preview read** behind the price-catalog port: a `GetPurchasePreview` Application
query taking `(siteId, dimension, requestedQuantity)` and returning `{ proratedAmountRub,
includedUntil }`, computed by the *same* code paths the purchase handlers already use (extract the
proration arithmetic into a shared Application helper the handler and the preview both call). This is
the correct home for the seat and admin previews.

**Recommendation (teaching-mode, §7):** ship a single server-side preview endpoint for all three
dimensions. It keeps the banded seat formula and the admin old-price netting in one place, on the
correct side of the dependency rule, and makes the three previews render identically. The channel
preview *could* be client-side, but splitting one dimension into a different computation path for a
few saved lines of code is not worth the divergence. **The preview is cut out of slice 1** — slice 1
shows the *unit* price and a plain "billed prorated for the days remaining in your period" note
without the exact figure; the exact prorated figure arrives with the preview endpoint as its own item.

### What is missing for Case 2

1. `channel-addon` price is not in `BillingStatusDto` → add `channelAddOnPriceRub` (nullable, honest
   `null` when the key is unpublished, exactly as `adminExtraPriceRub` already is). One extra
   `IPriceCatalogRepository.FindCurrentAsync(ChannelAddOnPricing.ChannelAddOnKey)` read in
   `GetBillingStatusHandler`.
2. `billingApi.ts` needs a `purchaseChannelAddOn(accessToken, siteId, baseSubscriptionId, channelKind)`
   client function + a `ChannelKind` type mirror, and `BillingPage` needs the channel-purchase control
   (the console half of `26-278`).
3. The proration **preview** endpoint (option (b) above) — its own item.

---

## 3. Case 3 — "Next charge: how much, when, and pay-early"

A single **Next renewal** card: the upcoming amount, the date, and a pay-early action.

| Field | Source | Notes |
|---|---|---|
| Renewal date | `latestSubscription.currentPeriodEnd` | already on the wire. |
| Renewal amount | **NOT computed anywhere — see below** | base + seats + admins + channels at full (non-prorated) price. |
| Pay early / renew now | **no command exists — see below** | new backend slice. |

### Next-charge amount is not returned, and is more than one row

`ProcessSubscriptionRenewalHandler` shows exactly what a renewal charges the **base** row:

```
seatAmount  = ComputeSeatPriceRub(RequestedSeats, basePrice, extraPrice)
adminAmount = ExtraAdministratorsPurchased × adminPrice   (0 if none)
overage     = variable, metered attachment-download overage (only some tenants, unpredictable)
baseCharge  = seatAmount + adminAmount + overage
```

**But each channel add-on is a *separate* `BillingSubscription` option row that renews on its own
schedule**, charging the flat `channel-addon` price (100) per row via the handler's `IsOption` branch.
So there is no single "next charge" — there is the base row's next charge plus each option row's next
charge. Option periods are aligned to the base at purchase time (`PurchaseChannelAddOnHandler` passes
the base's `periodEnd`), so in the common case they renew together and the displayed total is:

```
next charge ≈ baseCharge(excluding overage) + (channelCount × channelAddOnPrice)
```

Recommendation for the display: show the **predictable** recurring total
(`seatAmount + adminAmount + channelCount × channelAddonPrice`) and label it as "your recurring
subscription", explicitly **excluding** metered download overage (which is variable and only known at
renewal). Do not fabricate an overage figure — `CLAUDE.md`: "do not invent numbers."

To compute this the backend must expose either the components or the total. Cheapest honest option: a
computed `nextChargeRub` (recurring only, overage excluded) added to `BillingStatusDto`, computed in
`GetBillingStatusHandler` from the fields it already reads plus the channel count/price. This depends
on the same `ListOptionsForSiteAsync` addition Case 1 needs. **Cut out of slice 1**; the *display half*
of Case 3 that ships in slice 1 is just the renewal **date** (already on the wire) with the amount
deferred.

### Pay-early / renew-now needs a new backend slice

Renewal today is **automatic and worker-driven**: `Ago.Chat.Worker` sweeps `ListDueForRenewalAsync`
and calls `ProcessSubscriptionRenewalHandler`, which only acts when `IsDueForRenewal(now)` /
`IsRetryDue(now)`. There is **no** operator-triggered "charge me now and extend the period" path. A
manual pay-early is a genuinely new use case:

- a `RenewNow` (pay-early) Application command: guard `Succeeded` + stored payment method, charge the
  stored method for the full recurring amount now, and **extend** `CurrentPeriodEnd` by
  `PeriodLength` (the applier's own extend-on-success path, reused);
- the tricky part is *semantics*, not plumbing: does paying early on day 3 extend from today or from
  the current period end? To avoid a service gap while not letting a tenant lose paid days, it should
  extend from `CurrentPeriodEnd` (add one period to the end), and it must be **idempotent** against a
  double-click and against the automatic sweep firing on the same day (reuse the deterministic
  `renewal:{id}:{date}` idempotence key shape the renewal handler already uses);
- and it must decide whether channel option rows are paid early too, or only the base — simplest first
  cut is base-only, with option rows left to their own schedule.

**Flag:** this is not a display tweak; it is a new vertical slice (Domain extend-period method or
reuse, Application `RenewNow` command + handler, endpoint, applier, tests). The redesign can ship
Cases 1 + 2 and the **display half** of Case 3 (renewal date, and the amount once the next-charge
field lands) with no pay-early button, then add pay-early as its own item.

---

## 4. Compact layout — three cards, no wall of rows

Structure (not pixel CSS):

- **Three cards**, ideally a responsive grid: on a wide viewport a row of three (or Case 1 full-width
  on top, Cases 2 + 3 side by side below); on narrow, stacked. This alone kills most of the scroll —
  the current page is one narrow column of six full-width panels.
- **Card 1 — Current plan.** A tight definition grid (label left, value right, two or three columns of
  pairs), not one `<p>` per fact. Status as a coloured badge in the card header. Scheduled
  changes as one small inline line, not a stack of full-width `Alert`s.
- **Card 2 — Add to your plan.** A compact list, one row per buyable dimension: name, unit price, a
  small stepper, a buy button, and the one-line prorated note. Reduce-seats and cancel demoted to a
  small "manage" footer/secondary section.
- **Card 3 — Next renewal.** Amount (recurring, overage-excluded, labelled), date, and — once its
  backend lands — the pay-early button. Until then, date + a note that renewal is automatic.
- Keep the honest **pending-poll** mechanism unchanged (`usePollUntilCheckoutSettled` while status is
  `Pending`) — the redesign is layout + the two missing facts, never a change to the payment-truth
  discipline.

Move all pure *reference* pricing (base-seat price, extra-seat price, billing-period days, purchasable
range) out of a standalone panel and into the point of use: the unit prices belong in Card 2 next to
each buy control; the period length belongs in Card 3 next to the renewal date. No dimension gets a
row just to state a number nobody is about to act on.

---

## 5. Slice plan (rule 15 — one promise that lands green)

**Slice 1 — the redesign, on data that already exists.** *Promise: the billing page shows the current
plan (tier, seats, admins, status, paid-until) and the buyable add-ons with their unit prices, in
three compact cards, and every existing purchase still works.*
This is a pure `ago-console` change: regroup `BillingPage.tsx` into three cards, render only fields
already on the wire, wire the existing seat/admin purchase + reduce + cancel controls into the new
layout. **Includes** adding the **channel add-on purchase control** *only if* the channel price and a
`purchaseChannelAddOn` client fn are available — otherwise the channel purchase moves to slice 2 with
the DTO change it depends on. Green = existing `BillingPage.test.tsx` + `ux-gate` updated for the new
structure. Ships without: connected-channel display, next-charge amount, prorated preview figures,
pay-early. **File as its own item.**

**Slice 2 — the missing status fields (backend + console).** *Promise: the billing page shows how many
channels are connected, the channel add-on price, and the recurring next-charge amount.*
Backend: `ListOptionsForSiteAsync` on `IBillingSubscriptionRepository` + Postgres adapter; extend
`BillingStatusDto` with `channels` (count/kinds), `channelAddOnPriceRub`, and `nextChargeRub`
(recurring, overage-excluded); the extra `FindCurrentAsync` read + channel-count computation in
`GetBillingStatusHandler`. Console: render them in Cards 1 and 3, and the channel-purchase control if
not already in slice 1. Green = handler integration test asserting the new fields + console render test.
**Backend + console in one worker (one cross-repo item — MEMORY: one worker per cross-repo task).**

**Slice 3 — prorated purchase preview.** *Promise: each buy control shows the exact prorated amount
and the included-until date before you commit.*
A `GetPurchasePreview` Application query behind `IPriceCatalogRepository`, sharing the proration
arithmetic extracted from the three purchase handlers; a `GET …/billing/purchase-preview` endpoint;
console renders "you pay ₽X now, included until <date>" under each stepper. Green = preview handler
unit tests matching the purchase handlers' own figures + console render.

**Slice 4 — pay-early / renew-now.** *Promise: a tenant can pay ahead to extend the period and avoid a
gap.*
A `RenewNow` command + handler (guarded, idempotent against the sweep, extends `CurrentPeriodEnd` by
one period), endpoint, applier reuse, tests; console pay-early button in Card 3 that refetches status
(Case 1 updates — period extended). Green = handler integration test (charge + period extended +
idempotent double-fire) + console render.

**Numbers to file** (ago-root queue; titles the manager assigns numbers to):
- `Console billing page: three-card redesign on existing data` (slice 1)
- `Billing status: connected-channel count, channel add-on price, recurring next-charge` (slice 2, cross-repo)
- `Billing: prorated purchase-preview read + endpoint + console` (slice 3, cross-repo)
- `Billing: pay-early / renew-now command + console action` (slice 4, cross-repo)

---

## 6. Android billing — out of scope, cross-referenced

The same three-case clarity must later reach the Android app's billing surface (MEMORY: *Android full
console parity* — the app must let tenant-admins do everything the console does). That is its **own
item**, informed by `26-289`'s SDK/payment-transport decision (a mobile store's billing rules differ
from ЮKassa's hosted redirect), and is deliberately not designed here. When it is picked up, it reuses
the same `BillingStatusDto` (and whatever slices 2–4 add to it), so keeping the backend the single
source of every figure — never a second copy of the pricing grid on the client — is what lets the
Android screen render the identical numbers without re-deriving them.

---

## 7. Teaching-mode — where proration-preview belongs, and why

A proration preview is an **Application read behind the price-catalog port**
(`IPriceCatalogRepository`), not a client-side computation. Two reasons rooted in the dependency rule
and this codebase's own history:

1. **The seat formula is banded Domain logic** (`SubscriptionTierBands.ComputeSeatPriceRub`: base
   covers 3 seats, extra above). Computing the preview client-side re-copies that formula into
   TypeScript — precisely the "second copy of the grid drifts from the source" failure `25-23` fixed
   by moving `minSeats`/`maxSeats`/prices onto the wire. The preview must call the same Domain formula,
   which means it runs server-side, in Application, reading the currently-effective price through the
   port (Domain references nothing — rule 1 — so the price *read* cannot live in Domain; the arithmetic
   that combines a Domain formula with a port-sourced price is Application's job — rule 2).
2. **The administrator delta needs the subscription's stored old price version**
   (`BillingSubscription.AdminExtraPriceVersion`), which is deliberately not on the wire. The client
   physically cannot net "what I'm already paying" against "what I'd pay" — only the server, reading
   the stored version through `IPriceCatalogRepository.FindVersionAsync`, can. So the admin preview is
   server-only by necessity, and keeping the seat and channel previews on the same server path keeps
   all three identical.

The flat **channel** add-on (full price × remaining/period, no old-price term) is the one dimension a
client *could* compute correctly from catalog + period end. It is still recommended to route it
through the same preview read: a single code path the purchase handler and the preview both share means
the figure the tenant is shown is, by construction, the figure they are charged — the alternative
(preview computed one way, charge computed another) is the kind of divergence that surfaces as a "the
price changed at checkout" bug.

---

## 8. Premises checked against source (2026-09-29)

- Status endpoint returns tier/seats/admins/pricing but **not** channel count, channel price, or
  next-charge amount — confirmed in `GetBillingStatus.cs` / `GetBillingStatusHandler.cs`.
- No repo method lists a site's option subscriptions — confirmed in `IBillingSubscriptionRepository`.
- No proration-preview endpoint; proration computed only inside purchase handlers — confirmed in
  `PurchaseAdministratorSlotHandler`, `PurchaseChannelAddOnHandler`.
- No pay-early command; renewal is worker-driven off `IsDueForRenewal` — confirmed in
  `ProcessSubscriptionRenewalHandler`.
- Console has no channel add-on purchase UI (26-278 backend-only) — confirmed in `billingApi.ts` /
  `BillingPage.tsx`.
- Prices: seat-base 490 / seat-extra 200 (`seatPricing`), admin-extra 1000 (`adminExtraPriceRub`),
  channel-addon 100 (`ChannelAddOnPricing.ChannelAddOnKey`, **not** on the status wire).
