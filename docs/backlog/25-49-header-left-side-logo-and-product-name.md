# 25-49 · Header left side: logo size and the product's real name

- **Stage**: 25
- **Status**: done — `ago-console#197`
- **Verified**: 2026-09-12 — both elements confirmed real in `ago-console/src/shell/AppShell.tsx`:
  `ago-shell__glyph` ("A") and `ago-shell__wordmark` ("Офис"), present in two shell variants
  (`AppShell.tsx` lines ~505/693) plus asserted by `consoleLocale.test.tsx`. No hidden dependency.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## Scope

- Enlarge the "А" logo square to match the menu-icon size used elsewhere in the header.
- Rename the header's own product label from "Офис" to "AGO Офис".

## Done when

- [x] The logo square is the same size as a header menu icon.
- [x] The header reads "AGO Офис", not "Офис".

## Outcome

`ago-console/src/shell/shell.css`: `.ago-shell__glyph` grew from `2rem` to `2.75rem` square, matching
`.ago-shell__menu-button` - the header's own hamburger button, the only other square in that row and
therefore the "header menu icon" the item means. `ago-console/src/shell/AppShell.tsx`: both brand
blocks (`AppShell`'s header row and `CenteredShell`'s) now render `AGO Офис` instead of `Офис`, with
their doc comments updated to match. `src/i18n/consoleLocale.test.tsx`'s two `.ago-shell__wordmark`
assertions updated to `"AGO Офис"`. `typecheck`, `lint`, `test` (111 files / 1174 tests) and `build`
all green on branch `fix/25-49-header-left-side-logo-and-product-name`.
