# paying for something does not turn it on

- **Stage**: 23
- **Status**: ready
- **Depends on**: `adr/0151` is the decision it implements. `22-33` is the same seam from the other end.
- **Found**: 2026-09-07 — named as the gap `adr/0151` creates and does not close.

## The author's model, and what is missing from it

*«Он может за что-то заплатить и у него включится, но не сам.»* Payment turns a capability on; the
tenant does not.

**The second half exists and the first does not.** `23-65` gave the platform owner a way to grant a
module by hand. `adr/0151` says an entitlement comes from the platform owner **or from the system on a
payment**. Nothing in this codebase is that system.

`SubscriptionRenewalApplier` and `MarkLapsed` write neither `EnabledModule` nor `ModuleQuantityGrant` —
`22-33` found that from the lapsing side. This is the same absence seen from the paying side: **a
successful payment for an option does not grant anything either.**

So today the only working path from money to capability is a person doing it by hand, and nobody has
noticed because nobody has bought an option yet.

## Why it is worth its own number rather than a line inside billing

It is the join between two systems that have never met. Billing knows about subscriptions, periods and
lapses; entitlements know about modules, quantities and expiries. **Whichever item owns the join owns
the awkward cases**, and there are three worth naming up front rather than discovering:

- **A payment arrives for something already granted by hand.** The owner gave a trial; the tenant then
  pays. Two grants for one capability, and the expiry of one must not silently end the other.
- **A payment fails after the capability is on.** `adr/0073` chose downgrade over stop and did not
  extend that reasoning to add-ons; `22-33` is where that question lives, and this item must not answer
  it by accident.
- **A refund or a chargeback.** ЮKassa has no balance concept (`adr/0073`), so there is no credit to
  reverse — but there is a capability that is on, and something has to decide.

## Scope

- **A payment for an option grants its entitlement**, through the same mechanism the owner's own grant
  uses, so there is one way an entitlement comes into existence rather than two.
- **The grant carries where it came from.** `/owner` already distinguishes *we granted this* from *the
  tenant bought it* (`adr/0118` depends on that distinction to decide whether a revoke needs a reason);
  a system grant must be as legible as a manual one.
- **Idempotent.** A payment notification arriving twice grants once — the same at-least-once assumption
  everything else in this codebase makes.

## Out of scope

- What happens when payment stops. That is `22-33`, and it is a commercial decision rather than a
  mechanism.
- Pricing. `ago-business` `0012` has it.

## Done when

- [ ] A successful payment for an option results in the entitlement, without anybody acting by hand.
- [ ] The same payment arriving twice grants once.
- [ ] A system grant is distinguishable from a hand grant wherever a hand grant is visible today.
- [ ] The three awkward cases above are each answered in the change or explicitly carried out.
