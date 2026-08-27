# The site-configuration screens speak the tenant's chosen language

- **Stage**: 11
- **Status**: ready
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

- [ ] All three screens render in Russian for a `ru` site's `site:configure` operator - DOM-tested.
- [ ] The English-default regression case.
- [ ] This item's own body lists every string it found and translated.

## Open questions

None yet - inherits `11-11`'s settled design call.
