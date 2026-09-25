# 26-140 · [android app] Мастера screen

- **Stage**: 26 — Android calendar-config screen. Design:
  `docs/design/26-139-android-calendar-config-screens.md`. **Depends on 26-139** (data client).
- **Status**: ready — queued behind 26-139.

## One promise
A single **Мастера** screen — worker dictionary CRUD — in the app, reachable from the `⋮` config hub,
reusing the Услуги (26-96) screen pattern.

## Scope
- `bookings/MastersBody.kt` + `MastersUiState.kt` (four-arm) + `MastersViewModel.kt`; list of worker cards
  (displayName bold; services line; `error`-worded «Неактивен»), add/edit form-over-list (name parts,
  Отображаемое имя, Календарь `FilterChip`, Услуги checkboxes, Активен), delete `AlertDialog` (keep row +
  show server `detail` on refusal), re-read after each write (no optimistic). **No `(нужна правка)` badge**
  (author-decided drop). Add disabled with a note when no calendar exists.
- Wire into the `⋮` hub: `BookingsTab.Masters`, `showMastersSegment` (`calendar:configure`) threaded through
  `AppShellScreen`/`BookingsRoute`, `visibleBookingsConfigMenuEntries`, `bookingsTabLabel`; DI provider;
  strings both languages. Menu order: Календари · Мастера · Услуги · Часы.
- **Serializes with 26-142** (both edit `BookingsTab.kt`/`BookingsScreen.kt`/`AppShellScreen.kt`/`AppModule.kt`/
  both `strings.xml`).

## Done when
- [ ] Мастера screen full CRUD, gated `calendar:configure`, appears in the ⋮ hub; a test asserts the gating;
      `ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green; strings in both languages.
