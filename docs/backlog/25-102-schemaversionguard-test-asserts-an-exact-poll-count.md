# 25-102 · `SchemaVersionGuardTests` asserts an exact poll count under a tight, real-time clock

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: `dotnet
  format`/`build` clean, full `ago-chat` suite re-run at 3491/3491.
- **Depends on**: nothing
- **Found**: 2026-09-14, `25-101`'s own full-suite verification run — the worker's own full
  `Ago.Chat.Integration.Tests` run failed once, on a test `25-101`'s own diff never touches. Confirmed
  unrelated: `git status` showed `SchemaVersionGuardTests.cs`/`SchemaVersionGuard.cs` untouched by that
  change, and the same test passed cleanly (5/5) filtered to run alone, isolated from the heavy
  `Concurrency.Tests` load that ran immediately before it in the full-assembly order. The managing
  session's own later full-suite re-run (3488/3488) did not reproduce it — consistent with a rare,
  load-dependent timing flake rather than an always-reproducible bug.

## What is actually true

`SchemaVersionGuardTests.WhenTheSchemaCatchesUpWhileWaiting_ItProceeds`
(`tests/Ago.Chat.Integration.Tests/SchemaVersionGuardTests.cs:49`) drives `SchemaVersionGuard`'s own
wait-then-refuse loop with `Impatient` options — a 300ms `WaitTimeout` and a 20ms `PollInterval` — and
asserts `Assert.Equal(3, looks)`: the guard must have polled its status delegate **exactly** three
times before the schema reports current.

That number is real under ideal scheduling (20ms × 3 well inside 300ms), but the test has no margin
for the host being busy. Under real load — this test ran in `Ago.Chat.Integration.Tests` immediately
after the ~2.5-minute `Concurrency.Tests` project, on a Docker host also running this project's own
live k8s cluster continuously — a delayed poll can push the guard past its 300ms `WaitTimeout` before
a third check happens (turning success into `SchemaOutOfDateException`), or the scheduler can let an
extra poll slip in before the delegate's own `looks < 3` flips, changing the exact count without
changing the outcome the test actually cares about (does it eventually proceed once the schema catches
up).

## Why this is worth its own number

This is the fourth instance this evening of a test whose own construction makes it order- or
load-sensitive (`25-81`: a shared Mono.Cecil resolver; `25-92`: a shared hardcoded timestamp; `25-99`:
a global Dapper type-handler registration; `25-97`: two independent `UtcNow` reads that could straddle
a second boundary) — but a fifth, genuinely different mechanism: this one is not shared mutable state
at all, it is a **real-time assertion with no slack**, tripped by real scheduling delay rather than by
another test's side effect. Folding it into any of those four closed items would misrepresent what
each one's own fix actually covers.

## Scope

- Decide the fix shape: assert the *outcome* (`status.IsCurrent`, the schema was eventually seen as
  current) and a **loose bound** on `looks` (e.g. `>= 3`, since fewer than 3 would mean it stopped
  polling before the delegate caught up) rather than an exact count that assumes zero scheduling
  jitter; or widen `Impatient`'s own timeout/interval ratio to buy more margin without changing what
  the test demonstrates; or both. This item does not presuppose which - state what was chosen and why.
- Check `WhenTheSchemaIsAlreadyCurrent_ItReturnsWithoutWaiting`'s own `Assert.Equal(1, looks)` and
  `WhenTheSchemaNeverCatchesUp_ItThrowsAndNamesThePendingMigrations` for the identical shape of
  fragility while in the file - the first asserts a single, unwaited poll (no timing to race, likely
  fine) and the third drives a delegate that never returns `Current()` at all (no scheduling race
  possible either), but confirm rather than assume, and name plainly whether either needs the same
  treatment.

## Done when

- [x] `WhenTheSchemaCatchesUpWhileWaiting_ItProceeds` no longer requires zero scheduling jitter to
      pass. **Chosen fix: widen the timeout margin, not loosen the assertion** — a new
      `PatientlyWaiting` options constant (30s `WaitTimeout`, same 20ms `PollInterval`), used only by
      this one test. `Assert.Equal(3, looks)` stays exact, because the fake delegate's own call count
      (not wall-clock time) decides when it reports current — the timeout only had to stop being the
      thing racing against real scheduling delay. Proven with a real, temporary 150ms delay injected
      into the fake delegate (reverted before committing): failed against the old `Impatient` config
      exactly the way `25-101`'s own log showed (`SchemaOutOfDateException` after 0.3s), passed
      against the fixed `PatientlyWaiting` config with the identical delayed delegate (554ms).
- [x] The other two tests in the same file are checked for the identical fragility — **and a third,
      not named in this item's own Scope, was checked too** (`WithAZeroWaitTimeout_ItStillInspectsOnce`).
      **Neither needed a fix.** Confirmed by reading `SchemaVersionGuard.EnsureCurrentAsync` directly
      rather than assumed: the first inspect happens once, unconditionally, before the wait loop's own
      condition is ever evaluated. `WhenTheSchemaIsAlreadyCurrent_ItReturnsWithoutWaiting`'s delegate
      always reports current on that first call, so the loop is never entered at all.
      `WithAZeroWaitTimeout_ItStillInspectsOnce`'s zero `WaitTimeout` makes the loop's own
      `started.Elapsed < options.WaitTimeout` false on its first evaluation regardless of how much real
      time the first inspect itself took. Neither count can be perturbed by scheduling delay.
