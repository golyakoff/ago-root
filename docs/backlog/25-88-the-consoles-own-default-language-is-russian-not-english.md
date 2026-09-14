# 25-88 · The console's own default language is Russian, not English

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Decision**: the author's own, 2026-09-14 - "I'm Russian and it's more convenient for me," stated
  directly, and consistent with this deployment's own actual market (`docs/adr/README.md`'s own
  commercial-intent memory, `ago-business`'s Russian-language convention).
- **Found**: 2026-09-14, the author's own walkthrough of the platform-owner screens - they render in
  English, with no site in context to read a locale from.

## What is actually true

`ago-console/src/i18n/resolve.ts`'s `parseConsoleLocale` is the one place this console maps a raw
value to a language: `"Ru"` (`Ago.Chat.Domain.Locale`'s one non-default member) resolves to `"ru"`,
and **everything else - a `null` active site, `"En"`, or anything this console has never heard of -
resolves to `"en"`.** That fallback is why the platform owner's own screens - which have no one
tenant's site to read a configured locale from at all - render in English: there is nothing to
override the default, and the default is English.

**This already has a precedent that went the other way.** `23-28`'s own reasoning, already live in
`App.tsx`, for a pre-session screen with no site to follow: "no site, no locale to read, and the
answer is Russian rather than English." `parseConsoleLocale`'s own fallback never got the same
treatment - it is the one place this reasoning was not applied, not a deliberate second answer to the
identical question.

## Scope

- `parseConsoleLocale`'s fallback branch changes from `"en"` to `"ru"`. This is a single, structural
  default - not scoped only to owner routes - so it also changes what a tenant's own site sees if that
  site's own `Locale` is somehow unset or unrecognized (rare; `RegisterSiteHandler`/`MintDemoTenantHandler`
  already set a real value on every site this platform creates, so this mostly changes the
  platform-owner screens in practice, but say so rather than assume the blast radius stops there).
- **A site's own configured `Locale = "En"` is untouched** - this item changes the *fallback* only,
  never a real, explicit tenant choice. An English-configured tenant's own console keeps reading
  English exactly as it does today.
- The platform owner's own screens - the concrete case that found this - render in Russian once this
  ships, proven by loading one with no site context, the same walkthrough that found the gap.

## Where this is likely to go wrong

- **Every existing test that asserts English by default is asserting the old fallback, not a
  requirement.** Read `consoleLocale.test.tsx`/`preSessionLocale.test.tsx`/`workspaceLocale.test.tsx`
  (`ago-console/src/i18n/`) before changing the production code - some of those tests will need their
  own expected value flipped, deliberately, not treated as breakage to work around.
- **`23-28`'s own reasoning was written for a narrower case** (a pre-session screen with genuinely no
  site to ever have one) - confirm this item's wider, structural change does not contradict anything
  `23-28` itself relied on staying English-shaped elsewhere, before assuming the two are simply the
  same fix applied twice.

## Done when

- [ ] The platform owner's own screens render in Russian with no further action, proven by the same
      walkthrough that found the gap.
- [ ] A tenant's own site with an explicit `Locale = "En"` still renders in English, unchanged -
      proven, not merely reasoned about, since this item touches the fallback every locale resolution
      in this console shares.
- [ ] Every test asserting the old English-by-default fallback is read and, where it was actually
      testing the fallback rather than an unrelated behaviour, updated to the new one.
