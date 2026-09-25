# 26-142 · [android app] Настройка/Календари screen

- **Stage**: 26 — Android calendar-config screen. Design:
  `docs/design/26-139-android-calendar-config-screens.md`. **Depends on 26-141** (data client).
- **Status**: ready — queued behind 26-141.

## One promise
A single **Настройка** screen (menu label Настройка; primary section Календари) — embed/allowed-origins +
calendars list/create/edit — reachable from the `⋮` hub, reusing the app's screen chrome.

## Scope
- `bookings/CalendarSetupBody.kt` + `CalendarSetupUiState.kt` + `CalendarSetupViewModel.kt`; one scrolling
  column, `SectionLabel` per section: Встраивание/Разрешённые источники (read-only embed snippet placeholder +
  multi-line origins field → save) and Календари (cards: name + `zone · published`, edit name+published;
  create form Название / Часовой пояс / Опубликован). Working-hours NOT duplicated (it is the Часы screen).
- **Timezone on create = localized dropdown** (author-decided) — source a localized IANA zone list mirroring
  ago-console `25-16` (prefer a bundled list over a new endpoint). Edit never changes tz.
- Wire into the `⋮` hub: `BookingsTab.Calendars`, `showSetupSegment` (`calendar:configure`) threaded through
  the same shared files; DI provider; strings both languages.
- **Serializes with 26-140** (shared hub/nav/DI/strings files); land after 26-140, rebase on it.

## Done when
- [ ] Настройка screen: origins save + calendar create (localized tz dropdown)/edit; gated `calendar:configure`;
      appears in the ⋮ hub; gating asserted in a test; `ktlintCheck lint test :app:compileDebugAndroidTestKotlin`
      green; strings both languages.
