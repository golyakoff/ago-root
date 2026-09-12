# 25-48 · An Appearance settings page picks the theme

- **Stage**: 25
- **Status**: ready
- **Verified**: 2026-09-12 — **the item's own premise was wrong: `ago-console` already ships a fully
  working System/Light/Dark picker.** `design/ThemeToggle.tsx` (a `<Select>`, rendered by `AppShell`
  next to Sign out) backed by `design/theme.ts`'s `useTheme()` (`localStorage`, key
  `ago-console:theme`) and a complete dark-theme token set in `design/tokens.css`
  (`prefers-color-scheme` + `data-theme` override, already covering "System" following the OS). Every
  one of this item's original Done-when boxes was already true — only the *placement* (inline header
  control, not a standalone page) differed from what this item asked for.
  **The author's own call, once shown this, 2026-09-12**: the header is the right place for a
  rarely-reached toggle *today*, but more appearance settings are coming later, so build the
  standalone page now rather than revisiting placement twice — move the existing control onto it,
  don't duplicate it.
- **Depends on**: nothing to build against — `25-47`'s own user menu links here, but this page must
  exist on its own regardless of when that lands
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

The picker itself is done and correct. What is missing is only its home: a dedicated
`/settings/appearance`-style page, so future appearance settings have a place from the start instead
of a second placement migration later.

## Scope

- A new, standalone page (own route) that becomes the picker's real home: **System**, **Light**,
  **Dark**, using the *existing* `useTheme()`/`ThemeToggle` machinery — do not rebuild the
  persistence, the DOM-attribute application, or the dark token set, all of which already work.
- Remove `ThemeToggle` from the header (`AppShell.tsx`) once the page renders the same control — this
  is a move, not an addition; the app must not end up with the picker in two places at once.
- Nothing else lives on this page yet, matching the original feedback's own words — the "more visual
  settings later" the author named is future scope, not this item's.

## Where this is likely to go wrong

- **Do not treat this as "build a theme picker."** The picker, its persistence and the dark palette
  are shipped and correct; the only real work is relocating the existing control and its host page's
  own scaffolding (route, nav entry if any, page chrome).
- **Removing it from the header must not orphan the underlying `useTheme()` hook or its storage key**
  — those keep working exactly as they do today, only the rendering call site moves.

## Done when

- [ ] `/settings/appearance` (or the console's own equivalent route convention) offers
      System/Light/Dark via the existing `useTheme()`/`ThemeToggle` machinery, unchanged in substance.
- [ ] The header no longer renders `ThemeToggle` — the page is now the only place the control lives.
- [ ] The choice still persists across a reload for the same operator, and "System" still follows the
      OS/browser preference — both already proven by the existing implementation, just re-confirmed
      after the move.
