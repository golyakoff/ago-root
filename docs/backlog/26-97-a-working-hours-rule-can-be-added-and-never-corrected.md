# 26-97 · A working-hours rule can be added and never corrected

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-24, scoping the Записи (bookings/calendar) build-out for Android — not named
  anywhere in the mockup or in `ago-android/docs/navigation.md`, found while checking the real API
  behind the worker schedule screen. The author's own instruction, 2026-09-24: fix it in both the
  console and the Android app.

## What is actually true today, confirmed against real code

- `ago-calendar`'s `ConsoleEndpoints.cs` maps exactly one working-hours endpoint:
  `POST /api/v1/console/working-hours` (`addWorkingHoursRule`). `AddWorkingHoursRuleHandler` is the
  **only** use case in `Ago.Calendar.Application/UseCases/Configuration/` that touches working hours.
  There is no `PUT`, no `DELETE`, and no id-addressed read for one rule.
- `ago-console/src/pages/CalendarSetupPage.tsx:331-340` lists a calendar's existing working-hours rules
  **read-only** — no actions column, matching the missing endpoints exactly.
- A working-hours rule is precondition 4 of the six `booking-readiness` checks and directly decides what
  a schedule template materialises into real slots. **Typing 09:00 for 19:00 is permanent** today — the
  only available remedy anywhere in the product is deleting the worker entirely (`IWorkerRepository`'s
  own remarks note a worker's working-hours rules are removed with him), which also discards everything
  else about that worker.
- This is a materially worse gap than `26-96`'s (a wrong service duration is visible and merely
  embarrassing; a wrong working-hours rule silently cuts the wrong slots for every day inside the
  schedule's own horizon, with no client ever showing that anything is wrong).

## Scope

One promise: **an existing working-hours rule can be corrected or removed.**

1. **`ago-calendar`**: `DELETE /working-hours/{ruleId}` and/or `PUT /working-hours/{ruleId}`,
   tenant-scoped (refusing across a `TenantMismatchException` the same way every other tenant-scoped
   write already does), refusing wherever the domain's own validation already refuses a new rule.
2. **The materialisation question, decided and written down before implementation, not discovered
   during it**: a calendar's schedule may already have materialised real slots — some possibly already
   booked — from the rule being changed or removed. `RecutSchedule` (`26-97`'s sibling, the `26-90`
   planning pass's item **G**) already exists to handle exactly "the schedule changed, decide what
   happens to the days already cut" for the *template* case; the real design question here is whether a
   working-hours edit should (a) require running that same recut flow afterward, stated on screen as a
   next step, or (b) refuse the edit outright while any already-materialised day inside the rule's own
   range still has a live (non-cancelled, non-no-show) booking on it, forcing the recut to happen through
   a different path first. Pick one, state the reasoning in the PR — **do not silently leave
   already-booked slots unreconciled** either way.
3. **`ago-console`**: `CalendarSetupPage.tsx`'s working-hours list gains an actions column.
4. **`ago-android`** (this item supersedes the "cannot yet be changed" line in the planning pass's item
   **E**, «График мастера» — read that item's own Scope for the rest of what that screen already does):
   the same edit/delete affordance, reachable from the same list.

## Out of scope

- The schedule *template* itself (kind, slot/buffer minutes, horizon) — already editable via
  `saveWorkerSchedule`'s own create-or-replace upsert; this item is working-hours *rules* specifically.
- Building the recut flow itself if option (a) is chosen — that is the planning pass's own item **G**,
  a separate, already-scoped promise; this item only decides whether editing hours *triggers* it.

## Done when

- [ ] An existing working-hours rule can be corrected or removed from both the console and the phone,
      and the change is reflected in that calendar's own `booking-readiness` response afterward.
- [ ] A rule belonging to another tenant cannot be touched — the `TenantMismatchException` path,
      integration-tested.
- [ ] The materialisation question (2) is decided and documented before any client-side work started on
      it — not discovered mid-implementation — and no already-booked slot is left silently orphaned by
      either the chosen answer or its implementation.
- [ ] `dotnet format`/`build`/`test` (ago-calendar) green; `ago-console`'s full command set
      (`typecheck`/`lint`/`test`/`ux-gate`) green; `./gradlew ktlintCheck lint test assembleDebug`
      (ago-android) green.
- [ ] Checked once against a real tenant with a real materialised schedule: edit or remove a rule that
      has already cut real slots, and confirm the chosen (2) behaviour actually happens rather than
      merely compiling.
