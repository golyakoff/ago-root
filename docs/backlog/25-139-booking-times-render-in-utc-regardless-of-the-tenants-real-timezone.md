# 25-139 · Booking times render in UTC regardless of the tenant's real timezone

- **Stage**: 25
- **Status**: not planned — superseded by `25-145`
- **Found**: 2026-09-17, while investigating the author's reported booking-flow issues (not itself
  reported by the author) - filed per the standing rule that a found defect gets a number of its own
  rather than being folded into an unrelated item or left unfiled.
- **Depends on**: none identified yet - likely relates to `25-16` ("calendar timezone becomes a
  localized dropdown"), which should be read first by whoever picks this up.

## The gap

`ModuleStepFactory`'s own `DescribeRange` and `DescribeTimeOnly` (`ago-calendar/src/
Ago.Calendar.Application/UseCases/ChatModuleTask/ModuleStepFactory.cs:196-202`) render every slot and
every confirmation's own time in UTC, labelled `"UTC"` - correct per `docs/conventions/
date-and-time.md` rule 1 ("no visitor IANA zone is known in a chat channel... render UTC labelled as
UTC"), and `25-37`'s own scope explicitly left this alone for exactly that reason.

The rule's premise - "no zone is known for the visitor" - is arguably wrong for this specific case:
the visitor isn't booking into an unknown timezone, they're booking a slot on **the tenant's own
calendar**, which almost certainly operates in one fixed, known zone (the shop's own location).
`25-16` ("calendar timezone becomes a localized dropdown") suggests the calendar side of this system
already has some notion of a tenant timezone. If so, a visitor booking "14:00 UTC" for what is
actually a 17:00 Moscow-time appointment is a real, live-blocking usability defect for exactly the
kind of Russian small-business tenant this product targets - not a hypothetical.

## Scope

Not yet determined - this needs a decision, not just an implementation:

- Confirm what `25-16` actually built: does a `Site`/calendar already have a stored IANA timezone
  today, or only a UI affordance with nothing behind it yet?
- If a real tenant timezone exists, decide whether `ModuleStepFactory` should render slot times in
  it (labelled with the zone, not silently converted with no indication) - which would mean this
  factory needs that zone threaded to it the same way `25-37` threaded `locale`.
- If no tenant timezone exists yet, this item is really "give the calendar a timezone," a
  substantially bigger item that `25-16` may already be scoped to cover - don't duplicate it.

## Where this is likely to go wrong

- Don't guess a timezone from the visitor's own IP, browser locale, or phone country code -
  `date-and-time.md` rule 1 forbids exactly this, for good reason (a visitor booking on behalf of
  someone else, a VPN, a business traveler). The tenant's own configured zone is the only zone
  that's actually correct here, if one exists.

## Done when

Not yet defined - this item needs its own scoping pass (see Scope) before a Done-when list can be
written honestly.

## Outcome

Superseded by `25-145` (filed 2026-09-18, after the author hit this exact gap live and reported it in
detail): `25-16` had already given the calendar a real, tenant-configured `TimeZone` before this item
was even filed - the actual scoping pass this item deferred - so `25-145` carries the real fix rather
than this placeholder. Closed as not-planned rather than done; the promise this item represented is
being carried out under `25-145`'s own number, not this one.
