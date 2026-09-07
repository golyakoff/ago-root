
# ADR-0142: A service's price is honest, not exact — kopecks, an optional "от" floor, and never repeated in the booking confirmation

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23

## Context

`23-35` was answered by the author on 2026-09-06: a service has a price and a description, both on
the service itself. Three things were deliberately left to the change rather than decided in the
backlog item: what a price *means* when a service's real cost depends on the master or the job's own
length, whether a visitor sees a price before booking, and — not named explicitly, but forced by the
first two — how money is represented at all, since this is the first price field anywhere in this
codebase and `CLAUDE.md` names that choice a precedent every later price follows.

`Ago.Calendar.Domain.Service` already stores `Duration` as whole minutes in an `int`, never a `decimal`
or a Postgres `interval` — the domain's own invariant ("a whole number of minutes") already fits the
column, and an integer stays exact and orderable. No analogous invariant exists for money yet.

The item's own text names the risk directly: *"a shown price that is routinely wrong is worse for the
tenant than no price, because the visitor remembers the number"*, and gives the concrete shape of the
problem — *"«от 2000 ₽» versus «2000 ₽» — a haircut priced by hair length is the normal case, not the
edge one."*

## Decision

**Money is kopecks in an `int`, plus a currency code, never a `decimal`.** `Ago.Calendar.Domain.Money`
is a small value type: `MinorUnits` (int) and `CurrencyCode` (string), validated together. It is
mapped as one EF Core **nullable complex property** across `services.price_minor_units` and
`services.price_currency_code`, not two independently-settable columns — the same "two columns that
must agree are two columns that can disagree" reasoning `data-model.md` already gives
`sites.demo_expires_at`/`is_demo`. **v1 accepts exactly one currency, `"RUB"`**, validated in `Money`'s
own constructor rather than a database `CHECK`: nothing before this needed a second currency, and a
per-tenant "which currency" setting is a real feature with its own UI, not a byproduct of two columns.

**A price is not a single number's worth of semantics — it carries `PriceIsFrom`.** The tenant states,
per service, whether the stored amount is exact or a floor. `true` renders with an "от" ("from")
prefix; `false` renders as the number alone. This is what answers "what does a price mean when the
real cost varies by master or duration": rather than the product picking one universal reading (always
exact, or always approximate), the operator says which this particular service's number is.
`PriceIsFrom` is meaningless — and normalised to `false` — whenever `Price` is `null`, enforced in
`Service`'s own constructor so the two fields can never disagree.

**Both a price and a description are optional, independently, and `null` means exactly "not stated" —
never a zero or an empty string standing in for absence.** A shop still setting itself up, or one that
deliberately never states a price, is a real and legitimate state.

**A visitor sees the price and description before booking**, on the embed's own scoped read
(`EmbedScopeResolver`, `IBookingSurfaceReadStore` → `BookableServiceRow` → `BookableServiceResponse`)
and on the chat-channel equivalent (`ModuleStepFactory.DescribeService`) — the same fact, the same
shape, on every booking-capable surface, matching `20-06`'s own "expressible as a prompt and a list of
labelled choices" constraint. **The price is never carried into `BookingConfirmedResponse`.** A number
shown before a booking is a courtesy the visitor can act on knowing it may be a floor; the identical
number restated after a booking exists reads as a receipt — the evidentiary weight `23-35`'s own Goal
warns against taking on for a value this product does not enforce or collect.

## Consequences

**Positive.** A price that is sometimes wrong is never presented as certain — `PriceIsFrom` gives the
tenant an honest way to say so per service, rather than the product silently overstating precision or
forcing every price to read as approximate. Kopecks-in-an-int is exact under every arithmetic this
product will do with it (there is none yet beyond storage and display) and orders correctly in SQL if
a later item ever needs to. The complex-property mapping means "a price with no currency" is not a
state the aggregate, or the database, can represent — the same class of bug `demo_expires_at`/`is_demo`
avoids by construction rather than by discipline.

**Negative, named rather than hidden.** `PriceIsFrom` is one more field an operator must understand and
set correctly; a tenant who leaves it `false` on a genuinely variable service still shows an exact
number nobody promised. Nothing here prevents that — the mechanism gives an honest label available, it
does not force its use. `Money`'s single-currency acceptance means a tenant billing in more than one
currency cannot be modelled at all today; widening it is additive but is not designed here, and a
tenant with that need is currently unserved. The chat-channel description text
(`ModuleStepFactory.DescribeService`) is hand-formatted English rather than reusing the console's own
Russian-first copy — a real, narrow inconsistency between two renderers of the same data, acceptable
because `21-01`'s own channel-adapter text is not this item's scope to localise.

## Alternatives considered

- **A bare `decimal` price, no currency field.** Rejected outright — this is precisely the shape
  `CLAUDE.md`'s own warning names: a `decimal` with no currency alongside it is the choice that hurts
  every later price this project adds, and floating/decimal display arithmetic is not what an exact
  integer-minor-units amount needs to inherit.
- **One universal reading for what a stored price means** (always exact, or always "from"). Rejected:
  the backlog item's own example — a fixed-price consultation and a haircut priced by hair length —
  are both real and both common, so a single global rule would either overstate every variable
  service's precision or under-communicate every fixed one's certainty by prefixing "от" on a number
  that never varies.
- **Show the price only internally (the console), never to the visitor.** Rejected: the product is a
  booking surface for small service businesses, where showing a price (often as "от") before booking
  is the ordinary, expected practice, and the backlog item's own framing leans toward embracing that as
  the honest normal case rather than treating disclosure as the risk.
- **Carry the price into `BookingConfirmedResponse`.** Rejected: that response is deliberately built to
  carry nothing beyond what a customer needs to identify the appointment (its own doc comment states
  this as the type's central design decision), and a price shown before booking is a courtesy;
  the identical number repeated in a confirmation becomes evidence of a commitment this product has no
  mechanism to keep or enforce — `23-35`'s own Out-of-scope names payment as `13-xx`'s problem, not
  this one's.
- **A separate documents/versioning mechanism for the description, per `adr/0114`'s reasoning.**
  Rejected: `adr/0114`'s reasoning ("text is data, not code, so a wording fix should not need a
  deploy") already holds without its mechanism — a service description is a plain `Service.Description`
  column, edited through the existing authenticated console endpoint, which is already not a deploy.
  Building a second document-publishing/versioning system for a one-paragraph marketing blurb would be
  the premature generalisation `clean-architecture.md` warns a platform-shaped type against, applied
  here to a product-shaped one.
