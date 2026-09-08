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

## What this page does not decide

**Prices, tiers and packaging are not here and are not public.** They live in the private
`ago-business` repository. This page carries the mechanism — what an entitlement is, who may grant one,
and what keeps it alive — which is the part a reviewer of this codebase needs and the part that must
stay true regardless of what the price list says this week.
