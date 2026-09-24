# 26-96 · A service cannot be edited or deleted anywhere in the product

- **Stage**: 26
- **Status**: done — merged as [ago-calendar#72](https://github.com/golyakoff/ago-calendar/pull/72),
  [ago-console#276](https://github.com/golyakoff/ago-console/pull/276) and
  [ago-android#85](https://github.com/golyakoff/ago-android/pull/85). Chose archive
  (`Service.IsActive`), not delete — `events.service_id` survives forever and four read models
  resolve a booking's service name through it. `GET /configuration` keeps returning archived
  services so a worker card or past booking can still resolve the name.
- **Found**: 2026-09-24, scoping the Записи (bookings/calendar) build-out for Android. Named three times
  already in this codebase's own docs before this item existed: `ago-console/src/pages/
  CalendarServicesPage.tsx:56-61` ("a real gap, not an oversight"), `ago-android/docs/navigation.md:527`
  ("worth its own backlog item"), `ago-android/docs/scope-inventory.md` §4 ("the product's own gap
  rather than a mobile compromise"). The author's own instruction, 2026-09-24: fix it in both the console
  and the Android app.

## What is actually true today, confirmed against real code

- `ago-calendar`'s `ConsoleEndpoints.cs` maps `GET /configuration` (returns `TenantConfiguration.services`)
  and `POST /services` (`createService`) — and nothing else for this type. No `PUT`, no `DELETE`.
- `ConfiguredService` carries `name`, `durationMinutes`, `priceMinorUnits` (kopecks, nullable),
  `priceCurrencyCode` (nullable, always `"RUB"` today), `priceIsFrom`, `description`. There is **no
  active/inactive concept** — `CalendarServicesPage.tsx:60-61` names its absence explicitly as part of
  the same gap.
- These fields are visitor-facing: the booking widget reads the same `price`/`description` a service
  carries, so an edit here is not merely an internal admin correction — it changes what a visitor sees.
- Nothing today references a service by anything other than its id — `WorkerDetail.serviceIds`,
  `PendingBooking`/`ConfirmedBooking.serviceId`, `RecutBookingPreview` — so "what happens to a service in
  use" is a real question the moment deletion is on the table, not a hypothetical.

## Scope

One promise: **a service typed wrong can be corrected, and one no longer offered can be taken out of
rotation, without breaking anything that already references it.**

1. **`ago-calendar`**: `PUT /services/{serviceId}` — the same five fields `createService` already takes.
   Refuses (with the domain's own reason) exactly where creation already refuses (e.g. a non-positive
   duration).
2. **The deletion question, decided and written down before implementation, not discovered during it**:
   a service a worker performs and bookings reference almost certainly should not vanish out from under
   them. The two live options are (a) add an `isActive`/`archivedAt` concept — `PUT` (or a dedicated
   `POST /services/{id}/archive`) flips it, `GET /configuration` keeps returning archived services
   (so existing bookings/worker cards can still resolve their name) but the create/edit surfaces stop
   offering them as choosable, or (b) refuse deletion outright while any worker or future booking
   references the service, and offer nothing softer. Pick one, state the reasoning in the PR, and update
   `ConfiguredService`'s own shape accordingly (an `isActive` field, if (a)).
3. **`ago-console`**: `CalendarServicesPage.tsx` gains an actions column — edit (the five fields) and
   whichever deactivate/delete affordance (2) settled on.
4. **`ago-android`** (this item supersedes the "no edit" line in `26-70`'s sibling item, the Услуги
   screen — read that item's own Scope for the rest of what that screen already does): the same edit
   form as the console's, and the same deactivate/delete affordance, both reachable from a service row.

## Out of scope

- Any change to how a service is *chosen* on a worker card or a booking — this item only touches the
  service's own record.
- The visitor-facing booking widget's own read of `price`/`description` — already correct; an edit here
  simply changes what it reads, not how it reads it.

## Done when

- [x] A service's name, duration, price and description can be changed from both the console and the
      phone; the same call updates the record both clients read.
- [x] The deactivate/delete question is decided and documented (archive via `Service.IsActive`, not
      delete — `events.service_id` survives forever) before any client-side work started on it.
- [x] A service referenced by an existing worker or a real booking cannot silently disappear from either
      client's own display of that worker/booking — `GET /configuration` keeps returning archived
      services.
- [x] `dotnet format`/`build`/`test` (ago-calendar): 867 tests, 0 failed. `ago-console`'s full command
      set (`typecheck`/`lint`/`test`/`ux-gate`): all green. `./gradlew ktlintCheck lint test
      assembleDebug` (ago-android): 550 tests, 0 failed.
- [~] Checked against a real tenant — not done by the managing session; verified locally only (unit/
      integration tests, no live demo-tenant walkthrough).
