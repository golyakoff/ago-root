# 25-74 · A worker cannot gain a second service, and a slot lies about its own end

- **Stage**: 25
- **Status**: done — `ago-calendar#64`/`ago-console#217`
- **Found**: 2026-09-13, reported by the author against the live tenant `golyakov.net`: a worker has
  two services configured but booking only ever offers one, and a service longer than the calendar's
  slot grid looked like it might only be blocking as much time as one grid cell rather than its own
  full duration.

## Two unrelated bugs, not one - confirmed against golyakov.net's own live data and code

### 1. A worker's services can only ever be set at creation - there is no way to add one later

`CreateWorkerHandler` calls `Worker.Offer(service)` - the only call site of `Worker.Offer` in the whole
codebase. `UpdateWorkerHandler`/its `UpdateWorker` command carry no `ServiceIds` field at all; they only
rename, reactivate or deactivate. On the console side, `WorkerCard.tsx`'s service-checkbox `<fieldset>`
is wrapped in `{mode === "create" && (...)}` - not rendered in edit mode - and `CalendarWorkersPage.tsx`
only sends `serviceIds` on the `createWorker` branch, never on `updateWorker`; `calendarApi.ts`'s
`updateWorker` request type has no such property to send even if the console tried.

**Confirmed live**: golyakov.net's tenant has two services in its catalog (`Консультация`, 60 min;
`Примерка`, 90 min) but `worker_services` holds exactly one row, linking the worker only to
`Консультация`. Whatever happened when a second service was meant to be added, there was and is no
application-layer path that could have made it stick.

### 2. A slot's own `EndsAt` is the first grid cell's end, not the full run's end

`BookingSurfaceReadStore.OpenSlotsSql` selects `e.ends_at as "EndsAt"` from the run's *starting* event
row only - it verifies (via `generate_series`/`NOT EXISTS`) that enough consecutive `Available` slots
exist, but never reads or projects the *last* slot's own end. A service needing more than one grid slot
(golyakov.net: a 60-minute service on a 30-minute, no-buffer schedule) therefore reports an `EndsAt`
exactly one grid cell after `StartsAt`, regardless of the service's real duration.

**This is a display bug, not a reservation bug** - worth stating plainly, because it would be easy to
conflate the two. `ConsecutiveRunFinder`/`BookEventHandler`/`BookingStore.ClaimSlotSql` (`20-18`)
already correctly compute `ceil(duration/slot)` and atomically claim every row in the run - a booking
for a 60-minute service genuinely blocks the full hour today, and there is no double-booking risk. What
is wrong is only what the customer is shown before they pick a time: `ModuleStepFactory.SlotChoice`'s
button label (`DescribeTimeOnly`) is built straight from this store's `EndsAt`, so a 60-minute service
on a 30-minute grid shows a button reading a 30-minute range while the click behind it actually reserves
an hour.

**Proven, not merely reasoned about**: a real integration test against a real Postgres
(`OpenSlotsEndAtTests.AServiceNeedingTwoSlots_ReportsTheFullRunsEnd_NotTheFirstSlotsOwnEnd`, written and
run 2026-09-13, currently sitting uncommitted in the worktree at
`C:/git/ago/ago-calendar-slot-endat`, branch `diag/slot-endat-e2e-2` - reuse it as this item's own
fails-before rather than writing a second one) fails exactly as predicted: expected `07:00:00Z`
(start + the service's own 60 minutes), got `06:30:00Z` (start + one grid cell).

## What this item is not

- **Not a design question.** The existing shape - pick a start time at the grid's own granularity,
  reserve however long the chosen service actually takes - already matches how Calendly and most
  booking-style products work, and the reservation half is already built correctly. Nothing here asks
  "how should this work"; both are concrete bugs with an obvious correct fix each.
- **The one small, genuinely open UX call**: should `SlotChoice`'s button show the full range
  (`09:00–10:00`, matching what the confirmation card already shows via `DescribeRange`) once `EndsAt`
  is fixed, or keep a time-only label and state the duration elsewhere in the step's own prompt? The
  author's own lean, stated when this was found: show the range on the button - it both fixes the bug
  and costs nothing else. Confirm before implementing rather than assuming.

## Scope

1. `UpdateWorkerHandler`/`UpdateWorker` gains the ability to change which services a worker offers - the
   symmetric write `Worker.Offer`/whatever a removal needs already exist or need adding on the domain
   side; the gap is entirely in the handler and the console never reaching them.
2. `WorkerCard.tsx` renders the service-checkbox set in edit mode too, and `CalendarWorkersPage.tsx`/
   `calendarApi.ts` carry `serviceIds` on the update path, not only create.
3. `BookingSurfaceReadStore.OpenSlotsSql` computes the run's own true end (`starts_at` of the run's
   first slot, plus the consecutive run's own total span) rather than selecting the starting row's own
   `ends_at`.
4. `ModuleStepFactory.SlotChoice`'s button label reflects the fixed `EndsAt` - resolve the one open UX
   question above before or during implementation, not after.

## Done when

- [x] An operator can add a second service to an existing worker through the console, and it is
      immediately offered at booking - proven end to end, not only that the API call succeeds. —
      `WorkerEndpointTests`' new end-to-end test proves the booking surface itself lists the worker for
      the newly-added service, not only that the `PUT` returns 204.
- [x] `OpenSlotsEndAtTests.AServiceNeedingTwoSlots_ReportsTheFullRunsEnd_NotTheFirstSlotsOwnEnd` (or its
      committed equivalent) passes. — the reused diagnostic test, now committed, passes.
- [~] The widget's own time-choice button for a multi-slot service shows the service's real end time,
      confirmed by hand against a real booking flow, not only the underlying query. — **mechanism
      confirmed by code-path reading, not yet by hand**: `ModuleStepFactory.SlotChoice`'s
      `DescribeTimeOnly` already builds a start-end range string from `EndsAt`, so the fixed SQL reaches
      it (and the widget, which renders the label verbatim) with no further code change — but nobody has
      clicked through a real booking with the fix live. Carried to the next Done-when box's own deploy.
- [ ] golyakov.net's own live worker is re-checked after deploy: both services genuinely bookable, and
      a multi-slot service's button shows its real range. Pending the redeploy this queue's own items
      are batched into.
