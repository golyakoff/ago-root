# 26-315 · [ago-calendar] a freshly saved schedule has no slots until the daily job — no on-demand or on-save materialisation

- **Stage**: 26
- **Status**: done — merged as `ago-calendar#` (`df7f1369`), deployed. «Пересчёт» now bootstraps the
  first materialisation when a worker has zero slots, and `SaveWorkerScheduleHandler` stages a
  `WorkerScheduleSaved` outbox event a worker consumer materialises off the API host. No migration.
- **Found**: 2026-09-30, onboarding the first real (beta) client — tenant «Салон Топаз», worker Алёна
  Матерн. Everything on the readiness screen was green except **«Слоты сгенерированы в пределах
  горизонта»**, and nothing the operator could click fixed it. Confirmed live and unblocked by hand
  (restarted `ago-calendar-worker`, which cut 464 slots immediately). This is the one part of today's
  onboarding friction that is a plain bug rather than a design question — see [[26-316-…]], [[26-317-…]],
  [[26-318-…]] for the other three.

## Root cause (verified live)

Availability is materialised **only** by `AvailabilityMaterializationJob` (`ago-calendar-worker`), a
`PeriodicTimer` loop with `Interval = 1 day` that "runs once at startup, then every 24h". The worker
pod had been up 23h; the worker's schedule was saved at 12:58 UTC, *after* the last daily tick — so the
first materialisation for it was ~24h away, and there were **zero** `events` rows for the worker in the
meantime. The readiness check `SlotsMaterialized` reads `HasFutureSlots`, which is false with zero rows.

The two console actions do **not** bootstrap it:
- **«Пересчёт» (recut)** re-cuts *existing* slots preserving bookings; with zero slots it has nothing
  to do, so it silently no-ops — exactly what the operator reported ("нажимаю Пересчёт, ничего").
- **«Слоты»** only *views* slots.

So a correctly configured worker shows "no slots" for up to 24h, and no operator action shortens it.
A real user would have no idea why the calendar is unbookable.

## Fix

Give materialisation an **immediate trigger** the moment its prerequisites are met, rather than relying
on the daily sweep for the first cut:
- Preferred: `SaveWorkerScheduleHandler` (and the working-hours/worker/service writes that complete the
  readiness chain) enqueue a materialise for that calendar — via the outbox/an integration event the
  worker consumes, so the API host still never runs the cut inline. The daily job stays as the backstop.
- And/or make **«Пересчёт» bootstrap** when there are no slots yet: with nothing to re-cut, run the
  first materialisation instead of no-opping, so the button an operator naturally reaches actually works.

Keep the daily job (it repairs drift and extends the horizon). The gap is only the *first* cut having
no path faster than a day.

## Done when

- [ ] Saving a worker schedule (with hours/service/active/published all in place) produces future slots
      within seconds, without waiting for the daily job or a pod restart.
- [ ] «Пересчёт» on a worker with zero materialised slots performs the first materialisation rather than
      no-opping (or the on-save path makes that state unreachable — decide during build).
- [ ] The readiness «Слоты сгенерированы в пределах горизонта» flips to green on its own after setup.
- [ ] Gates green; the trigger runs off the API host (outbox/event), not inline in the request.
