# 26-139 · [android core] Masters (workers) data client

- **Stage**: 26 — first slice of the Android calendar-config screens. Design:
  `docs/design/26-139-android-calendar-config-screens.md`.
- **Status**: ready — in flight.

## One promise
A `core` data client (port + Ktor adapter) over the already-live worker endpoints, so the Masters screen
(26-140) is a pure UI build on top. No `app/` UI, no migration.

## Scope
- `WorkersApi` port + `Worker`/`WorkerDraft` models + result types (reuse `BookingsQueueFailure`,
  `BookingActionResult`/`BookingActionErrorUi`). `KtorWorkersApi` over `GET /console/workers`, `GET/POST/PUT/
  DELETE /workers/{id}` (delete refusable, surface `detail`), plus the `calendars[]`/`services[]` read from
  `GET /configuration`. Adapter tests. `core/**` only. Mirrors `WorkingHoursApi`/`KtorWorkingHoursApi`.

## Done when
- [ ] Port + adapter cover list/get/create/update/delete + config read; refusal detail surfaced; tests green;
      `ktlintCheck lint test` green; no `app/` files touched.
