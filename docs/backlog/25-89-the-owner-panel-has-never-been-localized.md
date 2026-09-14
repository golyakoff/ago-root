# 25-89 · The owner panel has never been localized

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: `npm run
  typecheck`/`lint` clean, full `npx vitest run` — 1419/1419 (up from 1414, the +5 is
  `ownerLocale.test.tsx`), matching the worker's own count exactly; the full `ux-gate` Playwright
  suite re-run for real — 63 passed / 5 skipped, `owner-sites` confirmed among the passing (no longer
  among the skipped), proving the real-Chromium-render claim rather than trusting it.
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

- [x] Every user-facing string across all five owner pages reads from `strings`, with a real,
      reviewed Russian translation - not English copied into the Russian slot. 288 new fields added to
      `ConsoleStrings`/`en.ts`/`ru.ts` (1425 → 1713, both automatically cross-checked for key parity -
      zero missing, zero extra, in either direction), covering every plain JSX text node, every prop
      (button `aria-label`s, `Field`/`Dialog`/`Panel` titles and descriptions, placeholders where the
      value is prose rather than a literal example), every table column header (including two built
      from arrays this item's own rough count of 32 nodes never saw), and three server-enum-to-label
      mapping functions in `ownerSites.ts` (`formatModuleStatus`'s "Active"/"Expired"/"Revoked",
      following `11-12`'s own precedent for a backend enum rendered as UI chrome) - a real count against
      the item's own floor, not the floor itself: the rough 32 undercounted for exactly the reasons its
      own text named. Real, reviewed Russian throughout, not a copy - reused `elapsedDayOne`/`Other`,
      `cancelButton` and `navPlatformSites` (pre-existing keys) rather than duplicating them, and added
      one owner-scoped shared block (`ownerNotAuthorizedTitle`, `ownerReasonFieldLabel`/`Description`,
      `ownerCouldNotBeReached`, `ownerAdditionalMinutesLabel`/`Description`, `ownerMinutesInvalid`, and
      others) for phrases identical across two or more of the five pages, rather than five copies.
- [x] A real Russian-locale render of each of the five pages is checked by hand (or by test,
      snapshotting rendered text), not only asserted from the string table. `src/i18n/ownerLocale.test.tsx`
      (new, 5 tests, mirroring `preSessionLocale.test.tsx`'s own established shape) mounts each of the
      five pages exactly as `App.tsx` mounts them and asserts real Russian sentences render while the
      matching English does not. Additionally proven in a real Chromium render, not just jsdom: the
      `ux-gate` Playwright screen `owner-sites` (`/owner`, already in `ux-gate/fixtures/screens.ts`)
      now runs its "no untranslated interface text" assertion for real for the first time - previously
      unconditionally skipped for this screen - and passes.
- [x] The owner panel's own routes are wrapped in their own explicit Russian `StringsProvider`, not
      relying on `StringsContext`'s own bare default or on `25-88`'s own `resolve.ts` change (neither
      reaches these routes) - proven by rendering an owner page with no other locale signal available
      and seeing Russian. Built `OwnerStringsProvider` (`ago-console/src/i18n/OwnerStringsProvider.tsx`)
      rather than reusing `PreSessionStringsProvider` - see "Decided" below for why. `App.tsx`'s five
      `/owner/*` routes each wrap in it, outside `RequireAuth`, the identical position
      `PreSessionStringsProvider` already takes on `/onboarding`/`/redeem-invite`. Proven with a
      fails-before check on the provider itself, not just on the pages: `OwnerStringsProvider`'s own
      `ru` import/value was mechanically inverted to `en`, all 5 of `ownerLocale.test.tsx`'s own tests
      were re-run and failed (each with a real diff - the expected Russian sentence absent, the
      matching English present instead), then the file was restored from a pre-mutation copy and the
      full suite re-run clean (136 files / 1419 tests). `StringsContext`'s own bare default and
      `resolve.ts` are both untouched - `git diff` against `origin/main` confirms neither file is in
      this item's own changed-file list.

**Decided**: `OwnerStringsProvider`, not `PreSessionStringsProvider` reused. The two providers are the
identical three lines (`<StringsProvider value={ru}>`), but the name stops fitting the moment it is
read at `/owner`'s own call site - a signed-in platform owner is not "pre-session" the way a visitor
at `/signup` genuinely is, and `StringsContext.tsx`'s own doc comment already needed a paragraph
distinguishing `/owner`'s old "always English, by design" case from the four pre-session routes' "no
tenant yet, so Russian" case; reusing the pre-session name would have collapsed a distinction that
doc comment spent real words drawing. `OwnerStringsProvider.tsx`'s own doc comment carries the full
reasoning, cross-referenced from `StringsContext.tsx`, `OwnerSitesPage.tsx` and `App.tsx`.

**Real final string count**: 288 new `ConsoleStrings` fields (not 32 - see the ticked box above for
what the rough count missed and why). Full per-page breakdown, `ux-gate` finding, and exact
verification counts are in the worker's own report to the managing session, 2026-09-14.

**`ux-gate` needed a narrow fix, not an extension.** `ux-gate/lib/i18nCompleteness.ts`'s own
"no untranslated interface text" assertion already walks whatever DOM a screen renders - nothing
about the function itself was owner-panel-shaped. What needed fixing was `ux-gate/gate.spec.ts`'s own
per-screen skip list, which carried a `owner-sites` entry whose stated reason ("`/owner` renders in
English... permanent by design") this item overturns. Removed once, run for real, and two real
in-scope gaps it found got fixed (a lowercase "id" that should have reused the already-exempted "ID",
and "API" - already used elsewhere in `ru.ts` but never previously exercised by a gated screen -
added to `EXEMPT_PHRASES`), plus one fixture-authoring bug (`ux-gate/fixtures/data.ts`'s seeded site
name literally embedded this test suite's own name, "ux-gate", inside a value that file's own rule
requires to be pure Cyrillic). What was left after those fixes - three *pre-existing*, real,
already-documented-or-designed gaps this screen was simply the first to exercise
(`OwnerSiteSummary.tier`'s deliberate raw server passthrough, `formatByteSize`'s deliberately-
untranslated unit letters, and `time/format.ts`'s fixed `en-GB` locale, the last already named in this
same file's own "what this deliberately does not exempt" section before this item touched it) - is
why the skip stays, with its own stated reason corrected rather than the row simply deleted. The other
four owner pages were **not** added to `ux-gate/fixtures/screens.ts`: each would need its own new API
stubs and fixture data (`OwnerSiteDetailPage`, `OwnerPricingPage`, `OwnerSuspensionsPage`,
`OwnerTenantIsolationPage` currently have none), which this file's own header treats as a screen
"earning" its place one at a time (`23-06`, `23-37`, `23-18` each did exactly one) - real, separate
scope, not a rider on this item (`CLAUDE.md` rule 15). `src/i18n/ownerLocale.test.tsx`'s own jsdom
coverage of all five pages is what stands in for that today.
