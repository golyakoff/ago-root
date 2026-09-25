# 26-141 · [android core] Calendar-setup data client

- **Stage**: 26 — Android calendar-config slice. Design:
  `docs/design/26-139-android-calendar-config-screens.md`.
- **Status**: ready — in flight.

## One promise
A `core` data client (port + Ktor adapter) over the live configuration/allowed-origins/calendars endpoints,
so the Настройка/Календари screen (26-142) is a pure UI build. No `app/` UI, no migration.

## Scope
- `CalendarSetupApi` port + `TenantSetup`/`ConfiguredCalendar`/`CalendarDraft` models + result types (reuse the
  shared failure/action types). `KtorCalendarSetupApi` over `GET /configuration`, `PUT /configuration/
  allowed-origins`, `POST /calendars` (Name, TimeZone, Publish), `PUT /calendars/{id}` (Name, Publish —
  timezone create-only; no delete-calendar endpoint). Adapter tests. `core/**` only, different files from
  26-139. Mirrors `WorkingHoursApi`/`KtorWorkingHoursApi`.

## Done when
- [ ] Port + adapter cover config read + allowed-origins save + calendar create/update; tests green;
      `ktlintCheck lint test` green; no `app/` files touched.
