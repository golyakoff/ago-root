# 25-205 · Channel-switcher row text reads too light in the channel's brand colour

- **Stage**: 25
- **Status**: done — `ago-widget#126`
- **Found**: 2026-09-21, the author, live in the browser while reviewing `25-204`'s own
  `AboveComposer` hover banner: "тексты выглядят слишком светло рядом со значками... не нужно их
  красить в цвет иконки канала" (the texts look too light next to the icons - no need to colour them
  in the channel icon's colour).

## What is actually true today, confirmed against real code before this was filed

`buildChannelSwitcherRow` (`ago-widget/src/ui/widget.ts`) sets `row.style.color =
CHANNEL_BRAND_COLORS[link.kind] ?? CHANNEL_FALLBACK_COLOR` on the row's own `<a>` element. That
function's own doc comment already states the current, narrower job this line does: since `25-172`,
the four real brand icons (Telegram/WhatsApp/Vk/Max) carry their own explicit `fill` values, never
`currentColor` - so this inline `color` no longer tints the icon at all, only the label `<span>` next
to it, via `.ago-channel-switcher-row { color: inherit }` (`ui/styles.css`). The author's own
complaint is exactly this: a brand colour picked to read well as a small icon accent (e.g. Telegram's
`#0088CC`) is a pale, low-contrast choice for body-sized label text against `.ago-channel-switcher-
banner`'s white background.

This is not new to `25-204` - `buildChannelSwitcherRow` is shared verbatim by every placement that
shows text rows: the new `AboveComposer` banner, and the mobile touch routing sheet (`25-197`). Both
inherit the same washed-out text the moment either renders a real channel link.

## Scope

- Stop tinting the row's **label text** with the per-channel brand colour. The label should read in
  the row's own ordinary text colour - the identical `color: inherit` neutral every other row in this
  file already falls back to when it carries no inline colour of its own (the retired card's old
  "stay here" row, and the current "Онлайн чат" row, both already read this way).
- **Do not touch icon colouring.** The four real brand icons already carry their own explicit fills,
  untouched by this item. Confirm live (screenshot or `getComputedStyle`) that removing the label's
  inline colour leaves every brand icon's own colour exactly as it is today.
- Decide what happens to the *unrecognised-kind fallback icon* (`createSvgIcon(CHANNEL_FALLBACK_ICON_PATH)`,
  which does use `fill: currentColor`, unlike the four real brand icons) once the inline `color` is
  gone - state the answer rather than leaving it to be discovered: it will render in the row's own
  neutral text colour once this item lands, which is a reasonable fallback (there is no real brand
  colour to preserve for an unrecognised channel), but say so explicitly in the change.
- `CHANNEL_BRAND_COLORS`/`CHANNEL_FALLBACK_COLOR` themselves may become dead code once nothing reads
  them for text - if so, remove them rather than leaving an unused map behind; if anything else still
  reads them (check before assuming), say what and why they stay.

## Out of scope

- `BelowLauncher`'s own icon-only circles (`buildChannelSwitcherLauncherIcon`) - a different function,
  never took this inline text colour in the first place (it has no text label at all).
- The "Онлайн чат"/"Отмена"/open-chat rows - already colour-neutral (or `--ago-accent`, a deliberate,
  different decision from `25-204`), untouched by this item.

## Done when

- [x] A connected channel's row (Telegram, WhatsApp, Vk, Max) shows its label in the row's ordinary
      text colour, not the channel's brand colour.
- [x] Every brand icon's own colour is provably unchanged (a live check, not assumed from reading the
      code).
- [x] The unrecognised-kind fallback icon's new colour is stated explicitly, not left to be noticed.
- [x] Existing tests asserting the old inline colour are updated to the new expectation, not deleted
      to make them pass.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.

## Outcome

Landed as `ago-widget#126`. `row.style.color` (the per-kind brand tint) is removed from
`buildChannelSwitcherRow` entirely; the label now falls back to `.ago-channel-switcher-row`'s own
`color: inherit`. `CHANNEL_BRAND_COLORS`/`CHANNEL_FALLBACK_COLOR` deleted outright - that line was
their only reader. The unrecognised-kind fallback icon (`createSvgIcon`, `fill: currentColor`, unlike
the four real brand icons which carry explicit fills) now inherits the row's neutral text colour
instead of the removed fallback grey, named explicitly in the new doc comment rather than left
implicit. Fixes both renderers that share this row builder: the `AboveComposer` banner (`25-204`) and
the mobile touch routing sheet (`25-197`).

Verified independently, beyond the worker's own report:
- `npm run typecheck`/`lint` - clean.
- `npm test` - 43 test files, 525 tests passed.
- `npm run build` - 38.6 KB gzipped (budget 46 KB).
- `npm run ux-gate` - 16/16 Playwright tests passed.
- Reviewed the diff directly: the doc-comment updates on `buildChannelSwitcherRow` and
  `buildChannelSwitcherLauncherIcon`, and the CSS comment, all correctly describe the new behaviour
  rather than the removed one. `buildChannelSwitcherLauncherIcon`'s own fallback-circle background
  (`.ago-channel-switcher-launcher-icon--fallback`) is a separate, pre-existing CSS literal, confirmed
  untouched by this change.
