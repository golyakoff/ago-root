# 25-127 · The emoji trigger draws an emoji instead of an icon

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: 2026-09-17. `25-120`'s own emoji picker trigger button
  (`ui/widget.ts:568`, `this.emojiButton.textContent = "🙂"`) renders its own *trigger* as a literal
  emoji character - inconsistent with every other composer-row control (`.ago-attach`, `.ago-save`),
  which already render a proper Material Symbols Outlined SVG via the existing `createSvgIcon(d)`
  helper (`ui/widget.ts:144`, five existing call sites).

## Scope

- Replace `this.emojiButton.textContent = "🙂"` with `this.emojiButton.appendChild(createSvgIcon(d))`,
  using a real Material Symbols Outlined "mood"/"sentiment_satisfied" glyph path (Google's own
  `material-design-icons` source, `-960 0 960 960` viewBox convention - `createSvgIcon`'s own doc
  comment states the exact convention every existing call site already follows; find the correct path
  data from that same source, do not approximate one by hand).
- The 40 literal emoji characters inside the picker's own grid cells (`buildEmojiPicker`) are
  unaffected - those are the actual insertable content, not a UI icon, and stay real emoji glyphs.
- `strings.insertEmoji` (the trigger's `aria-label`) is unaffected - only the visible glyph changes,
  not the accessible name.

## Where this is likely to go wrong

- **Do not touch the 40-glyph grid.** This item is about the trigger button's own icon only.
- **Match the existing five `createSvgIcon` call sites' own convention exactly** - same viewBox, same
  `fill: currentColor`, no stroke - so the new icon inherits color/sizing the identical way
  `.ago-attach`/`.ago-save` already do, with no new CSS needed.

## Done when

- [ ] The emoji-picker trigger button renders a real SVG icon, not a literal emoji character.
- [ ] It visually matches the weight/sizing of `.ago-attach`/`.ago-save` in both light rendering and at
      a glance in `ux-gate`'s own screenshots.
- [ ] The picker's own 40-emoji grid, and the trigger's `aria-label`, are unchanged.
