# Android calendar-config screens (Мастера + Настройка/Календари) — design

Author-directed (2026-09-25): fill the two missing Android calendar-**configuration** screens as **single
screens**, reusing the app's existing screen chrome/type/weights (the `26-96` Услуги / `26-97` Часы
pattern), reached through the existing `⋮` config hub (`26-103`). **No backend gap, no migration** — pure
client build over live `Ago.Calendar.Api` endpoints the app already partly consumes.

## Reused building blocks (verbatim, not re-invented)
`LoadingBody`/`EmptyBody`/`RefusalBody`/`ActionErrorBanner`, `BookingDetailRow` (all in
`bookings/BookingsScreen.kt`); the four-arm `*UiState` (Loading/Loaded/NotConfigured/Failed); the
`BookingsQueueFailure`+`failureMessage()` adapter-classifies/UI-words split; `BookingActionResult` +
`BookingActionErrorUi`; the `ServiceEditForm` form-over-list idiom; the WorkingHours delete-confirm
`AlertDialog` and weekday `FilterChip` row; `SectionLabel`; `AgoTypography` roles; the Route/Screen(stateless
Body) split; the `di/AppModule.kt` `@Provides` adapter idiom; the `TenantConfigurationWireDto`
(`ignoreUnknownKeys`) + `classify(Exception)` + `ProblemDetailsWireDto` adapter shape. New ports go in
`core/domain`, Ktor adapters in `core/network` (dependency rule — a VM must not hold an `HttpClient`).

## Мастера (Masters) — one screen, worker dictionary CRUD
Live backend: `GET /console/workers`, `GET /workers/{id}`, `POST /workers`, `PUT /workers/{id}` (replace
semantics, incl. `IsActive`+`ServiceIds`), `DELETE /workers/{id}` (refused if ever booked — refusal carries
`detail`). Calendar picker + services checkboxes come from `GET /configuration` (`calendars[]`, `services[]`).
Layout mirrors Услуги: list of worker cards (displayName bold; services line; `error`-worded «Неактивен»),
add/edit form-over-list (Фамилия/Имя/Отчество/Отображаемое имя/Календарь `FilterChip`/Услуги checkboxes/
Активен), delete `AlertDialog` (keep row + show server `detail` on refusal). Add disabled with a note when no
calendar exists. Four-arm states; re-read after each write (no optimistic). Gate: `calendar:configure`.
**Folded-out future drill-downs (backend already exists):** worker schedule template
(`GET/PUT /workers/{id}/schedule`), Слоты (`GET /workers/{id}/slots`), Пересчёт (`recut/preview`+`recut`).

## Настройка / Календари (Setup) — one screen
Menu label **Настройка**; primary section **Календари**. Live backend: `GET /configuration`,
`PUT /configuration/allowed-origins`, `POST /calendars` (`Name`,`TimeZone`,`Publish`), `PUT /calendars/{id}`
(`Name`,`Publish` — **timezone create-only**, no `deleteCalendar` by design). One scrolling column,
`SectionLabel` per section: **Встраивание/Разрешённые источники** (read-only embed snippet — placeholder per
console §14; multi-line origins field → save) and **Календари** (list card = name + `zone · published`;
edit name+published; create form Название/Часовой пояс/Опубликован). Working-hours is NOT duplicated here (it
is the existing Часы screen — deliberate deviation from the console's Setup). Gate: `calendar:configure`.

## Config hub (26-103) — now four ⋮ entries
The existing `⋮ BookingsConfigMenu` `DropdownMenu` gains `Calendars` and `Masters` members
(`BookingsTab` enum, `visibleBookingsConfigMenuEntries` + two new `calendar:configure` booleans threaded
through `AppShellScreen`/`BookingsRoute`, `bookingsTabLabel`, the `when(selectedTab)` bodies). Order
(fill/readiness): **Календари (Настройка) · Мастера · Услуги · Часы**. Hide-not-disable: the whole ⋮ vanishes
when the operator holds none of the four. The full «Конфигурация записей» readiness-chain hub
(`GET /booking-readiness`) stays a distinct larger future item — see 26-143.

## Slices (each one promise that lands green; no migration)
- **26-139 [android core]** Masters data client — `WorkersApi` port + models + `KtorWorkersApi`. `core/**` only.
- **26-140 [android app]** Masters screen — Body/UiState/VM + hub wiring + DI + strings. Depends 26-139.
- **26-141 [android core]** Calendar-setup data client — `CalendarSetupApi` + `KtorCalendarSetupApi`. `core/**`.
- **26-142 [android app]** Настройка/Календари screen. Depends 26-141.
- Parallelism: **26-139 ∥ 26-141** (disjoint `core/` files). **26-140 and 26-142 serialize** (both edit
  `BookingsTab.kt`/`BookingsScreen.kt`/`AppShellScreen.kt`/`AppModule.kt`/both `strings.xml`). PRs one at a
  time.

## Author decisions (small)
1. **Calendar timezone on create** — free-text default `Europe/Moscow` (minimal) vs localized dropdown
   (console has it since 25-16). Rec: free-text now, dropdown later. (Edit never changes tz.)
2. **`(нужна правка)` backfill badge** on worker rows — include vs drop as console-specific noise. Rec: drop
   unless the demo tenant has backfilled workers.

## Deferred (named, not papered over)
Full readiness-chain hub «Может ли клиент записаться?» (26-143); Masters drill-downs (schedule/slots/recut).
