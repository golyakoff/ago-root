# 26-278 · The connected-channel add-on is charged and gated (0012 §7 pay-or-disable)

- **Stage**: 26. Kind: revenue-path build (design done here; implementation follows). Found 2026-09-29 by
  the billing-vs-published reconciliation, filed by the managing session (CLAUDE.md rule 14). Sibling of
  26-277 (extra administrator on renewal) — same reconciliation, different priced dimension.
- **Status**: designed 2026-09-29. Ready to slice once 26-277 clears the migration lane (rule 13: one
  migration in flight; this item carries a seed migration that must be sequenced **after** 26-277's).
- **Repos touched (recommended slice)**: `ago-chat` only (Domain + Application + Infrastructure.Postgres +
  Api + a seed migration + tests). No platform, widget, console, android, deploy, or ago-business change
  in the recommended cut. (A console purchase screen and a free-tier purchase path are cut out to their
  own numbers — see the slice plan.)

## The finding, cited

Published pricing charges **+100 ₽/mo per connected channel beyond the website**. The plumbing for the
*price* exists and the plumbing for the *gate* exists, but the two are **not connected by any payment**:

- `Ago.Chat.Domain/ChannelAddOnPricing.cs` defines `ChannelAddOnKey = "channel-addon"`, its own remarks
  saying plainly "nothing reads it yet, deliberately" (the `25-101` half that built only the owner's
  publish surface).
- `Ago.Chat.Domain/PricedResourceKeys.cs` registers it ("Price per connected channel beyond the widget
  itself"), and the stand has it published at 100.
- Grep for `channel-addon` / `ChannelAddOnKey` across `src/` returns **only those two definition files** —
  no charge site reads it.

## What already exists — verified, so we don't rebuild it

**The gate is fully built** (`adr/0151`, `23-85`, `25-170`). "Pay-or-disable" from 0012 §7 is, at the
entitlement-read layer, already the live behaviour:

1. **Per-channel-kind entitlement.** `Domain/ChannelEntitlementOptionKeys.For(kind)` maps each
   `ChannelKind` to a billing option key (`channel-telegram`, `channel-max`, …). `adr/0151` §7 and 0012
   §7 both fix this as one privilege *per kind*, priced per unit, not one for the class.
2. **The two-step read.** `Application/UseCases/ChannelEntitlement.IsEntitledAsync` = the option key maps
   to a `ModuleKey` via `IBillingOptionEntitlementProvider.TryGet` **and**
   `IModuleQuantityGrantStore.GetQuantityAsync(siteId, moduleKey) > 0`. The stand declares exactly one
   real mapping today: `BillingOptionEntitlements__channel-telegram → channel`
   (`entitlements-and-subscriptions.md`).
3. **Connect is blocked without entitlement.** `RegisterChannelCredentialHandler` checks
   `IsEntitledAsync` right after the `channel:manage` permission gate and returns
   `ChannelEntitlement.Refusal(kind)` when the account has not paid.
4. **A lapsed channel is disabled at runtime.** `Ago.Chat.Worker/EntitlementWatchdogJob`
   (`ReconcileChannelEntitlementsAsync`, one-minute cadence) re-reads the effective quantity for every
   active credential and calls `ChannelCredential.PauseForLapsedEntitlement` (reversible — the long-poll
   loop for that channel stops within a tick) when it drops to zero, resuming when it returns. A separate,
   one-way, human-reviewed `DisconnectNonEntitledChannelCredentialsAsOwnerHandler` +
   `RevokeForLapsedEntitlement` handles the delete-the-credential case.
5. **A grant/revoke already rides an option subscription's renewal/lapse.**
   `Infrastructure.Postgres/SubscriptionRenewalApplier` writes `IModuleQuantityGrantStore.GrantAsync(…, 1)`
   on an option row's renewal success and `…, 0` on its lapse, in the same transaction as the charge
   outcome, published through the outbox.

**The option model is built too.** `adr/0159`: each purchased option is its **own** `BillingSubscription`
(`BillingSubscription.CreateOption`, `OptionKey` non-null, `IsOption`), its `CurrentPeriodEnd` copied from
the base at purchase so both renew together, its first charge covering the remainder of that period.
`adr/0160`: a paid option outlives a base lapse — it lives and dies by its own charges alone, and is
sellable even to a free-tier account.

## The gap — exactly one thing is missing

**Nothing on the payment path ever creates a channel option or charges its price.** This is the
"…or by the system on a payment" half of `adr/0151` that `adr/0159` already recorded as "does not exist":

- **`BillingSubscription.CreateOption` has no production caller.** Grep confirms it is referenced only in
  its own definition and in a comment. `23-115` ("a tenant can buy an option themselves") was never built.
- **`ProcessSubscriptionRenewalHandler` throws on every option row.** Its `if (subscription.IsOption)`
  branch raises `InvalidOperationException("…no price source for an option's recurring charge exists yet -
  see this item's own report.")`. So even a hand-created option row would crash the worker at its first
  renewal.
- **`channel-addon` is unseeded.** Like `admin-extra` (26-277), it lives on the stand only because the
  owner published it by hand; a fresh/local deploy has no version, so any charge site would get
  `PriceNotConfigured`.

Today the *only* way a `channel-*` grant becomes `> 0` is the platform owner acting by hand
(`GrantModuleQuantityAsOwner` / `SetUnconditionalModuleGrantAsOwner`). There is no self-service, paid path.

## Design decisions

### 1. Charge points — both, and this is forced, not chosen

`adr/0159` + 0012 §7 ("+100 ₽/**мес**", period aligned to the base) settle this: a channel add-on is a
**recurring** option, so it is charged at **two** points, mirroring the two the admin-slot and seat paths
already use:

- **At purchase — a prorated immediate charge** for the remainder of the base's current period, exactly
  the shape of `PurchaseAdministratorSlotHandler` (`ChargeStoredPaymentMethodAsync` against the base
  subscription's stored `payment_method_id`, `(price × remainingDays / periodLengthDays)` rounded away
  from zero). Difference from admin: it does not mutate the base row — it **creates a new option
  `BillingSubscription` via `CreateOption`**, `MarkSucceeded(alignedPeriodEnd: base.CurrentPeriodEnd)`,
  and grants the entitlement on the verified charge success.
- **At renewal — the recurring monthly charge**, by teaching `ProcessSubscriptionRenewalHandler`'s option
  branch to **read a price instead of throwing**. For a channel option the price is the flat
  `channel-addon` key (kind-independent, per `ChannelAddOnPricing`'s own remarks: "one price, independent
  of which kind"). The existing `SubscriptionRenewalApplier` already does the grant on success and revoke
  on lapse — that half needs no change.

**Handlers to change/add (recommended slice):**
- **new** `Application/UseCases/PurchaseChannelAddOn/PurchaseChannelAddOnHandler` (+ command, result) —
  mirror of `PurchaseAdministratorSlotHandler`.
- **new** `Application/Abstractions/IChannelAddOnPurchaseApplier` + `Infrastructure.Postgres`
  implementation — mirror of `IAdministratorSlotChangeApplier`/`AdministratorSlotChangeApplier`, but its
  apply step **creates the Succeeded option row and calls `IModuleQuantityGrantStore.GrantAsync(…, 1)`**
  in one transaction (reusing the `SubscriptionRenewalApplier` grant discipline).
- **change** `Application/UseCases/ProcessSubscriptionRenewal/ProcessSubscriptionRenewalHandler` — replace
  the `IsOption` throw with a `channel-addon` price read for channel options (missing-price handling: skip
  or throw — see the open sub-question below).
- **new** `Api/Billing/BillingEndpoints` route
  `POST /api/v1/sites/{siteId}/billing/subscriptions/{baseSubscriptionId}/channels` (mirrors the
  `/administrators` route), body naming the `ChannelKind`.

### 2. Gate semantics — already settled; only one nuance to reconcile

"Disabled" for an unpaid channel means, precisely:

- **Connect is refused at purchase/register time** when unentitled — `RegisterChannelCredentialHandler`
  returns `ChannelEntitlement.Refusal(kind)`. The gate READS the entitlement in the *connect command*.
- **A lapsed channel is disabled at runtime** — `EntitlementWatchdogJob` pauses the poller
  (`ChannelCredential.PauseForLapsedEntitlement`, reversible). The gate READS the entitlement in the
  *watchdog job* (once a minute) and in the *renewal applier* (the moment a charge fails and the option
  lapses, which sets the grant to 0).
- **Operator-visible state**: the credential carries `EntitlementPausedAt`; message routing / the console
  channel screen reflect it as paused rather than deleted (unless the owner runs the one-way disconnect).

Message *routing* does not re-check entitlement per message — the poller simply stops feeding the channel
when paused, which is the intended chokepoint (no per-message read on the hot path; CLAUDE.md rule 8 is
satisfied because the write-decision path — connect and the once-a-minute reconcile — reads the DB, and
the hot path just observes the paused flag).

**Nuance to record, not to change here.** 0012 §7 (written 2026-09-09) says a lapsed channel's
credentials are **deleted** ("удаляются, а не просто помечаются неактивными"). The mechanism actually
built (`25-170`) **pauses** the poller reversibly and keeps the credential; the one-way *delete* is a
separate owner-driven path. The reversible pause is the better mechanism (a returning payment resumes
without re-entering the token), and it is what shipped. This design keeps the pause; the design note
belongs on `entitlements-and-subscriptions.md`, and 0012 §7's wording is stale on this point — flag it to
the author rather than silently contradict the private decision doc.

### 3. Seed — yes, required, migration-lane, after 26-277

`channel-addon` = 100 must be seeded by a data-seed migration mirroring the `seat-base` / `seat-extra` /
`download-overage-per-gb` seeds, so purchase works on a fresh/local deploy instead of returning
`PriceNotConfigured`. **Rule 13**: this is a migration and the migration lane holds one at a time; 26-277
is in that lane now seeding `admin-extra`, so this seed is created and merged **after** 26-277 lands (its
migration timestamp must sort after 26-277's).

### 4. Option-key → price-key resolution (small new mapping)

The renewal handler needs to know a channel option's recurring price is `channel-addon`, while an AI
option (`ai-*`) deliberately has **no** published price (0012 §7: per-tenant cost accounting missing for
AI, "для ИИ — нет, и поэтому цены не публикуются"). Place this mapping in **Domain**, beside
`ChannelEntitlementOptionKeys`, e.g. `ChannelAddOnPricing.PriceKeyFor(BillingOptionKey) : PriceKey?`
returning `channel-addon` for a `channel-*` key and `null` otherwise. A `null` means "this option kind is
not priced in code yet" and the renewal handler keeps throwing for it (unchanged behaviour for AI),
charging only channel options.

## Repos / files touched (recommended slice), concretely

`ago-chat`:
- **Domain**: `ChannelAddOnPricing.cs` (add `PriceKeyFor`; drop the "nothing reads it yet" remark).
- **Application**: new `PurchaseChannelAddOn/{PurchaseChannelAddOn,PurchaseChannelAddOnHandler,PurchaseChannelAddOnResult}.cs`;
  new `Abstractions/IChannelAddOnPurchaseApplier.cs`; edit
  `ProcessSubscriptionRenewal/ProcessSubscriptionRenewalHandler.cs`.
- **Infrastructure.Postgres**: new `ChannelAddOnPurchaseApplier.cs`; a **seed migration**
  `…_Stage26SeedChannelAddOnPrice.cs`.
- **Api**: `Billing/BillingEndpoints.cs` (+ request record).
- **Module**: `ChatModule.cs` DI wiring for the new handler + applier.
- **Contracts**: a purchase request/response DTO if the endpoint needs one.
- **Tests**: handler unit tests (purchase prorates + grants; renewal charges `channel-addon` and lapses →
  revoke); a seed migration test; an integration test that a paid channel connects and a lapsed one is
  paused by the watchdog.

## Slice plan (rule 15)

**The one promise for 26-278**: *"A tenant with an active paid (Succeeded) base subscription can buy a
connected channel for 100 ₽ (prorated now, then +100 ₽/mo aligned to the base); the payment grants that
channel-kind's entitlement so the channel connects, and if the option lapses the grant is revoked and the
watchdog disables the channel. The price is seeded so this works on any deploy."*

This lands green end-to-end and is production-reachable for a paying tenant. Purchase + recurring-renewal
are **one** promise, not two: shipping the purchase without the renewal fix would create option rows that
crash the worker at first renewal (not "green"), so the finish-an-item "never first-breaks-then-fixes"
rule keeps them together. The seed is part of the same promise (else purchase returns `PriceNotConfigured`).

**Cut out to their own numbers** (genuinely different promises / shapes):

- **NEW #A — Free-tier channel purchase (checkout + webhook + domain relaxation).** `adr/0160` makes a
  channel sellable to a **free-tier** account, which has no base subscription and no stored payment
  method — so its purchase cannot be the synchronous stored-method charge above; it needs a
  redirect+webhook flow like `CreateCheckoutSessionHandler`, and `MarkSucceeded` currently *requires* an
  `alignedPeriodEnd` for options (there is no base period to align to). This is a materially different
  charge shape and a domain-invariant change — **it warrants its own ADR** (see below). File in `ago-chat`
  and mirror in `ago-root`.
- **NEW #B — Console/owner purchase surface for the channel add-on.** The backend endpoint is enough for
  26-278's promise; the tenant-facing console screen (buy-a-channel button + lapsed-channel state) is a UI
  slice of its own in `ago-console` (and, per the "Android full console parity" memory, eventually
  `ago-android`).

If the author prefers a smaller migration-lane-only first step, the alternative cut is **26-278 =
recurring-renewal + seed only** ("an existing channel option renews at `channel-addon` and lapses if
unpaid; the price is seeded"), with the purchase handler as NEW #C. That is a legitimate standalone green
slice (testable with a constructed option row) and matches how `ChannelAddOnPricing` shipped as
"nothing reads it yet." Recommended only if the migration lane is the binding constraint; otherwise the
end-to-end promise above is the better single deliverable.

## Done-when (recommended slice)

- [ ] A tenant with a Succeeded base subscription can `POST …/channels` naming a `ChannelKind`; the
      handler prorates `channel-addon` for the remainder of the base period, charges the stored payment
      method, creates a Succeeded option `BillingSubscription` (`CreateOption`, period aligned to the
      base), and grants the `channel-<kind>` module quantity — all on verified charge success. Handler
      test asserts the prorated amount and the grant.
- [ ] `ProcessSubscriptionRenewalHandler` charges `channel-addon` for a channel option at renewal instead
      of throwing; a missing `channel-addon` price is handled the same way the seat prices are (see the
      open sub-question). Renewal test asserts the charge and that a refusal lapses the option (→ grant
      revoked via the existing applier).
- [ ] A data-seed migration seeds `channel-addon` = 100, sequenced after 26-277's `admin-extra` seed.
      Seed test.
- [ ] An integration test: a paid channel connects (register succeeds); when the option lapses, the
      watchdog pauses the credential within a tick.
- [ ] `entitlements-and-subscriptions.md` records the option-key→price-key resolution and the §7
      pause-vs-delete reconciliation note. (0012 §7 stale-wording flagged to the author; ago-business edit,
      if any, is the author's call — not in this slice.)
- [ ] Free-tier purchase (#A) and console surface (#B) filed as their own numbers, not folded in.

## Open sub-questions for the author (small, decidable in chat)

1. **Missing `channel-addon` at renewal — skip or throw?** The seat prices *throw* (a Succeeded base
   proved they existed); the download-overage price *skips* (feature simply not for sale). A channel
   option that was purchased proves the price existed at purchase, so **throw** is the consistent choice —
   but if a deployment un-publishes `channel-addon` after selling one, throwing repeatedly is noisy.
   Recommend: throw (matches seats; loud is correct for a regression), state it in the handler remarks.
2. **`admin-extra` renewal (26-277) landing first** is assumed. If 26-277 slips, this item still stands
   but its seed migration must still sort after whatever 26-277 finally uses.

## ADR?

**Not warranted for the recommended 26-278 slice.** It executes `adr/0151` (entitlement layer),
`adr/0159` (option is its own subscription, prorated-then-recurring, period-aligned) and `adr/0160`
(paid option outlives base lapse). The one new micro-decision — the flat `channel-addon` key prices every
`channel-*` option while AI options stay deliberately unpriced — is a wiring fact recorded in
`entitlements-and-subscriptions.md` (authoritative for how it works now), not a new guarantee.

**Warranted for cut-out #A (free-tier channel purchase).** Selling an option to an account with no base
introduces an option lifecycle the current domain forbids (`MarkSucceeded` requires an aligned period for
options). Drafted row for the managing session to add to `docs/adr/README.md` when #A is numbered
(number to be assigned by the managing session — placeholder `ADR-XXXX`):

> `| ADR-XXXX | A free-tier account's channel option starts its own period | Accepted | 26 |`

Draft ADR body (for #A, not this slice):

> **Context.** `adr/0159` aligns every option's period to the account's base subscription, and
> `BillingSubscription.MarkSucceeded` enforces it (an option must be given an `alignedPeriodEnd`).
> `adr/0160` then made an option sellable to a **free-tier** account — which has no base subscription and
> therefore no period to align to. The two decisions collide the first time a free-tier tenant buys a
> channel.
> **Decision.** An option bought by an account with no base subscription **starts its own 30-day period**
> (`now + PeriodLength`), exactly as a base first-payment does, and renews on its own anchor. Alignment
> applies only when a base period exists at purchase. `MarkSucceeded` is relaxed to accept a null
> `alignedPeriodEnd` for an option **iff** the account has no Succeeded base row; a base that later
> appears does not retro-align the option (no reconciliation rule invented).
> **Consequences.** A free-tier tenant pays a full 100 ₽ for a full 30 days from purchase, never a
> prorated stub. If they later buy a paid base, the two periods drift — accepted, matching `adr/0160`'s
> "an option lives by its own charges and nothing else." The purchase itself needs a redirect+webhook
> flow (no stored payment method exists on a free account), so this item also builds the tenant checkout
> for an option, distinct from the synchronous stored-method charge used when a paid base is present.

## Teaching-mode notes (Clean Architecture)

- **The price READ lives in the Application handlers** (`PurchaseChannelAddOnHandler`,
  `ProcessSubscriptionRenewalHandler`), never in Domain. `IPriceCatalogRepository` is a port (rule 2) and
  Domain references nothing (rule 1); a Domain "pricing service" that read the catalog would drag a
  repository into the inner layer. The **arithmetic** (proration) can stay a pure Domain/`SubscriptionTierBands`-style
  static, but the *fetch* is the handler's job.
- **The entitlement GRANT is written through `IModuleQuantityGrantStore` (a port) in the Infrastructure
  applier, in the same DB transaction as the charge outcome** — rule 4 (state change + integration event
  commit together, published via the outbox). The alternative, writing an `EnabledModule` row, is
  rejected for the reason already recorded on `SubscriptionRenewalApplier`: `EnabledModule` needs a
  synchronous `IModuleRegistrationGateway.RegisterAsync` network call, and a network call inside a
  transaction that just charged a card is exactly the coupling rule 3's spirit keeps out.
- **The gate READ stays a static Application helper (`ChannelEntitlement`) composing two existing ports,
  not a new port** — matching its own recorded reasoning: a third "is-entitled" port would hide the
  two-step resolution a reviewer needs to see.
- **The option-key→price-key mapping lives in Domain** (beside `ChannelEntitlementOptionKeys`), because
  it is a stable fact about this codebase's own vocabulary (`channel-*` → `channel-addon`), not
  deployment configuration. The alternative — a `switch` in the Application handler — would scatter the
  pricing policy across layers; keeping it in Domain mirrors the existing `ChannelEntitlementOptionKeys`
  placement decision.
