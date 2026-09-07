# a lapsed subscription never touches the add-on it paid for

- **Stage**: 22
- **Status**: ready — **and the decision inside it is commercial, not technical**
- **Depends on**: nothing to find it. `22-08` (suspension) is where the mechanism would live.
- **Found**: 2026-09-07, while designing `22-08`.

## What is actually true

`SubscriptionRenewalApplier` and `MarkLapsed` write neither `EnabledModule` nor `ModuleQuantityGrant`.
A tenant whose subscription lapses is downgraded to the free chat tier — `adr/0073` chose a downgrade
over a stop deliberately — and **keeps the calendar add-on, and its full worker quota, indefinitely.**

Nothing expires it, nothing revokes it, nothing tells the calendar. The add-on outlives the payment
that bought it, for as long as the account exists.

## Why this is not simply a bug to fix

`adr/0073` decided that non-payment produces a **downgrade rather than a stop**, and that reasoning is
sound for the chat tier: a shop that misses a payment should not have its customers meet a dead widget.
Whether it extends to a paid add-on is a different question with a different answer, and nobody has
taken it.

Two shapes, and the choice is the author's:

- **The add-on lapses with the subscription.** What was paid for stops when payment does, which is what
  a customer would expect of an add-on. Needs `22-08`'s suspension mechanism, and needs an answer to
  what happens to bookings already made — `22-07` already says nothing a shop typed is destroyed by a
  billing action, and a stranger's appointment is not leverage.
- **The add-on survives, deliberately**, as part of the same generosity `adr/0073` chose. Then it is not
  a defect at all — but it must be written down, priced, and said out loud, because right now it is
  neither a decision nor a mistake, just something nobody wrote.

## Why it matters now rather than later

The first paying customers are weeks away. This is the difference between an add-on that is sold and an
add-on that is given away to anyone who stops paying, and it is cheaper to decide before there is a
customer on the wrong side of it.

## Done when

- [ ] The author has chosen, and the choice is recorded where somebody pricing the add-on will read it.
- [ ] Whatever was chosen is implemented, or the item is closed as not-planned with the reasoning kept.
- [ ] `adr/0073` says whether its downgrade-not-stop reasoning covers add-ons, either way.
