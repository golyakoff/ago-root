# 25-89 · The owner panel has never been localized

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing to build. **Corrected 2026-09-14, once `25-88` was actually built**:
  `25-88`'s own fallback flip (`resolve.ts`'s `parseConsoleLocale`) never reaches the owner panel at
  all - `OwnerSitesPage` and its siblings mount with no `StringsProvider` above them, so they read
  `StringsContext`'s own bare React-context default instead, which `25-88` investigated flipping and
  found could not be flipped safely in one pass (562 test failures across 69 files, see that item's
  own Outcome). This item's own scope therefore includes giving the owner panel **its own explicit
  Russian provider** - see Scope below - not merely reading from `strings`.
- **Found**: 2026-09-14, the managing session's own check while scoping `25-88` - the author asked
  directly whether that item already covered translating the owner panel. It does not, and could not:
  `grep -c "strings\." src/owner/*.tsx` returns **zero** across all five real owner pages
  (`OwnerPricingPage`, `OwnerSiteDetailPage`, `OwnerSitesPage`, `OwnerSuspensionsPage`,
  `OwnerTenantIsolationPage`). Every string in the owner panel is a hardcoded English JSX literal, not
  routed through `getStrings(locale)` at all - `11-12`'s own console-i18n pass (`ago-console#46`)
  never reached this section, and nothing since has either.

## What is actually true

A rough count of plain JSX text nodes alone (`grep -oE ">[A-Za-z][a-zA-Z0-9 ,.'()/-]{3,}<"`) finds
**32** across the five pages - an undercount, since it misses text passed as props (button labels,
`aria-label`s, table column headers built from arrays, template strings interpolating a value). The
real figure is comparable in shape to `11-12`'s own operator-workspace pass, just never done for this
one section.

## Scope

- Every user-facing string in the five owner pages above moves into `ConsoleStrings`
  (`ago-console/src/i18n/strings.ts`), with a real English and a real Russian value in
  `en.ts`/`ru.ts` - not a placeholder, not a literal copy of the English text into the Russian file
  standing in for translation (the same "no placeholder shipped as if it were real" standard this
  codebase already holds itself to for every other locale pair).
- Follow `11-12`'s own precedent for shape and tone rather than inventing a new one - read that
  item's own merged diff (`ago-console#46`) first.
- **The owner panel's own routes wrap themselves in an explicit `<StringsProvider value={ru}>`** -
  the identical, already-established `PreSessionStringsProvider` pattern `23-28` built for exactly
  this situation (a route with no tenant to read a locale from, that must not rely on `StringsContext`'s
  own bare default, because that default's own blast radius across the rest of this codebase is why
  `25-88` could not simply flip it). A new `OwnerStringsProvider` (or reusing `PreSessionStringsProvider`
  directly, if its own name still fits once read) is this item's own to decide - either way, **do not
  change `StringsContext`'s own bare default**, and do not change `resolve.ts` either - both are other
  items' own scope, already settled.

## Where this is likely to go wrong

- **`ux-gate`'s own i18n-completeness check** (`ux-gate/lib/i18nCompleteness.ts`, referenced in
  `AppShell.tsx`'s own remarks tonight) may already assume every route is covered, or may need
  extending to actually walk the owner routes for the first time - check which, rather than assuming
  either.
- **A string shared between an owner page and something else** (a shared component, a shared error
  message) should not get a second, duplicate key - grep `strings.ts` for a near-identical English
  value before adding a new one.

## Done when

- [ ] Every user-facing string across all five owner pages reads from `strings`, with a real,
      reviewed Russian translation - not English copied into the Russian slot.
- [ ] A real Russian-locale render of each of the five pages is checked by hand (or by test,
      snapshotting rendered text), not only asserted from the string table.
- [ ] The owner panel's own routes are wrapped in their own explicit Russian `StringsProvider`, not
      relying on `StringsContext`'s own bare default or on `25-88`'s own `resolve.ts` change (neither
      reaches these routes) - proven by rendering an owner page with no other locale signal available
      and seeing Russian.
