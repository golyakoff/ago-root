# paying for something does not turn it on

- **Stage**: 23
- **Status**: ready — **`ago-chat#233` shipped the core mechanism (option-as-subscription, aligned
  renewal, entitlement grant/revoke) 2026-09-08. The three awkward cases are answered in dialogue,
  2026-09-13 — see *Answered*, below. What remains open to build: the unconditional-grant flag and its
  OR-read, and the `ago-deploy` manifest declaring what an option actually turns on — see Done when.**
- **Depends on**: `adr/0159` for the shape. `22-33` is the commercial question this deliberately does not answer.
- **Found**: 2026-09-07 — named as the gap `adr/0151` creates and does not close.

## What was filed, and what is actually true

Filed as *"a successful payment for an option does not grant anything"*. Verified in code on
2026-09-08: nothing on the billing path writes an `EnabledModule` or a `ModuleQuantityGrant`.

**The reason is one level deeper than that.** `BillingSubscription` carries `Tier` and
`RequestedSeats` and nothing else. **There is no concept of a purchased option anywhere in the
domain** — so "the tenant paid for the channel" cannot be written down, never mind applied. The item
was filed as a missing join between two systems; it is a missing noun.

So today the only path from money to capability is a person doing it by hand (`23-65`), and nobody has
noticed because nobody has bought an option yet.

## The promise this item makes

**Paying for an option turns it on, and its lapsing turns it off.** One promise in both directions,
because a grant nothing can withdraw is not what a subscription means, and shipping only the grant
would hand the next item a half-mechanism to reason about.

## Scope

- **A subscription states what it is for.** One per account is the base — tier and seats, exactly what
  exists now. Others each name an option, by key.
- **An option's period is the account's**, not one of its own: `CurrentPeriodEnd` copied from the base
  at purchase (`adr/0159`), so both renew on the same date and the annual discount can apply to the set
  as the commercial grid requires.
- **A renewal that succeeds grants the entitlement; a lapse revokes it**, both inside the same
  transaction the applier already uses, published through the outbox the module registry already reads
  (`23-102`/`23-104` established that path).
- **The option-to-entitlement mapping is deployment configuration**, resolved by key — the shape
  `adr/0154` set for entry points and `23-102` for permissions. The deployment declares *what an option
  turns on*; it never declares what one costs.

## The three awkward cases, kept from this item's first draft

Whichever item owns the join owns these, and they are worth naming rather than discovering. They were
dropped when this file was rewritten on 2026-09-08 and are restored here — the rewrite was right about
the shape and careless about what it replaced.

- **A payment arrives for something already granted by hand.** The owner gave a trial; the tenant then
  pays. Two grants for one capability, and the expiry of one must not silently end the other.
- **The grant carries where it came from.** `/owner` already distinguishes *we granted this* from *the
  tenant bought it*, and `adr/0118` depends on that distinction to decide whether a revoke needs a
  reason. A system grant must be as legible as a manual one.
- **A refund or a chargeback.** ЮKassa has no balance concept (`adr/0073`), so there is no credit to
  reverse — but there is a capability that is on, and something has to decide. `adr/0160` settled the
  neighbouring case (a base lapse does not touch a paid option) and deliberately did not settle this
  one.

## Answered, 2026-09-13

All three awkward cases, settled in dialogue with the author:

**1. A payment arrives for something already granted by hand.** Every entitlement gets its own
**unconditional-grant flag**, independent of and orthogonal to whatever the billing-driven read already
checks (a `CurrentPeriodEnd`/paid-until fact) — never a second, competing write to the same field. The
two sources combine by **OR**: an entitlement is on while *either* the flag is set *or* billing says the
option is currently paid. Concretely:

- Flag set, billing active — both true at once is not a conflict to resolve; billing is simply
  redundant for as long as the flag stands, and that is fine, not a state anything needs to notice.
- Flag lifted, billing still active — the entitlement survives on billing alone; nothing about lifting
  the flag re-provisions or interrupts it.
- Flag lifted, billing lapsed or absent — the entitlement goes off. This is the one case where a write
  actually changes the outcome, so it is the one path that has to re-evaluate billing at the moment the
  flag is lifted, not assume the prior "on" state persists.

The flag can **only ever be set by the platform owner** — the same actor `adr/0118`'s own forced-revoke
already holds to a stated reason, applied here to the grant side of the same relationship.

**2. The grant's own provenance.** Settled as already proposed and confirmed without change: a manual
grant is always attributed to the owner who set it (case 1's flag has exactly one legitimate writer);
an automatic revoke driven by a lapsed subscription is self-documenting — "the subscription lapsed" is
itself the reason, the identical `OperatorId.System`-plus-reason-string shape already used elsewhere in
this codebase for a system-triggered act, not a gap needing new machinery.

**3. A refund or a chargeback.** **Moot by policy — no refunds are offered at all**, so there is no
credit-reversal case for the domain to model. Noted, not built around: a card-network chargeback can
still be initiated by an issuing bank regardless of a stated no-refunds policy — rare enough, by the
author's own call, to fall back on the identical manual owner-revoke path case 1 already provides rather
than earning any automation of its own.

## Where this is likely to go wrong

- **`GetBillingStatusHandler` becomes wrong silently, and it is the only such reader.** It calls
  `GetLatestForSiteAsync` and means *the site's subscription*. With options in the same table it
  returns whichever row is newest, so a tenant who just bought a channel sees the channel where their
  tier should be. Narrow that read in this change or it ships as a bug nobody is looking for.
- **The renewal job needs nothing.** `ListDueForRenewalAsync` is set-based over `(status,
  current_period_end)`, so options renew, retry and lapse through the code that already does it for
  tiers. Resist the urge to give options their own job.
- **Do not answer `22-33` by implementing it.** What happens to an option when the *base* lapses is a
  commercial question — the author has said a channel is meaningless without chat, which is an argument
  and not yet a decision. This item covers an option's own payment only.
- **Idempotence, as everywhere.** A re-granted entitlement must merge rather than duplicate; `23-102`
  already established that `AddPermissionsAsync` merges, and the same must hold here.

## Done when

- [x] A purchased option can be written down, and its period ends on the same day as the account's base.
      — `ago-chat#233`: `BillingSubscription.OptionKey`, `MarkSucceeded`'s aligned-period invariant.
- [x] An option whose renewal succeeds has its entitlement; one that lapses does not — shown in both
      directions rather than argued, against a real database. — `SubscriptionRenewalApplier` grants/
      revokes via `IModuleQuantityGrantStore` in the same transaction; fails-before re-proved
      independently (removing the grant call fails 3/12 `SubscriptionRenewalJobTests` against real
      Postgres).
- [x] Nothing that reads "the site's subscription" can be handed an option instead. —
      `GetBillingStatusHandler`'s `GetLatestForSiteAsync` leak fixed in the same PR.
- [~] The deployment declares what an option turns on, and no price of any kind enters a public
      repository. — **half done.** The mechanism exists (option-to-entitlement mapping resolved by
      key, mirroring `IModuleEntryPointProvider`) and no price entered this repository — but the
      `ago-deploy` manifest change that actually declares a mapping is explicitly **not** in
      `ago-chat#233` ("the ago-deploy manifest change is not in this branch"). No option can actually
      grant anything real yet until that manifest lands.
- [x] Each of the three awkward cases above is answered in the change or explicitly carried out to
      its own number. — **answered, 2026-09-13** (see *Answered*, above); none of the three is built
      yet (`ago-chat#233` predates this dialogue), so implementing the unconditional-grant flag and
      wiring the OR read remains real work, carried by this same item rather than a new number, since
      the answer was reached here.
