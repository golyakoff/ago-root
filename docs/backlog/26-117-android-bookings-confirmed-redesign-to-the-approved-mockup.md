# 26-117 · [android] Redraw Записи → «Утверждены» to the approved mockup (names, month labels, row icons, booking-detail sheet)

- **Stage**: 26 — implementation of `26-112` (design: `docs/design/26-112-bookings-names-contacts-navigation.md`;
  approved mockup lives in the Android mockup Artifact, «Утверждены» slot + «Детальная запись» slot).
- **Status**: done — merged as `ago-android#111`; Записи→Утверждены redrawn to the approved mockup (710 tests). Two follow-ups filed: `26-121` (calendar SMS/Источник fields, rendered «—» until then) and the dialog-link nav awaits `origin_conversation_id` (26-112 backend).
  is a hard requirement, not a suggestion. Do not "cut corners" on any of them.**
- **Depends on**: nothing for the visual + phone reveal (name/phone are already on the confirmed-booking
  payload — `customerDisplayName`, `phone`, `masked`). The chat→dialog navigation depends on the
  booking↔conversation link (`origin_conversation_id`), a separate 26-112 backend ticket — see "Dialog link".

## Why

The shipped «Утверждены» list is nameless (shows the emoji-pair handle + hex `shortId`), has no month
context on the day strip, no way to see the contact from a row, and no booking detail. The author redesigned
it. This ticket makes the Android screen match the approved mockup exactly.

## Hard requirements — the list (Записи → «Утверждены»)

1. **The client line is the NAME.** Show `customerDisplayName` as the row's prominent line; service +
   duration go on the muted sub-line beneath it (e.g. «Стрижка · 60 мин»). Time stays on the left.
2. **Fallback when there is no name: the masked phone + «Без имени» — NEVER the hex `shortId`.** The
   `7c4e18f0`-style code must not appear as a client identity anywhere on this screen. (Populating names at
   booking time is a separate backend task; this screen just must never show the code as the name.)
3. **Grouping by master and the day strip stay** (section header «<Мастер> · N записи», horizontal day
   strip with a selected day and dots on days that have bookings).
4. **Month + year under the day cards, INSIDE the same horizontally-scrolling container as the days** so
   they scroll together with the days (not a separate fixed row).
   - One label per month shown, each carrying **its own year** («Сентябрь 2026» / «Октябрь 2026»).
   - **No «|» divider** between months.
   - Each label sits under its own day cards; a label too narrow for the full name **ellipsizes** («Сен… /
     Октябрь 2026»).
   - **Same muted font, size and weight as the service/duration sub-labels** (`--ink-soft`-equivalent,
     regular weight) — do NOT invent a new colour, size, boldness or a special "month" style.
   - **No visible scrollbar** — the area just scrolls.
5. **Two Material icons per row, always both, left→right: chat then phone.**
   - Chat = Material Symbols `chat_bubble` (LEFT). Phone = Material Symbols `call` (RIGHT).
   - Both are always present on every row (a phone is mandatory on every booking).
   - Phone icon → the contact's phone (reveal, see detail sheet). Chat icon → the originating dialog (see
     "Dialog link" below).

## Hard requirements — the booking-detail sheet (row tap → detail)

6. Tapping a row opens the booking-detail (a bottom sheet over the list).
7. **Header:** the client name (prominent); then **one line with two containers — date on the LEFT, time on
   the RIGHT, and NO dot/separator between them** (e.g. «Вторник, 29 сентября 2026»  …  «10:00–11:00»). The
   date carries the year.
8. **«Мастер» is its own row**, like «Услуга» (rows: Услуга / Мастер / Телефон / Подтверждён по SMS /
   Источник).
9. **Телефон row: masked value + «Показать»** — reuse the existing audited reveal (`26-53`,
   surface distinguishes bookings), do not build a new reveal.
10. **«Источник» is plain text, no styled pill/label** — «Виджет на сайте», «Telegram», «Макс», etc.
11. Actions: **«Перейти к диалогу»** (primary) and **«Закрыть»** (secondary).

## Dialog link (chat icon + «Перейти к диалогу»)

- The link target is the **single conversation the booking was created in** (its `origin_conversation_id`),
  never "the last of several"; a contact's other dialogs are a separate surface (26-111's «Прошлые диалоги»).
- `origin_conversation_id` is a backend GAP (26-112 design GAP-C) — a separate ticket adds it. **In this
  ticket:** build both icons and the «Перейти к диалогу» affordance per the mockup, and wire the navigation
  to that field; when the field is not yet present on the payload, the navigation is a no-op/disabled but the
  icon and layout still render exactly as the mockup shows (do NOT drop the icon — the author requires both
  icons always). Leave a clear TODO referencing the backend ticket. Do not invent a client-side link.

## Out of scope

- Collecting/requiring a name at booking time (separate 26-112 backend ticket).
- The `origin_conversation_id` / `result_booking_id` backend link (separate 26-112 backend tickets).
- «Ожидают» / «Клиенты» / «Услуги» / «Часы» screens.

## Done when

- [x] The «Утверждены» list matches the approved mockup: name-prominent rows, masked-phone/«Без имени»
      fallback (never the hex), month+year labels inside the scrolling day container in the muted sub-label
      style (no divider, year each, ellipsis, no scrollbar), and chat(left)+phone(right) Material icons on
      every row.
- [x] Row tap opens the booking-detail sheet exactly per the mockup: name header; date-left/time-right with
      no dot; «Мастер» own row; «Телефон» with «Показать» reusing the existing reveal; «Источник» plain text;
      «Перейти к диалогу» + «Закрыть».
- [x] The chat icon / «Перейти к диалогу» navigates to the booking's origin dialog when the field is present,
      renders per mockup when it is not, with a TODO to the backend link ticket. Icons are always both.
- [x] Strings are resources (ru + en). `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin`
      green; tests for name-vs-fallback and the month-label boundary/ellipsis; counts reported.
