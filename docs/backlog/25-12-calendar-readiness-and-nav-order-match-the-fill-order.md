# 25-12 · The calendar's readiness checklist and nav both order by how a tenant actually fills them in

- **Stage**: 23
- **Status**: done — `ago-calendar#53`, `ago-console#179`
- **Depends on**: none
- **Found**: 2026-09-09, the author logging in as a tenant with the calendar module, opening
  `/calendar/masters` first, and reading the readiness checklist there

## Why this exists

The author read the readiness checklist on the Workers screen and the calendar nav menu in the order
they actually appear today, and both read backwards from how a tenant would naturally work through
setup — a checklist that does not read top-to-bottom as "do this, then this" makes a tenant guess
which unmet item to fix first, and a nav menu that opens on setup dictionaries before the screens a
day-to-day operator actually lives in buries the two most-used screens under ones a tenant visits once
and rarely returns to.

## Part 1 — the readiness checklist's order

`GetBookingReadinessHandler` (`Ago.Calendar.Application`) computes six named preconditions in a fixed
order, sent to the console verbatim — the console does no sorting of its own
(`ago-console/src/calendar/BookingReadiness.tsx`, `23-23`'s own item). Read against the actual funnel
SQL (`BookingReadinessReadStore.cs`), the true dependency chain is:

```
CalendarPublished      — independent (a toggle on the calendar row itself)
WorkerOnCalendar       — independent (any active worker on the calendar)
ServiceOffered         — needs WorkerOnCalendar (the funnel: bool_or(has_service))
WorkingHoursConfigured — needs WorkerOnCalendar AND ServiceOffered (bool_or(has_service AND has_hours))
ScheduleSaved          — needs the above three (bool_or(has_service AND has_hours AND has_schedule))
SlotsMaterialized      — a separate existence check (future `events` rows), practically downstream
                          of ScheduleSaved since nothing else produces one
```

**Five of the six are already in a valid dependency order.** The one item out of place is
`CalendarPublished`, listed first even though nothing depends on it and it depends on nothing —
structurally free to go anywhere, but conceptually it is the "go live" switch a tenant flips *last*,
once every other fact is true, not the first thing to fix. Leading the list with it reads as "fix
this first" for a step that is normally fixed last.

**Proposed order**: `WorkerOnCalendar`, `ServiceOffered`, `WorkingHoursConfigured`, `ScheduleSaved`,
`SlotsMaterialized`, `CalendarPublished` — the five dependency-chained facts in their existing
(already-correct) order, with the independent "go live" toggle moved to the end rather than the
front.

This is `GetBookingReadinessHandler`'s own `Order` array — a five-line change, sent to the console
unchanged (`BookingReadiness.tsx` renders whatever order it receives).

## Part 2 — the calendar nav menu's order

`buildCalendarItems` (`ago-console/src/shell/consoleNav.ts`) currently orders the full-access
(`calendar:configure`) menu:

```
Мастера → Услуги → Расписание → В ожидании → Записи → Клиенты → Показы телефонов → Объединения → Настройка
```

The author's own request: lead with the screens a tenant with a running calendar actually lives in,
then the setup dictionaries in the order they get filled in:

```
В ожидании → Записи → ?
```

**Proposed continuation**, reasoned from the same dependency chain Part 1 makes explicit, plus how
often each screen is opened once setup is done:

```
В ожидании → Записи → Клиенты → Мастера → Услуги → Расписание → Настройка → Показы телефонов → Объединения
```

- **В ожидании, Записи** — the author's own first two, unchanged: what needs a decision now, then
  the confirmed calendar.
- **Клиенты** — the tenant's own customer base; consulted often, not a one-time setup step, so it
  sits with the operational screens rather than the dictionaries below it.
- **Мастера → Услуги → Расписание** — the setup dictionaries, in the same fill order Part 1 names:
  a worker before a service can be assigned to one, a service before hours are meaningfully checked
  by the funnel above.
- **Настройка** — placed after the three dictionaries rather than with them, because
  `BookingReadiness.tsx`'s own `ROUTE_FOR` map sends *both* `WorkingHoursConfigured` (early setup)
  and `CalendarPublished` (the last, "go live" step) to this one page — **named here as an open
  question rather than assumed**: this screen serves two different moments in the fill order, and
  putting it after the dictionaries only fits the second of those two. Confirm before building
  whether that is the right resting place, or whether the page itself should split.
- **Показы телефонов, Объединения** — audit trails, opened rarely and only after something else
  already happened; last is where an infrequently-opened screen belongs.

## Where this is likely to go wrong

- **The muted/hidden branches of `buildCalendarItems`** (an admin without `calendar:configure`, an
  operator with only booking permissions) build their own item lists independently — `23-57`'s own
  ordering comment there ("`Bookings` first, matching the full-access ordering above") means those
  branches need the identical reordering, not just the full-access one, or the three menus start
  disagreeing with each other.
- **This is a display-order change only.** Nothing about which items appear, what gates them, or
  what a route does should move — `AppShellNavItem`'s array order is the only thing this item
  touches on the console side, and `Order` in `GetBookingReadinessHandler` is the only thing it
  touches on the server side.

## Done when

- [x] Done, `ago-calendar#53`. CI's own integration-level order test caught a hard-coded
      assertion my local run missed - fixed in the same PR (298/298 after).
- [x] `buildCalendarItems`'s full-access branch reorders to exactly the proposed sequence,
      `ago-console#179`. The `Настройка` placement question is answered by the implementer's own
      stated choice (after the three dictionaries), not settled by the author — recorded in the
      component's own comment as the chosen middle ground, not a final answer.
- [x] The operator-limited branch already pushed in the matching relative order — only its stale
      comment needed a fix. The admin-muted branch has one item, nothing to reorder.
- [x] `src/shell/consoleNav.test.ts` (new) pins all three branches' order directly against
      `buildTenantNavSections`'s real output.
