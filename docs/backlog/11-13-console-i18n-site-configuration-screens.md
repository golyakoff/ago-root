# The site-configuration screens speak the tenant's chosen language

- **Stage**: 11
- **Status**: done — merged `ago-console#51` (2026-08-28). Found already shipped the same day while
  briefing a background worker to build it; reconciled here rather than re-implementing (see 11-11's
  own Status line for the same gap and why it happened)
- **Depends on**: `11-11-console-i18n-foundation-and-shell.md` (the string-table mechanism and locale
  resolution this item reuses without rebuilding).

## Why this exists

The last group of `site:configure`-gated screens: `AdminConversationsPage` (`/admin`),
`WidgetConfigPage` (`/settings/widget`), `OfflineAutoReplyPage` (`/settings/auto-reply`). Lower
traffic than `11-12`'s workspace, still real - an operator with `site:configure` sees these regularly,
and a Russian tenant's admin screen staying English after the rest of the console does not would be
exactly the half-finished feature `11-10`'s own scope discipline was written to avoid producing.

## Scope

- Enumerate every user-facing string across the three screens by reading the source.
- Extend `11-11`'s string table.
- `WidgetConfigPage`'s own `LOCALE_LABELS` (Russian/English, the locale picker's own option names) is
  explicitly **not** touched by this item - `4-06`(console) already fixed those to endonyms, and an
  endonym is correct in every UI language by construction, nothing to translate.

## Out of scope

- `OwnerSitesPage`, `/onboarding`, `/signup` - no site to take a language from, per `11-11`'s settled
  design call.

## Done when

- [x] All three screens render in Russian for a `ru` site's `site:configure` operator - DOM-tested
      (`siteConfigLocale.test.tsx`).
- [x] The English-default regression case.
- [ ] This item's own body lists every string it found and translated — **not carried through**, the
      same gap `11-12`'s own reconciliation names: the merged PR (`ago-console#51`) states the full list
      ("68 new string fields") was meant to land in this exact file, and the docs-side half of that PR
      was never opened. The list exists in `ago-console#51`'s own diff (`src/i18n/en.ts`/`ru.ts`), not
      here. Left unchecked and named, not backfilled.

## Open questions

None yet - inherits `11-11`'s settled design call.
