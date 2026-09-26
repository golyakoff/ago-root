# 26-154 · [android] Readiness hub «Может ли клиент записаться?» — scoping

- **Stage**: 26 (Android app). **Kind**: design/scoping; no production code, no tickets filed here.
- **Item**: `ago-root#1657` (placeholder, no backlog file yet). Named as deferred in
  `26-111-contact-panel-slices.md` §"Deferred placeholders" and `26-139-android-calendar-config-screens.md`
  §"Config hub".
- **Premise check (bg-worker-brief §0.6)**: the backend exists in full and the console already renders it;
  **nothing on Android exists** — no client, no screen, no `⋮` entry. This is a pure client build over one
  live read. No backend change, no migration.

## 1. What already exists (verified against `origin/main`, 2026-09-26)

**Backend — `ago-calendar` (`95ce462`).** `GET /api/v1/console/booking-readiness`
(`ConsoleEndpoints.cs:62`, handler `GetBookingReadinessHandler`, read store `BookingReadinessReadStore`),
gated **`calendar:configure`** (403 `configuration.forbidden`). Response: `CalendarReadinessResponse[]`
(`ConsoleContracts.cs`):

```
[{ calendarId: guid|null, calendarName: string|null, isBookable: bool,
   preconditions: [{ precondition: string, isMet: bool }] }]
```

- `preconditions` is always the same six, in **fill order** (`25-12`): `WorkerOnCalendar`,
  `ServiceOffered`, `WorkingHoursConfigured`, `ScheduleSaved`, `SlotsMaterialized`, `CalendarPublished`.
  Each is a **funnel** over the calendar's active workers (worker → offers an active service → has hours or a
  Cycle schedule → has a schedule), `SlotsMaterialized` is calendar-wide (`starts_at > now`, `Available`).
- One entry per calendar, in creation order. **Zero calendars → exactly one synthetic entry** with
  `calendarId == null`, `calendarName == null`, everything unmet — the only null this field ever carries.
- `isBookable` is folded server-side; the client must never re-fold the six booleans.

**Console — `ago-console` (`2315100`).** `src/calendar/BookingReadiness.tsx`, rendered as a panel on both
`/calendar/setup` and `/calendar/masters`, each page fetching it alongside its own read; readiness is
"supplementary, not critical" (a failed readiness read never fails the page). Per row: Готово/Не хватает
badge + label; an unmet row links «Исправить» to its form (`ROUTE_FOR`), `SlotsMaterialized` links
«Посмотреть слоты». Russian copy to mirror verbatim (`i18n/ru.ts:1516-1529`): title «Может ли клиент
записаться прямо сейчас?», «Календаря пока нет», «Можно записаться»/«Нельзя записаться», «Готово»/«Не
хватает», «Исправить», «Посмотреть слоты», and the six labels («Календарь опубликован», «На календаре есть
активный мастер», «Этот мастер оказывает услугу», «У этого мастера заданы рабочие часы или циклический
график», «У этого мастера сохранён график», «Слоты сгенерированы в пределах горизонта»).

**Android — `ago-android` (`89dcc2f`).** The `⋮` config hub (`26-103`/`26-157`) opens each config screen as a
**modal page** (`BookingsConfigModalPage`: back-arrow app bar, no avatar, bottom bar hidden) over Записи;
entries are `BookingsTab.{Calendars, Masters, Services, Hours}`, each gated by its own
`calendar:configure` boolean threaded `AppShellScreen → BookingsRoute → visibleBookingsConfigMenuEntries`.
Reusable verbatim: `LoadingBody`/`EmptyBody`/`RefusalBody`/`ActionErrorBanner`, the four-arm `*UiState`,
`BookingsQueueFailure` + `classify`, `KtorWorkersApi`'s check-base-url-first adapter idiom, `AgoIcons.Check` /
`AgoIcons.Exclamation`, `AgoTypography` (titleMedium Bold for a card title, labelMedium for a status word,
bodyMedium rows, `error` colour for a negative word — the Masters card's own treatment).

## 2. What the Android screen does

**Entry.** A fifth `⋮` entry, **first in the menu** — «Готовность» (screen title «Может ли клиент
записаться?»). Rationale: the hub is the "where am I" screen a tenant opens *before* the four fill screens,
and the console's own fill order (Календари · Мастера · Услуги · Часы) is what it points into. Gate:
`calendar:configure`, hide-not-disable, one more boolean in the existing chain (no new permission).
*Alternative (Q1):* embed a compact readiness card at the top of Календари and Мастера, as the console does
— rejected as primary because on a phone it pushes the CRUD list below the fold on the two screens people
use most; offered as an *addition* if the author wants the console's "always visible" posture.

**Body.** Four-arm state over one read (`Loading` / `Loaded` / `NotConfigured` / `Failed` → `RefusalBody` with
retry). `Loaded` = one **calendar card** per server entry, in server order:

- Title row: `calendarName` (titleMedium Bold) or «Календаря пока нет» when null; trailing status word
  «Можно записаться» (onSurfaceVariant) / «Нельзя записаться» (`error` colour, labelMedium) — a word, never a
  colour alone (the Masters «Неактивен» rule).
- Six rows, server order, one per precondition: leading glyph (`AgoIcons.Check` for met,
  `AgoIcons.Exclamation` tinted `error` for unmet) + localized label (bodyMedium). An **unmet** row gets a
  trailing `TextButton` **«Исправить»** (or **«Слоты»** for `SlotsMaterialized`).
- An unknown precondition string renders its raw wire spelling with no button (the same "classification in
  `:core:domain`, unknown shown as-is" rule `ContactDetailsSection.fieldLabel` follows).

**«Исправить» targets (Android's own map — differs from the console where the app's screens differ).**
`CalendarPublished` → Календари; `WorkerOnCalendar` → Мастера; `ServiceOffered` → Мастера (services are
assigned on the worker form); `WorkingHoursConfigured` → **Часы** (Android has a separate Часы screen — the
console points at Setup because Setup owns its hours form; `26-139` already recorded this deliberate
deviation); `ScheduleSaved` → Мастера (→ the График drill-down once `26-155` lands); `SlotsMaterialized` →
Мастера (→ the Слоты drill-down once `26-155` lands). Navigation is an **in-hub swap** of `activeConfigTab`
(no new NavHost route): system back from the target returns to Записи, not to the hub — acceptable, and
stated (Q3).

**Refresh.** Re-read on every open of the screen and on the `RefusalBody` retry; no polling. Readiness is a
snapshot the tenant consults between edits, and every config screen already re-reads after its own writes.

**Copy.** All strings as resources in both languages (`26-91`); the six labels mirror the console's Russian
verbatim; the English side mirrors `i18n/en.ts`.

## 3. Backend change

**None required.** One additive option, *not recommended*: return a "which worker is the funnel's survivor"
id per calendar so «Исправить» could deep-link to a specific worker's form. The funnel is `bool_or` over
workers by design (`IBookingReadinessReadStore` remarks: "someone bookable exists", not "who") — naming one
worker would misreport a two-worker calendar. Leave it.

## 4. Product questions for the author

- **Q1 — Placement.** (A) its own `⋮` entry «Готовность», first in the menu *(recommended)*; (B) a compact
  card at the top of Календари + Мастера (console posture, costs list space on a phone); (C) both.
- **Q2 — Menu label.** «Готовность» (short, fits a `DropdownMenuItem`) with the long question as the page
  title, vs the full «Может ли клиент записаться?» as the menu item too.
- **Q3 — «Исправить» navigation.** In-hub swap to the target config screen (back → Записи), vs pushing the
  target so back returns to the readiness hub (needs a two-level saveable state, the same mechanism `26-155`
  introduces for drill-downs — could share it). Recommend swap now, upgrade when `26-155`'s nesting exists.
- **Q4 — Refresh policy.** Re-read on each open + retry only *(recommended)*, vs pull-to-refresh.
- **Q5 — Before `26-155` lands**, `ScheduleSaved`/`SlotsMaterialized` «Исправить» point at Мастера (the list)
  — acceptable as an interim, or hold `26-164` until `26-155`'s drill-downs exist?

## 5. Proposed implementation tickets (provisional numbers — managing session assigns real ones, ~26-163+)

Each is one promise that lands green (rule 15). Repo tag **[android]**. No migration lane.

- **26-163 [android core] — booking-readiness data client.** `BookingReadinessApi` port (`core/domain`) +
  `KtorBookingReadinessApi` (`core/network`) + models (`CalendarReadiness`, `PreconditionState` with the raw
  wire `precondition` string + a `:core:domain` known-set classification); `NotConfigured` on a null calendar
  base URL, `Failed(BookingsQueueFailure)` otherwise; `di/AppModule.kt` one-line provider. Green = adapter
  unit tests (loaded incl. the null-calendar synthetic entry, not-configured, failure classification).
  *Depends on: none. `core/**` only — parallel-safe with `26-165/166/167`.*
- **26-164 [android app] — Готовность screen + `⋮` entry.** `ReadinessBody`/`ReadinessUiState`/
  `ReadinessViewModel`; `BookingsTab.Readiness` + `showReadinessEntry` boolean threaded through
  `AppShellScreen`/`BookingsRoute`/`visibleBookingsConfigMenuEntries`/`bookingsTabLabel`/
  `BookingsConfigModalPage`; «Исправить» in-hub swap per §2's map; strings both languages; a unit test for
  the gating + a VM test. Green = the screen renders the server's list with per-row fix actions, gated
  `calendar:configure`; `ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green. *Depends on:
  26-163. **Serializes** with every other edit of `BookingsTab.kt`/`BookingsScreen.kt`/`AppShellScreen.kt`/
  `strings.xml` — i.e. with `26-168/169/170`.*
- *(folded, not its own ticket)* re-pointing `ScheduleSaved`/`SlotsMaterialized` at the drill-downs is a
  two-line change inside whichever of `26-164` / `26-168` lands second.

Closing `#1657`: it becomes the umbrella closed when `26-164` merges (or is cancelled with reason if Q1 = B
changes the shape enough to re-file).
