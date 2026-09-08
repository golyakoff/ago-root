# a tenant can buy an option themselves

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-86`, which makes a purchased option representable and applied. This is the way in.
- **Found**: 2026-09-08, splitting `23-86` once it turned out to be a missing noun rather than a missing join.

## What this adds

`23-86` makes a paid option turn a capability on. It says nothing about how a tenant buys one, and
without that the only way to create an option subscription is a seeded row — which is enough to prove
the mechanism and useless to a customer.

**This is the purchase itself**: a tenant sees what is available, chooses one, is told what it will
cost *now*, and pays.

## The arithmetic the screen must get right, because it is the part a customer checks

An option bought mid-period is charged for **the remainder of the account's period**, so that both end
on the same day (`adr/0159`). A tenant on an annual subscription buying a channel on day 128 pays for
**237 days, not 128** — the days they will actually have it.

That distinction was worth writing down: it was stated the other way round in conversation on
2026-09-08 and, taken literally, would have charged for the elapsed part and given away roughly eight
months at the price of four. The screen is where a slip like that becomes real money, so the number it
shows and the number charged come from one calculation, not two.

**Mid-period purchases run at full price** until the renewal date; the annual discount applies to the
whole set at renewal, never retroactively (`ago-business/0012`). So the screen never has to explain a
partial discount, and must not invent one.

## Scope

- **What is on offer comes from the deployment's own declaration** (`23-86`'s configuration), not from
  a list typed into the console. A deployment that declares no options offers none, and the screen says
  so rather than rendering an empty table.
- **The price shown and the price charged are the same number**, computed once.
- **An option the account already holds is not offered again** — including one granted by the platform
  owner by hand (`23-65`), which is an entitlement without a subscription behind it.
- **Cancelling is in scope only as far as `adr/0073` already decided**: it runs to the end of what was
  paid for, and there is no refund and no credit.

## Where this is likely to go wrong

- **Prices must not reach a public repository.** They are `ago-business`'s. The console renders what
  the API tells it and the API reads what the deployment holds; nothing about money is committed here.
- **The platform-owner grant and a purchase can collide.** An account that was given the calendar by
  hand and then buys it has one entitlement and one subscription, and revoking either must not leave
  the tenant with a capability nobody is paying for or without one they are.
- **Two payment rhythms are now visible to a person**, which the commercial grid flagged as the thing
  to check with the first real tenant. The screen is where that becomes concrete: an account can be
  partly paid, and the interface has to say which part.

## Done when

- [ ] A tenant can buy an option without anybody at AGO doing anything.
- [ ] The amount shown before paying is the amount charged, and it covers the remaining days rather
      than the elapsed ones — proved with a mid-period purchase, not only a fresh one.
- [ ] No price of any kind is committed to a public repository.
