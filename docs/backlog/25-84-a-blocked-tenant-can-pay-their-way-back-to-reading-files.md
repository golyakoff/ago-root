# 25-84 · A blocked tenant can pay their way back to reading files

- **Stage**: 25
- **Status**: done — both open questions decided and recorded below, and in `adr/0174`. Independently
  re-verified by the managing session before merging: `dotnet build`/`format --verify-no-changes`
  clean in `ago-chat` (after a rebase onto `25-91`, which needed two new DI registrations in that
  item's own test host — applied and re-verified); full `dotnet test` — Domain 707/707, Application
  1317/1317, FakeCrm 21/21, Architecture 46/46, Concurrency 88/88, Integration 1267/1267 (the +5 over
  the worker's own claimed 1262 is exactly `25-91`'s own newly-merged tests, picked up by the
  rebase — the math checks out exactly). `ago-console`: typecheck/lint clean, `npx vitest run`
  1432/1432, matching the worker's own count.
- **Depends on**: `25-83` — the hard block this item exists to lift. Building this before `25-83`
  merges would have nothing to attach a payment to.
- **Decision**: the author's, reached in dialogue with the managing session, 2026-09-14 — the same
  conversation that produced `25-83`; see that item for the enforcement half.
- **Found**: the same place `25-83` was — `23-82`'s own deferred ceiling decision, split in two once
  the shape of "what happens at the ceiling" turned out to be its own real feature, not a detail of
  enforcing the ceiling itself.

## The shape, decided 2026-09-14

**Metered, not a flat unlock.** 100 ₽ per gigabyte over the hard threshold, platform-owner
configurable (a default, not a hardcoded constant — the same per-tier-editable shape `25-83`'s own
thresholds already take, though this price is deployment-wide rather than per-tier unless the owner
says otherwise when this is built). This is real usage-based billing, not a single toggle-purchase —
say this plainly, because it changes what "metered" costs to build: the charge has to be computed
from an actual gigabyte count, not from a boolean.

**Valid until the end of the current calendar month, however little of it remains**, and does not
carry into the next month — a tenant who pays on the 28th gets three days of unblocked reading, not a
refund or a rollover credit. The counter (and the threshold itself) resets with the new month, the
same boundary `23-82`'s own `period_month` bucketing already uses.

**Paying unblocks immediately.** Whatever mechanism actually applies the charge, the tenant's next
presigned GET after payment succeeds without waiting for any billing cycle boundary.

**A platform-owner-only, per-tenant toggle decides how the charge is applied — not a tenant-facing
setting.** Two modes:
- **Auto-bill** (the recommended default, per the author's own reasoning: "planned expenses beat
  surprise ones" — a tenant would rather see this on next month's regular invoice than have to notice
  and act on a block mid-month): crossing the hard threshold auto-applies the per-GB charge as it
  accrues and keeps the tenant unblocked, with the accumulated charge appearing as a line item on
  their next regular invoice. No explicit action from the tenant at the moment of crossing.
- **Manual**: crossing the hard threshold blocks as `25-83`'s own base case describes, and the
  tenant/operator sees the same "this is limited, pay to continue" state everywhere `25-83`'s own
  block is visible (console banner, the in-conversation system message) with a real, immediate
  checkout — the same purchase mechanism this codebase already uses for a module or a seat, not a new
  payment flow invented for this one case. Paying unblocks the same way as the auto-billed path.

Both modes ultimately charge the same 100 ₽/GB meter; the toggle decides *when* the tenant commits to
paying it, not *whether*.

## Where this is likely to go wrong

- **This is the item that turns `23-82`'s own proxy egress counter into a real, disputable invoice
  line.** `25-83`'s own Done-when already asks that the proxy nature be stated rather than inherited
  silently — this item is where that stops being a footnote and starts being a number a tenant could
  reasonably ask to see justified. Decide, and state, whether the invoice line shows the raw
  gigabyte figure this meter produced, or something reconciled against the storage provider's own
  egress bill (`23-82`'s own "ours is a proxy, theirs is the truth" distinction) before this ships —
  billing off a number this codebase has already called imprecise, without saying so to the tenant,
  is the shape of dispute this item should not manufacture on day one.
- **Auto-bill accrues a debt with no natural ceiling of its own.** A tenant on auto-bill who keeps
  getting downloaded from (their own visitors, not necessarily anything they did) could accrue a large
  next-invoice charge with nothing stopping it mid-month, by design — that is the whole point of
  "unblocked." Whether the platform owner wants any secondary cap on the auto-bill path (a second,
  higher hard stop even auto-bill cannot cross) is a real question this item should ask before
  building, not assume either way.
- **The existing purchase/checkout mechanism this item reuses for the manual path was built for a
  one-time, fixed-price purchase (a seat, a module).** A metered amount computed at the moment of
  payment (how many GB over, right now) is a different shape than "buy one of these" — read that
  mechanism's own code before assuming it takes a variable amount without a change of its own.

## Out of scope

- The block itself, both thresholds, the owner's free-override toggle, and the notification/
  in-conversation-message mechanism — all `25-83`.
- Any tenant-facing self-service control over the auto-bill/manual toggle — stays the platform
  owner's, per the decision above.

## Outcome — the two decisions this item refused to default

### 1. The invoiced figure is the raw proxy count, disclosed. Not reconciled.

**Decided: bill from `site_attachment_egress.bytes_out` — AGO's own measurement, taken when a presigned
download URL is issued — and state on the tenant's own surfaces that this is what the charge is computed
from.**

The reason reconciliation was rejected is not tolerance for imprecision, and it is worth stating first
because it is the only argument that actually settles it: **the provider's figure does not exist at the
granularity a tenant would be billed at.** Yandex Object Storage bills egress per bucket, and this
deployment has exactly one bucket shared by every tenant (`docs/architecture/file-storage.md`: "one
list, for every bucket the server holds, which is exactly one here"). There is no provider-side
per-tenant number to reconcile *against*. The best a reconciliation could do is derive a
deployment-wide ratio between our total and the real bill and scale every tenant by it — which makes
one tenant's invoice depend on other tenants' browser-cache behaviour. That is less defensible to the
person being charged than the undercount it would replace, not more.

Two supporting reasons, neither sufficient alone:

- **The error already runs in the tenant's favour, structurally.** Every uncounted event is a cache hit
  inside a presigned URL's own TTL, and a cache hit can only ever be an event we failed to count, never
  one we invented. So the proxy undercharges, always — and nobody disputes being undercharged.
- **An exact per-tenant counter is a different item.** It needs either the bytes proxied through the
  API (which `file-storage.md` rules out on purpose) or a bucket per tenant (a storage-layout change
  with its own cost). If that layout ever changes, this decision genuinely reopens, and the ADR says so.

What this takes on is **disclosure, not accuracy**: the tenant-facing figure and the charged figure are
the same number, the proxy nature is now stated in `docs/architecture/data-model.md` where the table is
defined (extended this pass with the attribution argument), and the runbook a platform owner reads
before changing the price says a gigabyte here is 1024³ bytes rather than the decimal gigabyte the
provider prices in.

### 2. Yes, auto-bill gets a secondary cap — owner-configurable, per tier.

**Decided: `tier_download_thresholds.auto_bill_cap_rub` — the most a site on that tier may accrue in
overage charges within one calendar month before `25-83`'s block returns despite auto-bill. `NULL`
means uncapped, available to the owner but not the shipped default.**

Every other charge this product makes is initiated by the tenant — they pick a seat count, they buy an
Administrator slot. **This one is driven by third parties**: the tenant's own visitors clicking download
links. An unbounded charge produced by somebody else's behaviour is the shape that ends in a chargeback
and a refund rather than revenue, and the tenant who says "I did nothing" is factually right.

The asymmetry settles it. Uncapped, the ceiling on one month's damage is whatever a script can fetch.
Capped, the worst case is a tenant blocked at a number the platform owner chose — a state this product
already implements end to end, because `25-83` built exactly it — and the owner lifts it with one write.

**Per tier, unlike the price, and that difference is the point.** This item left the price
deployment-wide unless argued otherwise, and that stands: a gigabyte costs what a gigabyte costs
regardless of who downloaded it. A cap is the opposite kind of number — a judgement about how much
exposure a *kind* of customer should be allowed — and a free-tier tenant who has never paid anything is
not the same judgement as a Business tenant on a real subscription.

The cap applies to a manual tenant too, once they have paid: after a checkout they are in the identical
"accruing without acting" situation the question was about, so one rule covers both.

## Three things this item had to decide that its own text did not name

- **"Pay once, then meter" is the only reading of this item that satisfies all of its own sentences.**
  The text says the charge is metered and not a flat unlock; that a payment is "valid until the end of
  the current calendar month, however little of it remains"; and that "both modes ultimately charge the
  same meter — the toggle decides *when* the tenant commits." Those fit together exactly one way: a
  manual tenant's checkout settles the overage accrued up to that instant **and** opts them into the
  same accrual auto-bill has had all along for the rest of the month. Charging again at every further
  gigabyte would re-block them seconds after paying; treating the payment as buying the month outright
  would let a tenant go 0.01 GB over on the 1st, pay a rouble, and have unlimited egress — which is not
  a meter at all.
- **The column default is `Manual`, not the "recommended" `AutoBill`.** "Recommended default" is a
  recommendation to the platform owner about what to *set*, not a licence for a migration to move every
  existing tenant onto a silent, unagreed recurring charge whose first notice is an invoice. `Manual` is
  what every row behaves as today, so the migration changes nobody's bill.
- **The escape hatch closes when no price is published, rather than opening.** A deployment where
  nobody published a `download-overage-per-gb` version leaves `25-83`'s block exactly where it was —
  the opposite direction from `IDownloadThresholdReadStore`'s missing-row rule (which fails *open*), and
  deliberately: a missing threshold means "no limit was ever configured", while a missing price means
  "the paid way past a limit that *was* configured is not for sale yet."

## What reading the existing checkout mechanism actually found

The item warned that the purchase mechanism "was built for a one-time, fixed-price purchase... read that
mechanism's own code before assuming it takes a variable amount." **It already takes one.**
`IYooKassaPaymentsClient.CreatePaymentAsync`/`ChargeStoredPaymentMethodAsync` both take a plain
`decimal AmountRub`, and `PurchaseAdministratorSlotHandler`/`ChangeSubscriptionSeatsHandler` already
pass an amount computed at the moment of payment (a proration against remaining period days). The
fixed-price shape lives in the *callers*, never in the port or the adapter. So no change to the payment
mechanism was needed at all — `PurchaseDownloadOverageHandler` computes its own amount and calls the
same port, which is what "reuse the mechanism, do not invent a new payment flow" was asking for.

The one real extension was on the **inbound** side: `BillingWebhookApplier` resolved a ЮKassa payment id
only against `billing_subscriptions`. It now falls through to `download_overage_charges` when no
subscription matches — inside the same transaction and behind the same `(payment_id, event_type)`
idempotency ledger, so a redelivered `payment.succeeded` for an overage purchase is caught by exactly
the mechanism that already catches one for a subscription, rather than a parallel one that could
disagree with it.

## Done when

- [x] The per-GB overage price is configurable by the platform owner, not hardcoded, with 100 ₽ as the
      shipped default. `DownloadOveragePricing.OveragePerGigabyteKey` (`download-overage-per-gb`),
      registered in `PricedResourceKeys.All` and seeded as `v1 = 100.00` by migration
      `Stage25AddDownloadOverageBilling` — `25-43`'s existing price-catalog mechanism, not a second one.
      Because the owner's pricing screen renders whatever `PricedResourceKeys.All` lists, it became
      republishable with no console change at all. Proven against the real seeded row, not a retyped
      constant: `SiteAttachmentStorageHandlersTests.TheShippedOveragePrice_Is100Rub_AndIsOwnerRepublishable`;
      a republished price is followed at charge time by
      `PurchaseDownloadOverageHandlerTests.HandleAsync_FollowsThePlatformOwnersOwnCurrentPrice_NotTheShippedDefault`.
- [x] A charge computed from real gigabytes-over-threshold, valid through the end of the current
      calendar month only, is provably correct against a fabricated egress figure — not merely "some
      amount was charged." The arithmetic: `DownloadOveragePricingTests` (7 tests — one GiB is exactly
      100 ₽, a half GiB exactly 50 ₽, 2.5 GiB at an owner-set 40 ₽/GiB exactly 100 ₽, a mebibyte rounds
      to 0.10 rather than truncating, nothing at or below the threshold is ever negative). End to end
      against a real fabricated egress row: `PurchaseDownloadOverageHandlerTests` (8 tests — 2.5 GiB over
      reaches the payment provider as exactly 250.00 ₽, and only the *unsettled* remainder is charged
      when part of the month was already paid for). The calendar-month expiry, against real Postgres and
      with no expiry job existing to drive:
      `SiteAttachmentStorageHandlersTests.ASettledCheckout_DoesNotUnblockTheFollowingMonth_OverRealPostgres`
      — the identical settled row, still in the table, stops unblocking when the clock rolls over,
      because the row's own `period_month` stamp is what expires.
- [x] Paying (either path) unblocks the tenant's next presigned GET immediately, proven end to end.
      Manual: `SiteAttachmentStorageHandlersTests.ManualPath_PayThenDownload_UnblocksImmediately_OverRealPostgres`
      — blocked, then a real checkout through the real handler, then **still blocked** (a pending row is
      not payment), then the real `BillingWebhookApplier` on a real `payment.succeeded`, then the very
      next presigned GET succeeds. No clock advanced, no job ticked, no renewal ran in between.
      Auto-bill: `OwnerDownloadOverageBillingModeEndpointTests.OwnerToken_SetsAutoBillThenManual_AndTheRealDownloadGateFollowsBothTimes`
      — over the real owner HTTP route and real Keycloak tokens, checked against the real download gate
      each way rather than against the write's own `200`.
- [x] The platform owner can set the auto-bill/manual toggle per tenant, and both paths are proven —
      auto-bill accrues onto the next invoice with no tenant action; manual blocks until an explicit,
      real checkout. The toggle: `POST /api/v1/owner/sites/{siteId}/download-overage-billing-mode`,
      `RequirePlatformOwner` only, proven owner-scoped over real HTTP against an ordinary operator, a
      site-wide Admin and no token (`OwnerDownloadOverageBillingModeEndpointTests`, 7 tests).
      Auto-bill accruing with zero tenant action:
      `SiteAttachmentStorageHandlersTests.HandleAsVisitorAsync_WhenOnAutoBill_IsNotBlocked_OverRealPostgres`
      plus `ProcessSubscriptionRenewalHandlerTests` (8 tests — the renewal charge grows from 490 ₽ to
      790 ₽, the description names the overage, and the applier receives a per-month,
      per-price-version ledger line). Manual blocking until a real checkout:
      `GetAttachmentDownloadUrlHandlerTests` (8 new tests, including the control that a *pending*
      checkout still blocks). **Note what "a line item" means here**, stated rather than glossed: this
      codebase has no invoice entity — a regular invoice is one ЮKassa charge with a description — so an
      overage line is three real things (the charge amount grows, the description names it, a
      `download_overage_charges` row records it at its price version) and no invented fourth one.
- [x] Whether the invoiced figure is the raw proxy count or something reconciled is decided and stated,
      not left implicit now that it is a real money question. Decided: **the raw proxy count** — see the
      Outcome section above for the full argument, restated in
      `docs/adr/XXXX-download-overage-is-invoiced-from-the-proxy-meter-under-an-owner-set-cap.md` and in
      `docs/architecture/data-model.md` where the table is defined.
- [x] *(Not in the original list — the item's own second open question, answered.)* Whether auto-bill
      needs a secondary ceiling: **yes**, built as `tier_download_thresholds.auto_bill_cap_rub`,
      owner-configurable per tier, never a hardcoded number. Proven biting, and proven not to bite one
      rouble under itself, against real Postgres
      (`..._WhenOnAutoBill_AndPastTheTiersAutoBillCap_IsBlockedAgain_OverRealPostgres`) and in the
      handler tests either side of the boundary.

## Found and fixed while proving it

Two real defects that only the real-Postgres/full-suite pass could reach — neither is a compile error,
so a clean build was never evidence either way:

1. **`DownloadOverageReadStore` bound a `DateOnly` as a Dapper parameter**, which throws
   `NotSupportedException` at Dapper's own parameter generator. `AttachmentEgressReadStore` had already
   met and documented this for the table this one joins against; the fix follows it. The asymmetry is
   now written down where the next person will hit it: a `date` column *reads back* as a `DateOnly`
   (Npgsql maps it natively) but cannot be *bound* as one.
2. **`CrossTenantRouteIsolationTests`' own test host did not register the two new ports**
   `GetDownloadUsageForSiteHandler` now depends on, so a route that should answer `403` answered `500`.
   That host builds its service list one line at a time rather than calling the production composition
   root — the production wiring was correct throughout. Caught only by running the full suite rather
   than the filtered one, which is the argument for running it.
