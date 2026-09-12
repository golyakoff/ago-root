# 25-54 · Explanatory prose becomes tooltips across the Диалоги›Мои workspace

- **Stage**: 25
- **Status**: done — `ago-console#210`
- **Verified**: 2026-09-12 — every named string confirmed real in `ago-console/src/i18n/ru.ts`:
  `queueAssignedNote`, `queueWaitingNotePrefix`, `conversationWaitingForHub`, the delivery-status
  note (line ~109), `notesVisitorCannotSeeNote`, `channelIdentitiesSectionTitle`'s own explanation,
  `outcomeNotAVerifiedSaleNote`, and the visitor-panel header text (line ~145).
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

The three-panel operator workspace (Диалоги›Мои: conversation list, active dialog, visitor detail)
carries several paragraphs of standing explanatory prose that only matter once, before an operator
has oriented themselves, and permanently eat screen space afterward.

## Scope

Move each of the following into a (?) tooltip-icon, hover/focus-triggered, next to the element it
explains — the visible label/control stays, the paragraph explaining it does not render inline:

- Панель «Диалоги»: "В реальном времени — новое назначение появляется без обновления страницы." и
  "Новые диалоги назначаются автоматически — нажмите, чтобы забрать диалог самостоятельно.
  Обновляется каждые 15 секунд."
- Панель «Диалог»: "Ожидание сервера оператора, пока диалог не сможет загрузиться или отправить
  сообщение." и "Статус доставки показывается только для сообщений, отправленных через подключённый
  канал (SMS, Telegram и т. п.). Сообщения в чате на сайте статус доставки не показывают."
- Панель «Посетитель»: the "Посетитель их никогда не видит" note on Заметки; the «Связанные каналы»
  section's own explanation (what the generated pairing code is for); the «Результат» field's own
  "Указано оператором — не продажа, подтверждённая AGO Chat независимо."; and the panel's own header
  text "Это всё, что платформа сегодня знает о посетителе. Текущая страница и источник перехода пока
  не собираются. Предыдущие диалоги показаны ниже, если этот посетитель был распознан в канале (MAX,
  Telegram или SMS)." — as a tooltip on the panel's own header/title, not inline body text.

## Where this is likely to go wrong

- **Text content does not change**, only where it renders — this is a placement item, not a copy
  rewrite. If a tooltip's own source text needs Material Symbols icon work (`25-46`) for the (?)
  trigger itself, use that icon set, not a new one.
- **This item does not resolve what «Связанные каналы»/«Сгенерировать код» or «Результат» mean** —
  those mechanisms already exist and work (see this item's own investigation notes in the session
  that filed it); this item only relocates their existing explanatory copy into a tooltip.

## Outcome

Seven of the eight named strings were real and moved into a new `Tooltip` component (`ago-root#907`
is the companion `adr/0030` fifth amendment — the twelfth component, exactly the trigger that ADR's
own Alternatives section named). Hand-rolled, not a headless library — hover + keyboard focus +
click-to-focus for touch, Escape closes without moving focus, `role="tooltip"` + `aria-describedby`.
The eighth (an explanation near `ChannelIdentitiesPanel`'s "Связанные каналы") does not exist in the
code — corrected here rather than silently assumed: the item's own Scope above named eight strings,
seven are real, and nothing was invented to fill the eighth.

## Done when

- [x] None of the named paragraphs renders as permanent inline text in any of the three panels.
- [x] Each is reachable via a (?) tooltip triggered from the control/section it explains, including
      the visitor panel's own header tooltip.
