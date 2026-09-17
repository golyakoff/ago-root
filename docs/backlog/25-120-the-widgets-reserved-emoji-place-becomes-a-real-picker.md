# 25-120 · The widget's reserved emoji place becomes a real picker

- **Stage**: 25
- **Depends on**: nothing (completes `23-61`'s own deferred scope)
- **Status**: done — `ago-widget#90`, deployed live (`ago-deploy` pin `87d949a`), smoke 42/42.
- **Found**: 2026-09-17, the author asking for an emoji picker in the widget - investigation found
  `23-61` had already reserved this exact spot and explicitly deferred it: "An emoji picker. This
  reserves its place; choosing and building one is a separate item."

## What is actually true today

`WidgetPanel`'s composer row already has a disabled, non-interactive placeholder
(`buildReservedComposerPlace("🙂", strings.emojiComingSoon)`, `src/ui/widget.ts`) sized and positioned
identically to the real `attachButton`/`saveButton` beside it (`.ago-composer-reserved` mirrors
`.ago-attach`/`.ago-save` in `src/ui/styles.ts`). `23-62` already completed the identical pattern for
the save-conversation place in the same row - this item is the same move for the other one.

## Scope

- Replace `emojiPlaceholder` with a real `<button>` (`.ago-emoji`, sized/positioned like `.ago-attach`/
  `.ago-save` - mirror their CSS exactly, the same way `23-62` mirrored `.ago-attach` for `.ago-save`),
  icon-only with a real `aria-label`, matching every other composer-row button's own shape.
- Clicking it opens a picker panel showing exactly these 40 emoji, in this order (a deliberately
  curated, business/support-chat-appropriate set - reactions, common gestures, and everyday symbols a
  visitor or operator would actually reach for, nothing obscure or culturally ambiguous):

  ```
  😀 😊 🙂 😉 😂 😍 🤔 😮 😢 😡 😴 🥳
  👍 👎 🙏 👏 🤝 💪 ✋ 👋
  ❤️ 💔 ⭐ 🔥 ✅ ❌ ⚠️ ❓
  🎉 🎁 📅 📞 📧 🕒 💰 🛒 📦 🚀 💡 📎
  ```

  A flat, static list - no search, no categories, no recently-used tracking, no skin-tone variants.
  This item is "the reserved place becomes real," not a full emoji-picker product; a richer picker is
  a later item if the fixed 40 turns out not to be enough.
- Clicking an emoji inserts it into `this.input` (the composer `<textarea>`) at the current cursor
  position (not always appended at the end - a visitor who moved the cursor to edit earlier text
  should get the emoji where they were), and returns focus to the input afterward so typing continues
  without a click. Closes the picker on insert.
- The picker is dismissible the way this codebase already dismisses an overlay (`WidgetPanel`'s own
  `role="dialog"` + `Escape`-to-close pattern is the closest existing precedent, `src/ui/widget.ts`) -
  `Escape` closes it, a click outside the picker (but not on the trigger button, which should toggle)
  closes it, and closing returns focus to the emoji button itself.
- Keyboard-operable as a real grid: arrow keys move between emoji, `Enter`/`Space` picks the focused
  one, `Tab` does not need to visit all 40 individually if a roving-tabindex or `role="grid"` pattern
  is used instead - pick a standard, accessible shape (ARIA's own grid or listbox pattern) rather than
  inventing one; state which you chose and why.
- i18n: a real `aria-label` for the trigger button (replacing `emojiComingSoon`'s own "(coming soon)"
  wording, which no longer applies) and an `aria-label` for the picker panel itself, in both `en.ts`
  and `ru.ts`, following this file's own existing string-naming convention.

## Where this is likely to go wrong

- **Do not build a second, differently-styled overlay mechanism.** Reuse the sizing/positioning this
  row's other buttons already establish and the dismiss pattern `WidgetPanel`'s own dialog already
  uses - a picker that looks or behaves differently from the rest of this widget's own chrome is a
  regression in consistency, not a new feature.
- **This widget ships inside a strict, CI-enforced gzip budget** (`ago-widget`'s own build - the
  console worker's own report for `25-119` names it: "well under the 45 KB budget"). Forty emoji as
  literal characters cost nothing meaningful; do **not** reach for an emoji-picker npm package (a
  common one bundles thousands of emoji, keyword search indexes, and skin-tone data far beyond this
  item's own fixed-40, no-search scope) - hand-build the flat grid.
- **Real accessibility, not just keyboard-reachable in principle** - this project's own widget
  accessibility bar is high (see `AttentionBanner`/`Tooltip`-equivalent rigor already in this
  codebase); a mouse-only picker or one that traps focus wrong is a real regression a screen-reader
  user would hit immediately.
- **Cursor-position insert, not append-only** - a visitor who clicked into the middle of what they
  already typed and expects the emoji to land there, not at the end, is the concrete case naming this
  requirement rather than leaving it to be discovered later.

## Done when

- [x] The reserved emoji place is a real, working button - `emojiComingSoon`'s "(coming soon)" wording
      is gone from both locales.
- [x] Clicking it opens a 40-emoji grid; clicking an emoji inserts it at the cursor and returns focus
      to the composer.
- [x] The picker is fully keyboard-operable (arrow-key grid navigation, `Enter`/`Space` to pick,
      `Escape` to close) and closes on an outside click, returning focus to the trigger button. `role=
      "grid"` with roving tabindex, per ARIA APG's own worked example for an emoji picker.
- [x] A real-browser (Playwright/`ux-gate`) test proves the picker actually renders, is keyboard-
      navigable, and an insert actually lands in the textarea - 16/16 `ux-gate` passed, both viewports.
- [x] The widget's own gzip budget check still passes - 36.4 KB gzipped (budget 45 KB).
