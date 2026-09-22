# 25-220 · The widget's built-in default greeting becomes "Напишите нам..."

- **Stage**: 25
- **Status**: done — `ago-widget#132`, `ago-console#270`
- **Found**: 2026-09-22. The author asked whether the panel header's text ("Чем мы могли бы вам
  помочь?") has a control, or is a fixed default. **It already has a control** — Console → "Виджет на
  сайте" → the "Кнопка запуска" panel's own "Заголовок панели" field (`25-210`) — the author had looked
  at the "Каналы" panel further down the same page, which controls the channel-switcher's own settings,
  not the panel's greeting. Left blank (the common case), the widget falls back to its own built-in
  default, shown as that field's placeholder — this item changes what that default reads, not whether
  a control exists.

## Scope

- `ago-widget/src/i18n/ru.ts`'s `chatWithUs` — the real fallback the widget renders when a site has no
  configured `panelTitle` — becomes `"Напишите нам..."`.
- `ago-console/src/i18n/ru.ts`'s `widgetPanelTitlePlaceholder` — the same text, shown as the field's
  placeholder so an operator sees what "left blank" actually renders — becomes the identical string,
  keeping the two surfaces in agreement (`ui/widget.ts`'s own doc comment on why the channel-switcher
  banner reads `this.title.textContent` rather than re-deriving it is the same "never let two surfaces
  show different words" reasoning this item's two-file change preserves).
- Update the two `ago-widget` tests that asserted the old Russian default text
  (`widget.test.ts`, `locale.test.ts`).
- The English default (`"How can we help you?"`) is untouched — not asked for, and not an equivalent
  translation of the new Russian text.

## Out of scope

- Any other locale's default.
- The field's own label, description, or character-counter behaviour (`25-210`) — unrelated to what
  text renders as the default.

## Done when

- [x] `chatWithUs` (ago-widget) and `widgetPanelTitlePlaceholder` (ago-console), Russian locale only,
      both read `"Напишите нам..."`.
- [x] Both repositories' full test suites green — 566/566 (`ago-widget`), 1672/1672 (`ago-console`).
