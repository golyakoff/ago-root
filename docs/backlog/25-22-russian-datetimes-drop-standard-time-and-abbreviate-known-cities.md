# 25-22 · Russian-locale datetimes drop "стандартное время" and abbreviate known cities

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-09, the author reading a timestamp in the console

## What is actually true

`ago-console/src/time/format.ts`'s Russian rendering carries a `", стандартное время"` tail wherever
the underlying `Intl` timezone-name formatting supplies one. This deployment's own zones do not observe
daylight saving (`24-17` already settled the numbers this rests on) — "standard time" is always true
here and never worth saying, so the phrase adds nothing a reader needs.

## Scope

- Drop the `", стандартное время"` (and any `", летнее время"` equivalent, in case a future zone ever
  needs one — it will not on this deployment today, but the fix should remove the tail rather than
  special-case one specific string) from the Russian rendering.
- **Abbreviate a city name where a standard Russian abbreviation exists** — "Москва" → "МСК" is the
  example given. Use a real, checkable list of standard abbreviations (Russia's own regional time-zone
  abbreviations, e.g. МСК/МСК+1 etc. for the zones this deployment actually offers per `25-16`'s own
  scope) rather than inventing shortenings. **Where no standard abbreviation exists for a city this
  deployment might show, leave the full name** ("Москва") rather than guess at one.

## Where this is likely to go wrong

- **Do not abbreviate speculatively.** A made-up abbreviation is worse than the full name it replaces
  because it looks authoritative while being wrong. Only abbreviate what actually has a standard,
  checkable short form.
- **This utility is shared** — check every caller of `time/format.ts`'s Russian path before assuming
  the tail is only cosmetic in one place; a timestamp rendered elsewhere (e.g. `25-21`'s "who accepted"
  list, once built) inherits this fix for free, which is the reason to fix it here rather than per
  screen.

## Done when

- [ ] Russian-locale datetime rendering never appends "стандартное время" (or a DST equivalent).
- [ ] A city with a standard Russian abbreviation renders abbreviated (Москва → МСК); one without stays
      full, and the list used is named and checkable rather than invented ad hoc.
