# 25-54 · Explanatory prose becomes tooltips across the Диалоги›Мои workspace

- **Stage**: 25
- **Status**: ready — **not yet verified against the real code** (docs/backlog/README.md)
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

## Done when

- [ ] None of the named paragraphs renders as permanent inline text in any of the three panels.
- [ ] Each is reachable via a (?) tooltip triggered from the control/section it explains, including
      the visitor panel's own header tooltip.
