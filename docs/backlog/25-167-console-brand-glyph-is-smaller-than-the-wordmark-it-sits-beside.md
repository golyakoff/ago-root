# 25-167 · Console's brand glyph ("A" in the square) is smaller than the wordmark it sits beside

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-19, reported live by the author: the "A" inside the square brand mark next to
  "AGO Chat" in the console header reads much smaller than the "A" that opens "AGO Chat" itself, and
  should be comparable in height.

## What is actually true today

Confirmed directly in `ago-console/src/shell/shell.css`:

- `.ago-shell__glyph` (the square mark's own "A", `AppShell.tsx`'s `<span className="ago-shell__glyph">`)
  is sized with `font-size: var(--ago-text-sm)` - `0.8125rem` (13px), the same token used for field
  labels and table headers elsewhere in the console.
- `.ago-shell__wordmark` ("AGO Chat" itself) is sized with `font-size: var(--ago-text-display)` -
  `1.375rem` (22px).

So the two "A"s the author is comparing are 13px and 22px respectively - a real, measurable mismatch,
not a perception effect. The square's own size (`.ago-shell__glyph`: `width`/`height: 2.75rem`, matching
`.ago-shell__menu-button`'s own header-icon size, per `25-49`'s own comment) is not the problem; only the
glyph's own font-size inside that fixed square is undersized relative to the wordmark beside it.

Two render sites carry the identical markup and must both change together: `AppShell.tsx`'s main brand
block (~line 610) and its mobile-header twin (~line 970) - both already share one CSS class
(`.ago-shell__glyph`), so a single rule change covers both automatically; only worth naming so nobody
adds a second, wordmark-only fix and misses the mobile header.

## Scope

- Grow `.ago-shell__glyph`'s own `font-size` so the glyph's cap-height reads as comparable to the
  wordmark's own cap-height - likely close to `--ago-text-display` itself, though the exact token/value
  is an implementation call once seen rendered (a literal `--ago-text-display` might read as slightly
  too large once centered in a fixed 2.75rem square with its own padding - render both side by side
  before settling on a final value).
- Keep the square's own fixed `2.75rem` size unchanged - `25-49`'s own reasoning (matches the header's
  other icon, `.ago-shell__menu-button`) still holds; this item is about the glyph's own type size
  inside that square, not the square itself.

## Out of scope

- Any other console branding surface. The favicon gap for both the console ("офис") and `ago-landing`
  is filed separately (`25-168`) - a different kind of asset (a static icon file), not a CSS sizing fix.
- Redesigning the brand mark itself (shape, color, gradient) - `25-169` covers a gradient-fill question
  for the widget specifically; nothing here asks for the console's own square to become a gradient.

## Done when

- [ ] The glyph's own "A" and the wordmark's own "A" read as comparable in height, confirmed live in the
      console header (both the desktop and mobile render sites)
- [ ] No other element sized from `--ago-text-sm` is affected (confirm the token itself is not
      reused elsewhere in a way a value bump here would disturb, or scope the fix to the class only)
