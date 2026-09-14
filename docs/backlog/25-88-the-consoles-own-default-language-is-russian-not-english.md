# 25-88 · The console's own default language is Russian, not English

- **Stage**: 25
- **Status**: done — `ago-console#233`. Built directly by the managing session this time, not a
  background worker (the scope turned out too intertwined with a live, real-time investigation to
  hand off cleanly) — `npm run typecheck`/`lint` clean, full suite 134/134 files, 1398/1398 tests,
  not just the files expected to be affected.
- **Depends on**: nothing to build this item's own scope, but **`25-89` is what makes this item
  visible on the platform owner's own screens** - the owner panel has never been localized at all
  (`25-89`'s own finding), so this item's fallback flip has nothing to switch there yet. Found while
  scoping this item: the author asked directly whether it already covered owner-panel translation.
  It does not, and structurally could not - see `25-89`.
- **Decision**: the author's own, 2026-09-14 - "I'm Russian and it's more convenient for me," stated
  directly, and consistent with this deployment's own actual market (`docs/adr/README.md`'s own
  commercial-intent memory, `ago-business`'s Russian-language convention).
- **Found**: 2026-09-14, the author's own walkthrough of the platform-owner screens - they render in
  English, with no site in context to read a locale from. **This item alone does not fix that specific
  walkthrough** - the owner panel's strings are hardcoded English, not read from `strings` at all, so
  flipping the fallback changes nothing there until `25-89` lands. This item still stands on its own:
  every *other* no-site screen (sign-up, the OIDC callback, anything already routed through
  `getStrings`) does change today.

## What is actually true - two defaults, not one

`ago-console/src/i18n/` has **two** separate places a "no locale known" case falls back to a
language, found while building this item, not before:

1. **`resolve.ts`'s `parseConsoleLocale`** - the function `OperatorShell`'s tenant-scoped provider
   calls with a real site's own `Locale` field. `"Ru"` resolved to `"ru"`; everything else (`null`,
   `"En"`, or a value this console has never heard of) resolved to `"en"`. **This is the one this
   item actually changes** - the fallback branch now resolves to `"ru"`, and only an explicit `"En"`
   still resolves to `"en"`.
2. **`StringsContext.tsx`'s own bare React-context default** (`createContext<ConsoleStrings>(en)`) -
   what `useStrings()` returns for any component mounted with no `StringsProvider` above it at all.
   `/owner` is the deliberate, permanent case (`OwnerSitesPage`'s own doc comment, `11-11`'s settled
   call: "not scoped to one tenant, so it always falls through to this bare default, on purpose,
   forever"). **This item investigated flipping this one too - and found it must not, not in this
   pass.** A full test-suite run with it flipped surfaced **562 failing tests across 69 files** -
   components mounted bare in test harnesses throughout this codebase (not just `/owner`) rely on
   this bare default resolving to English, for reasons ranging from "this is a real transient
   pre-provider render state" (`WorkerScheduleSection.test.tsx`'s own doc comment names this
   explicitly) to simple test-harness convenience never audited against a locale change. Reverted;
   left exactly as it was (`en`).

**This already has a precedent that went the other way, for the narrower case.** `23-28`'s own
reasoning, already live in `App.tsx`, for a pre-session screen with no site to follow: "no site, no
locale to read, and the answer is Russian rather than English." That item deliberately did *not*
touch the bare `StringsContext` default either - it wrapped its four routes in their own
`PreSessionStringsProvider` instead, precisely so the bare default's own much wider surface stayed
untouched. This item's own `resolve.ts` change follows the same shape as `23-28`'s actual mechanism
(a narrow, explicit override), not the shape this item originally assumed it would take (a single
global flip).

## Scope

- `parseConsoleLocale`'s fallback branch changes from `"en"` to `"ru"` - real tenant sites whose own
  `Locale` field is unset or unrecognized now read Russian, matching `23-28`'s own reasoning applied
  structurally to this one function.
- **A site's own configured `Locale = "En"` is untouched** - this item changes the *fallback* only,
  never a real, explicit tenant choice.
- **The platform owner's own screens are explicitly out of this item's own scope**, corrected from
  this item's own earlier draft: they do not read `parseConsoleLocale` at all (`OwnerSitesPage`
  mounts with no `StringsProvider`, reaching `StringsContext`'s own bare default instead), and that
  bare default is not touched here - see "What is actually true" above for why. `25-89` is where the
  owner panel actually gets a Russian default, **by wrapping its own routes in an explicit
  `<StringsProvider value={ru}>`** (the identical, already-established `PreSessionStringsProvider`
  pattern `23-28` used), not by this item's own mechanism.

## Where this is likely to go wrong

- **Every existing test that asserts English by default may be asserting the old fallback, not a
  requirement - and the blast radius is real, not theoretical.** Beyond the three locale-specific
  files (`consoleLocale.test.tsx`/`workspaceLocale.test.tsx`/`siteConfigLocale.test.tsx`, all fixed
  by this item), `permissionGating.test.tsx` alone lost 18 passing tests to this change - a
  navigation-gating test suite that was never about locale, incidentally asserting English section
  labels because that used to be the only value `fetchMyPermissions`'s own mock response could
  produce. Fixed by pinning that file's shared mock helper to `locale: "En"` explicitly (so it tests
  permission gating, stably, regardless of this default's own value) rather than rewriting 18 tests'
  worth of labels to Russian for a file that is not actually about language.
- **Two genuinely-in-flight-or-failed-permissions test cases in that same file were correctly left
  Russian, not pinned.** "Nothing known yet" (a pending or rejected `fetchMyPermissions` call) has no
  real locale to pin - the new default showing through there is the actual, intended behaviour, not
  an artifact.

## Done when

- [x] A tenant's own site with an unset or unrecognized `Locale` renders in Russian -
      `parseConsoleLocale`'s own new fallback, proven by `consoleLocale.test.tsx`/
      `workspaceLocale.test.tsx`/`siteConfigLocale.test.tsx`'s own updated "no Locale set" cases.
- [x] A tenant's own site with an explicit `Locale = "En"` still renders in English, unchanged -
      proven by new sibling test cases in the same three files (none existed for this case before).
- [x] The full `ago-console` test suite passes with the change in place - not merely the three files
      expected to be affected; `permissionGating.test.tsx`'s own 18 incidental failures were found and
      fixed by pinning its shared mock's locale, not by discovering them after merge.
- [ ] The platform owner's own screens render in Russian - **explicitly not this item's own box any
      more**, corrected once the two-default finding above was made. See `25-89`.
