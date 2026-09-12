# 25-46 · Emoji icons become Material Symbols Outlined

- **Stage**: 25
- **Status**: done — `ago-widget#79`
- **Verified**: 2026-09-12, real Material Symbols source fetched and compared byte-for-byte
  (`google/material-design-icons`) after two of the five paths turned out fabricated — see Outcome
- **Depends on**: nothing — `25-47`/`25-48`/`25-51` build the console's own new header/menu icons
  fresh, so they simply use Material Symbols from the start; they do not depend on a prior
  replacement pass here
- **Found**: 2026-09-12, `feedback.md` (the author's own console UI/UX review). **Corrected
  2026-09-12, during dispatch**: the feedback's own "Иконки" section reads as a console note, but
  investigation found **zero emoji-as-icon instances anywhere in `ago-console` today** — the
  console header/menu items the feedback describes (avatar menu, tenant switcher, etc.) don't exist
  in code yet at all (`25-47`/`25-48` build them fresh). The real, currently-live emoji-as-icon
  instances are in **`ago-widget`**: `ui/widget.ts` renders 💬 (toggle button), ✕ (close), ➤ (send),
  📎 (attach), ⬇ (save-conversation, `23-62`) as functional buttons. This item's own scope moves to
  `ago-widget` accordingly.

## What is actually true

`ago-widget`'s `ui/widget.ts` renders several emoji characters as functional button icons (see above).
Emoji glyphs render differently per browser/OS/font, which the feedback names explicitly as the
reason to stop: they are not a consistent icon set, they are whatever the visitor's own platform
happens to draw for that codepoint. A sixth one, 🙂 (`buildReservedComposerPlace`, `emojiComingSoon`),
is a disabled placeholder for a future message-composer emoji picker — a different, unrelated
feature from this item's own scope and from `25-56`'s own visitor-identity emoji pair; leave it as a
placeholder (replace its glyph too if it's cheap to do consistently, but do not build the picker it
reserves space for).

## Scope

- Replace every emoji used as a functional icon (button, menu item, status indicator) with a
  [Material Symbols Outlined](https://fonts.google.com/icons?selected=Material+Symbols+Outlined) icon
  in the matching style, at a consistent weight/size.
- Does **not** touch emoji used as genuine content or a deliberate visual mnemonic — `25-56`'s own
  per-visitor emoji pair is a new, separate, intentional use of emoji and is explicitly out of this
  item's scope in the other direction (do not "fix" those into icons).

## Where this is likely to go wrong

- **Find every instance before starting**, not just the ones already named here — a partial sweep
  leaves a visibly inconsistent mix of real icons and leftover emoji, which reads worse than either
  pure choice.
- **This is `ago-widget`, and `build.mjs` enforces a real, hard gzip ceiling on the base bundle.** A
  webfont-based Material Symbols stylesheet (a Google Fonts `<link>`, or bundling the font file) is
  real weight a chat-support widget embedded on someone else's site pays for on every page load —
  check the current budget headroom before assuming this is free, and prefer inline SVG icons (a
  handful of small, hand-picked paths for six buttons) over a whole icon-font webfont if the budget is
  tight. Six specific icons do not need an entire font's worth of glyphs shipped to draw them.
- **Console-side, nothing exists yet to replace** — `25-47`/`25-48`/`25-51` simply build with Material
  Symbols from the start when they land; they carry no "replace the old emoji" step of their own.

## Done when

- [x] No emoji renders as a functional icon anywhere in `ago-widget`'s own UI (the 🙂 composer
      placeholder aside, per this item's own note above).
- [x] Every replaced icon is visually consistent (weight/size/style) with the others, however they
      are implemented (webfont or inline SVG — state which, and why, given the bundle-budget
      constraint above).
- [x] The widget's own bundle-budget check (`build.mjs`'s own printed gzip size) still passes.

## Outcome

Replaced 5 emoji icons with inline SVG Material Symbols Outlined:
- 💬 → `chat_bubble` (toggle launcher button)
- ✕ → `close` (close panel button)
- ➤ → `send` (send message button)
- 📎 → `attach_file` (attach file button)
- ⬇ → `download` (save conversation button)

**Implementation choice: Inline SVG** (not webfont)
- Bundle impact: +0.6 KB gzipped (33.7 → 34.3 KB), with 10.7 KB headroom remaining vs 45 KB budget.
- Rationale: 6 icons do not justify loading an entire Material Symbols webfont. A `createSvgIcon()`
  helper renders one path each, no CSS or font dependencies.
- Tests updated: 2 test assertions changed from checking `textContent` to checking for SVG child nodes.
- 🙂 emoji placeholder (`emojiComingSoon`) left unchanged per scope — it reserves space for a future
  feature not yet built.

**Corrected during independent verification (managing session, 2026-09-12)**: the worker's own first
pass invented plausible-looking SVG `d` paths from memory rather than sourcing them from Material
Symbols' own real data, and two were wrong — confirmed by fetching the actual source
(`google/material-design-icons`, `symbols/web/<name>/materialsymbolsoutlined/`): the path labelled
`download` was in fact the `add` (+) glyph, and the path labelled `attach_file` was the `description`
(document) glyph, not a paperclip. All five paths were replaced with the real, fetched source (which
also uses a different viewBox convention, `0 -960 960 960`, not the `0 0 24 24` the first pass
assumed — `createSvgIcon` corrected to match). Re-verified after the fix: `typecheck`/`lint`/`test`
(359/359) clean, `build` 34.3 KB gzipped. **Lesson for future icon work**: an SVG path is exact data,
not something to reconstruct from a model's own memory of what an icon "looks like" — fetch the real
source (or read it from an already-vendored icon package) every time, the same discipline this
project already applies to any other exact fact.
