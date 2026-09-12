# 25-49 · Header left side: logo size and the product's real name

- **Stage**: 25
- **Status**: ready
- **Verified**: 2026-09-12 — both elements confirmed real in `ago-console/src/shell/AppShell.tsx`:
  `ago-shell__glyph` ("A") and `ago-shell__wordmark` ("Офис"), present in two shell variants
  (`AppShell.tsx` lines ~505/693) plus asserted by `consoleLocale.test.tsx`. No hidden dependency.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## Scope

- Enlarge the "А" logo square to match the menu-icon size used elsewhere in the header.
- Rename the header's own product label from "Офис" to "AGO Офис".

## Done when

- [ ] The logo square is the same size as a header menu icon.
- [ ] The header reads "AGO Офис", not "Офис".
