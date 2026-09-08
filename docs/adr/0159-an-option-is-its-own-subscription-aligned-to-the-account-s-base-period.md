# ADR-0159: An option is its own subscription, aligned to the account's base period

- **Status**: Accepted
- **Date**: 2026-09-08
- **Stage**: 23

## Context

`adr/0151` says an entitlement is granted by the platform owner **or by the system on a payment**.
The second half does not exist: nothing on the billing path writes an `EnabledModule` or a
`ModuleQuantityGrant`, checked rather than assumed. `23-86` found it from the paying side and `22-33`
from the lapsing side, and they are the same absence.

**The reason is one level deeper than either item recorded.** `BillingSubscription` carries `Tier` and
`RequestedSeats` and nothing else. There is no concept of a purchased option anywhere in the domain, so
"the tenant paid for the channel" cannot be *written down*, let alone applied.

The commercial grid (private, `ago-business/docs/decisions/0012`) sells three things that are not the
same shape: a tier priced by seats and administrators; per-month options; and AGO Calendar, which
`0008` already decided is **its own subscription rather than a line on the Chat invoice**, priced by
masters.

That grid also raises the constraint this decision turns on, and leaves it open: an annual base plus an
option bought mid-year is *"два платёжных обязательства вместо одного, и отказ по второму не должен
ронять первое"*.

The author's own worked case: a tenant on an annual subscription buys a channel on day 128. They are
charged for the remainder of the year so that **both end on the same day**, and at renewal the annual
discount applies to the whole set — which is `0012`'s stated rule that mid-year purchases run at full
price until the renewal date.

## Decision

**Each option is its own `BillingSubscription`, and its period is aligned to the account's base
subscription rather than starting a year of its own.**

- A subscription states **what it is for**. One per account is the base (tier and seats); the others
  each name an option.
- **An option's `CurrentPeriodEnd` is copied from the base at purchase**, and its first charge covers
  the remainder of that period. Both then renew on the same date, and the annual discount applies to
  the set as `0012` requires.
- Failure is per subscription. An option that cannot be charged goes `PastDue` and then `Lapsed` on its
  own seven-day window, and the base does not notice.
- **The mapping from an option to the entitlement it grants is deployment configuration**, resolved by
  key — the shape `adr/0154` established for module entry points and `23-102` for module permissions.
  Prices stay in the private repository; the deployment declares only *what an option turns on*.

## Consequences

**`0012`'s isolation requirement is satisfied by construction rather than by a mechanism somebody has
to remember.** A failed option charge cannot endanger the tier, because the two rows have no
relationship a charge can traverse. That is the whole argument for this shape over lines on one
subscription, where "partially failed charge" would have to be invented — and a partially failed charge
is the worst possible place to invent something.

**The renewal machinery already works for options, unchanged.** `SubscriptionRenewalJob` asks
`ListDueForRenewalAsync` for every row whose period has ended, not for one row per site, so option
subscriptions renew, retry and lapse through exactly the code that already does it for tiers. This was
the largest single reason to expect this decision to be expensive, and it turned out to be free.

**One existing read becomes wrong and must be narrowed.** `GetBillingStatusHandler` calls
`GetLatestForSiteAsync` and means *the site's subscription*. With options in the same table it would
return whichever row was created last — so a tenant who just bought a channel would see the channel
where their tier should be. It is the only such reader; the renewal job's set-based query is unaffected.
**This is the migration hazard of this decision**, and it is silent rather than loud.

**Two payment obligations per account become normal, not exceptional.** `0012` flagged this as
something to check with the first real tenant, and it stays true: ЮKassa charges each subscription
separately, so an account can be partly paid. Everything downstream must read entitlements rather than
infer them from "the account is paid".

**A refund is still not modelled, and this does not change that.** `adr/0073` removed credit
accounting because ЮKassa has no balance; an option cancelled mid-period runs to the end of what was
paid for. Aligning periods makes that easier to explain, not different.

## Alternatives considered

**Options as lines inside one subscription.** One row, one charge, one invoice — simpler for the tenant
and cheaper to operate. Rejected on `0012`'s own requirement: a single charge either succeeds or fails,
so a declined card for a 100 ₽ channel would put a 490 ₽ tier into `PastDue`. Recovering from that
needs partial-payment semantics that ЮKassa does not offer and that this project would have to invent
in the least forgiving place it has.

**An option as a flag on the site, granted by a one-off payment.** Cheapest of all, and it is what the
platform-owner grant path already effectively does by hand. Rejected because it has no period: nothing
would ever expire, so "paid for a month" and "granted forever" would be the same record, and `22-33`
exists precisely because a thing that is paid for must be able to stop being paid for.

**Starting the option's own year at purchase.** Avoids pro-rating, and every subscription is then a
clean twelve months. Rejected because it produces staggered renewal dates across one account, which
breaks `0012`'s annual-discount rule (the discount applies to the set, at one moment) and gives the
tenant several unrelated charges a year instead of one date they can plan for.
