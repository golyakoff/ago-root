# What an account has, and what keeps it having it

This is the current-state document for two things that had no owner and were scattered across five
others: **what a tenant is entitled to**, and **the subscription that sustains it**. They are one page
because they are one question asked at two moments — *may this account do this at all*, and *is it
still paid for*.

Adjacent pages own the neighbouring questions and are not repeated here:
[`authorization.md`](authorization.md) for whether a *person* may act on an account's behalf,
[`personal-data.md`](personal-data.md) for what a revoke and an erasure remove, and the
[module grant and revoke runbook](../runbooks/module-grant-and-revoke.md) for how a grant is performed
by hand.

## The two layers, and why they never merge

[`adr/0151`](../adr/0151-entitlement-is-granted-by-the-platform-configuration-inside-it-is-the-tenants.md)
draws the line this page exists to hold:

| | Who decides | Examples |
|---|---|---|
| **Entitlement** — may this account use this capability at all | **The platform only**: the platform owner acting deliberately, or the system on a payment | the calendar, channels, the AI additions, FAQ |
| **Configuration** — what the capability does for this tenant | **The tenant**, inside their own sandbox | widget appearance, their operators, their own bot token, their own consent text |

**Every capability that appears in the price list has an entitlement, and every write that would use
one checks it — in the handler, never only in the screen.**

**A tenant's own credential is configuration, not entitlement.** Pasting a Telegram token is the
tenant's act and stays theirs; it is refused when the account holds no channel entitlement, and the
refusal names that reason rather than looking like a validation failure.

### A permission is not an entitlement

This is the mistake the line exists to prevent, and it is easy to make. `channel:manage` answers
*"is this person allowed to act on behalf of this account"*. It cannot answer *"has this account bought
it"* and never could — permissions are seeded per site by `RegisterSiteHandler` and have nothing to do
with money.

Every place that treated a permission check as sufficient was implicitly asserting that anybody allowed
to act had already paid. That held only while nobody held the permission.

### What an entitlement is made of, mechanically

A grant writes a row in chat's `enabled_modules` and seeds the module's permissions into the site's
roles, in one transaction, publishing so the module's own copy learns (`23-102`, `23-104`). A revoke
**tombstones** rather than deletes, because that row is chat's only record the site ever held the
module; an erasure reaches the module over the deployment-wide provisioning channel rather than the
per-site one, since a revoked tenant no longer has a per-site credential
([`adr/0155`](../adr/0155-erasure-reaches-a-module-over-the-provisioning-channel-and-a-revoke-tombstones.md)).

The visitor handshake reports the site's live module keys as opaque strings, so a widget that was
pasted once and never touched again gains a capability the moment it is granted (`23-105`).

**A grant that comes from a payment is narrower than that, deliberately.** Writing an `enabled_modules`
row needs an entry point, a credential and a **synchronous registration call to the module** before the
row means anything — none of which belongs inside a background job's own transaction, seconds after it
charged a card. A billing grant therefore writes a quantity grant, which is a durable row plus one
outbox event and no network call at all.

The consequence has to be stated rather than discovered: **a billing grant is not yet sufficient to
turn on a module that requires registration**, `calendar` and `faq` being the two that do. Pointing an
option at one of those would leave chat believing the module is granted while nothing routes to it.
Widening the billing grant to drive real registration, or keeping the two mechanisms apart on purpose,
is an open question and not decided here.

## The subscription that sustains it

[`adr/0073`](../adr/0073-subscription-lifecycle-recurring-charge-retry-cancellation-seats.md) is the
lifecycle in full. What holds:

**`SubscriptionRenewalJob` ticks hourly** — the same `PeriodicTimer`/`BackgroundService` shape as every
other sweep here — and asks for every subscription whose period has ended or whose daily retry is due.

**Two states carry failure**, and the distinction is the useful part:

- **`PastDue`** — a recharge failed. `sites.tier` and `seat_limit` are **untouched**, so a tenant whose
  card expired keeps working while it is sorted out.
- **`Lapsed`** — terminal, reached either by exhausting the seven-day `PastDue` retry window or by a
  cancelled subscription reaching its own paid-through end. **One terminal state for both**, because
  from the site's point of view "ran out of retries" and "chose not to renew" end in the same place.

**Retries run at most once per calendar day**, gated on elapsed time since the last attempt rather than
an attempt counter — so the job's tick interval is free to be more frequent than the retry cadence
without over-charging.

**The recurring charge is idempotent by a deterministic key** (`renewal:{subscriptionId}:{date}`),
deliberately not a fresh id per call. The hazard at this scale is not a client-side network retry; it
is **two `Ago.Chat.Worker` replicas independently deciding the same row is due on the same day**. A
deterministic key turns that race into the provider returning one payment's result twice, which is
cheaper and more honest than putting a row lock on a job whose real cadence is daily.

## An option is its own subscription

**Each purchased option is a `BillingSubscription` of its own, and its period is the account's rather
than one starting at purchase** ([`adr/0159`](../adr/0159-an-option-is-its-own-subscription-aligned-to-the-account-s-base-period.md)).
`CurrentPeriodEnd` is copied from the base when the option is bought, and the first charge covers the
**remaining** days - so both renew on one date, and the annual discount applies to the whole set at
that moment rather than to each row separately.

**Failure is per subscription, and that is the point.** An option that cannot be charged runs its own
`PastDue` window and lapses on its own; the tier does not notice. Lines inside one subscription would
have made a declined charge for a cheap option put a paid tier into `PastDue`, because a single charge
either succeeds or fails - and partial-payment semantics are not something to invent in the least
forgiving place this system has.

**The renewal job needs no knowledge of any of this.** `ListDueForRenewalAsync` selects on
`(status, current_period_end)` across all rows, so options renew, retry and lapse through the same code
that already does it for tiers.

**One read has to stay narrow.** `GetBillingStatusHandler` means *the site's base subscription*; handed
the newest row instead, it would show a tenant their channel where their tier belongs. It is the only
reader with that assumption.

**A paid option is not cancelled by the lapse of the tier beneath it**
([`adr/0160`](../adr/0160-a-paid-option-outlives-the-tier-that-lapsed-under-it.md)). The account falls
to the free tier and the option keeps working for as long as it is paid for - the same generous
direction `adr/0073` chose for the tier itself, and already true by construction, since the two rows
have no relationship a charge can traverse. **An implementation that checks the base's status to decide
an option's fate has misread this.**

So **an account can be on the free tier and paying**, and that is a normal state rather than an odd
one. Everything downstream reads entitlements rather than inferring them from a tier name, and "free
account" stops meaning "brings no revenue".

**What an option turns on is deployment configuration, resolved by key** — the identical shape
`adr/0154` set for module entry points and `23-102` for module permissions.
`IBillingOptionEntitlementProvider` reads `BillingOptionEntitlements:<option-key>` and answers with the
`ModuleKey` that option grants; a key this deployment has not declared throws, loudly, rather than
granting nothing (`SubscriptionRenewalApplier.ResolveEntitlementOrThrow`'s own remarks). `ago-deploy`
declares one real mapping today — `BillingOptionEntitlements__channel-telegram` → `channel`, on
`Ago.Chat.Worker` (the only host that ever calls this port, since `SubscriptionRenewalApplier` is the
only caller) — deliberately not `calendar` or `faq`: this page's own "a billing grant is not yet
sufficient to turn on a module that requires registration" a few paragraphs up applies here exactly,
and pointing this mapping at either would leave chat believing the module is granted while nothing
routes to it.

## An unconditional grant overrides billing, never competes with it

**Every entitlement carries a second, independent input the platform owner alone may set: an
unconditional-grant flag, combined with whatever billing already says by OR** (`23-86`, answered in
dialogue 2026-09-13). This is the awkward case an early draft of `23-86` named and did not build: a
tenant already granted a trial by hand, who then pays for the identical option. Two sources, one
capability, and the expiry of either must not silently end the other.

- **Flag set, billing active** — both true at once is not a conflict; billing is simply redundant for
  as long as the flag stands.
- **Flag lifted, billing still active** — the entitlement survives on billing alone; lifting the flag
  never re-provisions or interrupts anything.
- **Flag lifted, billing lapsed or absent** — the entitlement goes off. This is the only case where
  lifting the flag actually changes the outcome, which is why lifting it re-evaluates the current
  billing-driven quantity rather than assuming the prior "on" state persists.

**The flag never becomes a second, competing write to `ModuleQuantityGrant.Quantity`.** `Quantity`
keeps meaning exactly what it always has — the last number a billing renewal/lapse or an owner's own
quantity grant wrote. `EffectiveQuantity` (`Quantity` OR'd with the flag, `Math.Max(Quantity, 1)` when
the flag is set) is computed fresh on every read and is what `IModuleQuantityGrantStore.GetQuantityAsync`/
`GetAllForSiteAsync` return and what every `ModuleQuantityGranted` event carries — never the raw
`Quantity` alone. That last point is load-bearing: `SubscriptionRenewalApplier`'s own billing-driven
grant/revoke calls are **completely unchanged** by this mechanism — they still call
`IModuleQuantityGrantStore.GrantAsync` with the plain billing fact, exactly as before `23-86`. The OR
happens once, inside `ModuleQuantityGrantStore` itself, so a billing lapse while the flag is set can
never publish a `ModuleQuantityGranted` fact ("revoked") that contradicts what the flag promises,
without a single caller needing to know the flag exists.

**Only the platform owner may set or lift the flag**, always with a stated reason
(`SetUnconditionalModuleGrantAsOwnerHandler`, `PUT /api/v1/owner/sites/{siteId}/modules/{moduleKey}/unconditional-grant`) —
the same "an owner-only override always carries a stated reason" shape `adr/0118`'s forced-revoke
already established, mirrored here for the grant side of the identical relationship rather than
reinvented. Provenance for the flag itself (who, when, why) lives as columns on the
`ModuleQuantityGrant` row it describes, not a separate audit table: unlike `adr/0118`'s own
`module_revoke_overrides` (chosen because the row it audits is about to be deleted), this row survives
indefinitely, which is exactly the case `adr/0118`'s own "Alternatives considered" section says a
column-on-the-row belongs to (`adr/0098`'s reasoning, restated there).

**A refund or a chargeback needs no mechanism here.** No refunds are offered at all, so there is no
credit-reversal case to model; the rare chargeback case falls back to this identical manual owner-revoke
path rather than earning automation of its own.

## What this page does not decide

**Prices, tiers and packaging are not here and are not public.** They live in the private
`ago-business` repository. This page carries the mechanism — what an entitlement is, who may grant one,
and what keeps it alive — which is the part a reviewer of this codebase needs and the part that must
stay true regardless of what the price list says this week.
