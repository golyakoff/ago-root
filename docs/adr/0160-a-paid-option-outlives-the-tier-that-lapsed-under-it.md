# ADR-0160: A paid option outlives the tier that lapsed under it

- **Status**: Accepted
- **Date**: 2026-09-08
- **Stage**: 23

## Context

`adr/0073` decided that non-payment of the chat tier produces a **downgrade rather than a stop** — a
shop that misses a payment should not have its customers meet a dead widget. `22-33` found that the
reasoning had never been extended to a paid add-on, and that today nothing revokes one at all: the
add-on outlives the payment that bought it, indefinitely, because no code path touches it.

`adr/0159` then made each option its own subscription with its own money and its own failure window.
That settles what happens when an *option* is not paid for. It leaves the harder case, which is
commercial rather than technical: **the base lapses to the free tier while an option is still paid
for.**

The author answered two questions in sequence, and the second only makes sense with the first:

1. *"Можно заплатить на бесплатном 100 рублей и пользоваться бесплатным тарифом с доп. каналом"* — an
   option is sellable to an account on the free tier. Checked against the commercial record: nothing
   in the tariff grid scopes options to the paid tier, and the free-tier cost criterion
   (`ago-business/0001`, marginal cost that grows with use) is *better* satisfied by a paying free
   account than by a silent one.
2. *"Канал продолжает работать, пока не кончится оплата — максимум год."*

## Decision

**A paid option is not cancelled by the lapse of the tier beneath it.** It runs on its own
subscription and its own money: the base falls to the free tier, and the option keeps working for as
long as it is paid for.

**"Maximum a year" is the horizon of a single paid period, not a stop.** The longest period this
system sells is annual, so an option can be paid at most a year ahead; while payment continues it
continues. That is the reading applied here, and it is the one that makes both of the author's
statements true at once — an option sellable on the free tier cannot also be one that must die when
the tier is free.

**So an option's life is decided by its own charges and by nothing else.** There is no rule anywhere
that reads "if the base is not active, the option stops".

## Consequences

**`22-33` is answered, and answered in the generous direction** — the same direction `adr/0073` chose
for the tier. Nothing that a tenant paid for is taken away because something else was not paid for.

**It is what `adr/0159` already does by construction**, which is the useful part: two subscriptions
with no relationship a charge can traverse. This decision adds no mechanism; it *declines* to add one.
An implementation that has to check the base's status in order to decide an option's fate has
misunderstood this ADR.

**An account can be on the free tier and paying.** That state is now normal rather than exceptional,
and everything downstream must read entitlements rather than infer them from a tier name. It also
means "free account" stops being a synonym for "brings no revenue" in any reasoning about cost.

**One existing rule contradicts this and has to move**, which is the reason this ADR is worth writing
rather than leaving as a line in an item. The commercial grid exempts an account from auto-deletion
for inactivity **under the paid tier's heading** — *"автоудаления за бездействие нет, пока идёт
оплата"* — while the free tier is deleted after three months without a sign-in. Read literally, an
account paying for a channel on the free tier is deleted for not signing in, taking its conversations
and contacts with it. **The exemption belongs to the fact of payment, not to the name of a tier.**
`23-116` carries that correction, and it is cheap because `23-73` has not been built yet: this is a
specification change ahead of implementation rather than a defect in production.

**What is deliberately not decided here:** whether an option should be *offered* to a free-tier account
in the purchase screen, as opposed to surviving there. Surviving and being sold are different
questions and `23-115` holds the second.

## Alternatives considered

**The option lapses with the base.** What `22-33` framed as the customer-expectation answer: you
stopped paying for the thing, so the thing attached to it stops. Rejected because the premise is
false here — the option *is* still being paid for. Its neighbour, "a channel is meaningless without
chat", does not survive contact with the facts either: chat still works, on the free tier, and a
Telegram channel over two operators and two months of history is a perfectly sensible product.

**Stop charging for the option when the base lapses, and let it run out.** Kinder-sounding, and
rejected as worse: it silently cancels something the customer chose, and `adr/0073` already ruled out
credit and refunds, so the tenant would lose the capability and get nothing back. If a tenant wants
the option gone they can cancel it, which already runs to the end of the paid period.

**Requiring an active base for an option to renew.** The reading of *"максимум год"* as a hard stop.
Rejected because it contradicts the author's own prior answer that options are sellable on the free
tier: a rule that lets you buy a channel on Solo but not keep one there is two rules disagreeing about
the same account.
