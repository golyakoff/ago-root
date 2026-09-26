# 26-155 · [android] Masters drill-downs — График / Слоты / Пересчёт — scoping

- **Stage**: 26 (Android app). **Kind**: design/scoping; no production code, no tickets filed here.
- **Item**: `ago-root#1658` (placeholder, no backlog file). Named as "folded-out future drill-downs" in
  `26-139-android-calendar-config-screens.md` §"Мастера".
- **Premise check (bg-worker-brief §0.6)**: all three backend surfaces exist and the console has a page for
  each; **Android has none of the three** — `WorkersApi` (`26-139`) is roster CRUD only, and the Masters
  card (`26-140`) has Изменить / Снять с активных / Удалить and nothing else. One shipped Android touchpoint
  already *points at* the missing re-cut: the Часы screen's `RecutNotice` (`26-97`) tells the operator to
  «пересчитайте расписание с {date}» with nowhere to do it. No backend change, no migration.

## 1. What already exists (verified against `origin/main`, 2026-09-26)

**Backend — `ago-calendar` (`95ce462`), all under `/api/v1/console`, all gated `calendar:configure`:**

| Surface | Route | Wire | Notes |
|---|---|---|---|
| Schedule read | `GET /workers/{id}/schedule` | `WorkerScheduleResponse` | **404 `configuration.no_schedule`** when none yet — a real "create" state, not an error (the console renders the empty form on that code) |
| Schedule save | `PUT /workers/{id}/schedule` | `SaveWorkerScheduleRequest` → `WorkerScheduleResponse` | create-or-replace; `Kind` `"Weekly"`/`"Cycle"`; cycle fields required together; `HorizonDays ≤ 180`, `BufferMinutes ≤ 480`; `MaterializeFrom` **forward-only** (400 `configuration.invalid`); `BuffersCountTowardServiceDuration` default true |
| Slots | `GET /workers/{id}/slots?from&to` | `WorkerSlotResponse[]` | every status (`Available`/`PendingConfirmation`/`Booked`/`Cancelled`/`NoShow`/`Blocked`); `personId` never gated, `phone`+`masked` only with **`customer:read`** (null otherwise); `bookingId` groups a multi-slot run; `weekday` server-derived; 400 `worker_slots.invalid_range` |
| Re-cut preview | `POST /workers/{id}/schedule/recut/preview` `{from}` | `RecutPreviewResponse{days[], fingerprint}` | days = `[from, today+horizon]` incl. empty ones; per booking `canDecide` (false for NoShow); 400 `recut.from_before_today` / `recut.not_a_regression` / `recut.horizon_before_from` / `recut.worker_has_no_schedule` |
| Re-cut confirm | `POST /workers/{id}/schedule/recut` `{from, fingerprint, decisions[]}` | `RecutConfirmResponse{recutDays, skippedDays, slotsDeleted, slotsInserted, bookingsCancelled}` | **409 `recut.stale`** (a booking landed since preview → reload); 400 `recut.missing_decision`; 409 `recut.day_changed_concurrently` (days already re-cut stand) |
| Phone reveal | `POST /contacts/{personId}/reveal-phone` `{surface}` | `{phone}` | already an Android client (`BookingsApi.revealCustomerPhone`, `26-53`); `surface` is free text for the audit |

Error codes travel as RFC 7807 **`type`** (`ErrorExtensions.cs`: "clients branch on `type`, never on the
message"); `detail` is the human sentence.

**Console — `ago-console` (`2315100`).** `WorkerScheduleSection.tsx` (inside the worker card; one form for
both kinds; the 70-minute arithmetic note; «Не генерировать раньше» min = existing cursor; a link to the
re-cut when a schedule exists), `CalendarWorkerSlotsPage.tsx` (from/to default today..+14, table of every
status, calendar-zone times, reveal per person, `26-161` person-name display-merge; the multi-slot border
grouping was deliberately dropped), `CalendarWorkerRecutPage.tsx` (three steps: date + Предпросмотр → per-day
cards with Отменить/Оставить radios per decidable booking → inline confirm panel with the four numbers and
«Это нельзя отменить»; `recut.stale` clears the preview). Row actions «Слоты»/«Пересчёт» sit on the workers
table. Russian copy to mirror: `i18n/ru.ts:1533-1649`.

**Android — `ago-android` (`89dcc2f`).** Masters screen (`MastersBody`/`MastersUiState`/`MastersViewModel`,
`WorkerCard`, `WorkerEditForm`), the modal config page + single-level `activeConfigTab: BookingsTab?`
(`26-157`), `BookingsQueueFailure`/`BookingActionResult`/`ActionErrorBanner`, the Masters delete
`AlertDialog`, `FilterChip` rows, typed `HH:mm` `OutlinedTextField`s with `KeyboardType.Number` (Часы),
`DatePickerDialog` + UTC-midnight round trip (`AnalyticsDateRangeControl`, `26-57`), `BusinessLocalTime`
(calendar-zone rendering, `26-51`), `PersonsApi` display-merge (`26-162`), `SectionLabel`,
`IdentifierText`. **Adapter gap (client-side only):** the calendar adapters read only ProblemDetails
`detail`; the analytics adapters already read `type` — the schedule client must read `type` to tell
`configuration.no_schedule` from a failure.

## 2. What the Android screens do

**Navigation.** The `WorkerCard` gains two `TextButton`s on its action row — **«График»** and **«Слоты»**
(console row-action parity). **«Пересчёт» is not a card action**: it is destructive and only meaningful once a
schedule exists, so it is reached (a) from a note+button inside График when a schedule exists (console
parity) and (b) from the Часы `RecutNotice`, which becomes tappable and opens Пересчёт with `from`
pre-filled to the server's `recutFrom`. A drill-down is a **second-level modal page** over Masters: one new
saveable `MastersDrillDown(workerId, kind: Schedule|Slots|Recut)?` beside `activeConfigTab`; app bar title
«{Screen} — {displayName}»; system back returns to the Masters list (Masters stays loaded underneath). Same
chrome as `BookingsConfigModalPage`, no new NavHost route. Each drill-down VM is `hiltViewModel()` **only
inside its branch** (the `26-51` Hilt-avoidance rule; and the `26-162` androidTest landmine).

**График (schedule).** Four-arm state where `Loaded` carries `existing: WorkerSchedule?` + the form. Form
(one column, `12.dp` spacing, the `WorkerEditForm` idiom): Шаблон `FilterChip` pair Недельный / Цикл; Cycle
only → Дата привязки (`DatePickerDialog` button), Рабочих дней, Выходных дней, Открытие/Закрытие (typed
`HH:mm`); Weekly only → note «Недельные часы задаются на экране Часы» **tappable** (in-hub swap to Часы);
Длина слота, Перерыв (Number); checkbox «Перерывы внутри длинной записи считаются рабочим временем» + the
70-минут arithmetic caption (mirrors `ConsecutiveRunFinder.ComputeSlotsNeeded`, display only); Горизонт with
caption «Ограничено 180 днями» (cap enforced server-side, not on the client — console decision, kept);
«Не генерировать раньше» date with caption «нельзя сдвинуть раньше, чем {cursor}» when existing (no client
`min`; the server's 400 `detail` is shown verbatim); when existing → note «Нужно исправить дни, уже
нарезанные по старому шаблону?» + «Пересчитать» button → Пересчёт. Primary button «Создать расписание» /
«Сохранить». Empty note «Расписания пока нет…» when none. Save → re-read (no optimistic). Switching Cycle →
Weekly shows the console's warning line, no confirm gate.

**Слоты (slots).** Header row: two date buttons (`DatePickerDialog`, default today..+14 in the **calendar's
zone**) + «Обновить»; caption «Время указано по местному поясу {tz}». Body: one flat `LazyColumn` grouped by
day with a `SectionLabel` per `localDate` («{date} · {weekday}»), rows: `HH:mm–HH:mm` (`BusinessLocalTime`),
status word (six localized words), service name or «—», person name via `PersonsApi` display-merge (degrades
to «имя пока не показано» / `IdentifierText`), phone — only when the server sent one — masked + «Показать»
(reuse `revealCustomerPhone`, `surface = "AndroidWorkerSlots"`, replace every row of that person in place,
masked stays on failure). Rows sharing a `bookingId` are **not** visually merged (the console dropped it too;
stated). Empty: «В этом диапазоне нет слотов.» `worker_slots.invalid_range` → banner with `detail`.

**Пересчёт (re-cut).** Three steps on one page. (1) «Пересчитать с» date button (default: today, or the
`recutFrom` handed in from Часы) + «Предпросмотр». (2) Preview: an info line when nothing is generated in
range; one **day card** per `days[]` entry (title = date; «N свободных слотов будет удалено»; «В этот день
записей нет.» or its bookings: time, service, person name, phone/reveal (`surface = "AndroidRecut"`), status
word; a decidable booking gets a `FilterChip` pair **Отменить / Оставить**; a NoShow booking gets the note
«Уже произошло как неявка — этот день сохраняется»; a day with any Оставить/NoShow shows «(останется без
изменений)»). «Просмотреть и подтвердить» enabled only when **every** decidable booking is decided; the
console's helper line otherwise. (3) Confirm = **`AlertDialog`** (the app's own destructive idiom — Masters
delete, Часы delete): the four numbers («очистит и заново создаст N дн., удалив N своб. слотов и отменив N
записей; N дн. останутся точно такими же…») + «Это нельзя отменить» + destructive «Подтвердить пересчёт».
Result card («Готово»: recut/skipped/deleted/inserted/cancelled). Errors: `recut.stale` → clear preview +
decisions, banner with `detail` («…Reload the preview…»); `recut.day_changed_concurrently` → same, and the
banner's `detail` already says days re-cut so far stand; every other refusal → `detail` verbatim, state kept.

**Copy.** Every string a resource in both languages (`26-91`); Russian mirrors `ru.ts` verbatim.

## 3. Backend change

**None required.** Two adapter-side notes, neither a server change: (1) read ProblemDetails `type` in the
new calendar adapters (for `configuration.no_schedule`, `recut.stale`); (2) two new free-text reveal
`surface` values, `AndroidWorkerSlots` / `AndroidRecut`, accepted as-is by `RevealCustomerPhoneRequest`.
*Not proposed:* a per-service slot grid or a merged multi-slot row — `20-15`'s own scope keeps a slot one
row, and this item inherits that.

## 4. Product questions for the author

- **Q1 — Entry shape.** Two card buttons «График»/«Слоты» *(recommended, console parity)* vs one «›» into a
  per-worker detail page holding all three as rows (one more tap, but a smaller card).
- **Q2 — Where Пересчёт lives.** Only inside График + from the Часы notice *(recommended — destructive, needs
  a schedule)* vs also a third card button.
- **Q3 — Confirm step.** `AlertDialog` *(recommended, the app's idiom)* vs the console's inline second panel.
- **Q4 — Time input.** Typed `HH:mm` (Часы parity, zero new components) *(recommended for now)* vs a
  `TimePickerDialog` — if the latter, Часы should switch in the same pass (its own small item).
- **Q5 — Slots default range** today..+14 (console) — confirm; and is a cap on the range wanted client-side
  (the server has none)?
- **Q6 — Show `Cancelled` rows in Слоты?** The server returns them and the console shows them; a phone list
  is longer — keep (recommended: "did my schedule come out right" needs every row) or filter?
- **Q7 — Audit surfaces** `AndroidWorkerSlots` / `AndroidRecut` — confirm the vocabulary (the console uses
  `ConsoleWorkerSlots` / `ConsoleRecut`).
- **Q8 — Back from a drill-down** returns to the Masters list (recommended) — confirm, since `26-154` Q3
  may reuse the same two-level state.

## 5. Proposed implementation tickets (provisional — managing session assigns real numbers, ~26-165+)

One promise each (rule 15); repo tag **[android]**; no migration lane.

- **26-165 [android core] — worker-schedule client.** `WorkerScheduleApi` (`fetchSchedule` →
  `Loaded(schedule)` / **`None`** (on `configuration.no_schedule`, read from `type`) / `NotConfigured` /
  `Failed`; `saveSchedule(workerId, draft)` → `Saved(schedule)` / `Refused(detail)` / `Failed`) + models +
  Ktor adapter + tests + `AppModule` line. *Depends on: none.*
- **26-166 [android core] — worker-slots client.** `WorkerSlotsApi.fetchSlots(workerId, from, to)` →
  `Loaded(slots)` / `NotConfigured` / `Refused(detail)` / `Failed`; `WorkerSlot` model (every field incl.
  `bookingId`, `personId`, nullable `phone`+`masked`); tests; `AppModule` line. *Depends on: none. ∥ 26-165.*
- **26-167 [android core] — re-cut client.** `RecutApi.preview(workerId, from)` and
  `confirm(workerId, from, fingerprint, decisions)`; results carry `Refused(detail, code)` so the UI can
  branch on `recut.stale`; tests; `AppModule` line. *Depends on: none. ∥ 26-165/166.*
- **26-168 [android app] — «График» screen + the Masters drill-down navigation.** The two-level
  `MastersDrillDown` state + nested modal page + card «График»/«Слоты» buttons (Слоты button present but
  its page lands in 26-169 — *if the author prefers no dead button, ship the Слоты button in 26-169
  instead*); `WorkerScheduleBody`/UiState/VM; strings; tests (VM + gating). Green = a worker's schedule can
  be created and edited from the app; back returns to Masters. *Depends on: 26-165. **Join point** for
  26-169/170; serializes with 26-164 on `BookingsScreen.kt`/`strings.xml`.*
- **26-169 [android app] — «Слоты» screen.** Range control, grouped list, person display-merge, reveal
  with `surface = "AndroidWorkerSlots"`; strings; tests. *Depends on: 26-166, 26-168.*
- **26-170 [android app] — «Пересчёт» screen.** Three steps, decisions, `AlertDialog` confirm, result,
  `recut.stale` handling; entry from График's note and from the Часы `RecutNotice` (pre-filled `from`);
  strings; tests. *Depends on: 26-167, 26-168.*

**Parallelism:** 26-165 ∥ 26-166 ∥ 26-167 (disjoint `core/**` files; `AppModule.kt` one line each — rebase
touch-up). 26-168 → then 26-169 ∥ 26-170 only if they keep to their own `bookings/masters/*.kt` files; they
both touch `strings.xml` and the drill-down `when`, so **land them one at a time**. PRs one at a time (rule
13). Closing `#1658`: umbrella, closed when 26-170 merges.
