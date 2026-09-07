# the flusher's final flush on shutdown has no test, because the one written for it is right half the time

- **Stage**: 23
- **Status**: done (2026-09-07), `ago-chat#215`. Test only — no production file changed.
- **Depends on**: nothing. `23-07` is merged; this is the one Done-when it could not close honestly.
- **Decision**: none needed. This is a defect in our own ability to prove something, not a product question.

## What is actually true

`23-07`'s Done-when says *"a pod restart mid-window loses at most the unflushed batch and never a
whole day"*. That is two claims.

**The second is covered and structural.** Rows in `site_widget_activity` are per `(site, day)` and
flushes *add* rather than replace, which `Flush_CalledTwiceForTheSameSiteAndDay_AddsRatherThanReplaces`
proves. A lost window costs that window and nothing before it.

**The first is not covered.** `WidgetActivityFlusherService` flushes once more after its loop ends —
deliberately, so an ordinary rolling deploy's graceful stop does not throw away up to a whole
`FlushInterval` of counts. Nothing exercises that line.

## Why it is not covered, which is the whole item

A test was written for it while landing `23-07` and **dropped rather than merged**:

```
Flusher_StoppedBeforeItsFirstTick_StillWritesWhatWasAccumulated
```

Start the service with a one-hour interval so the periodic tick provably never fires, record a load
and an open, stop it, and read the totals back. It behaves like this:

| Run | Result |
|---|---|
| Alone | passes, three times out of three |
| In a sixteen-test filtered subset | passes |
| In the full `Ago.Chat.Integration.Tests` project | **fails about half the time** |

**A test that is right half the time is worse than the gap it covers**, because it teaches people to
re-run CI. That is why it was dropped instead of merged, and it is why this item exists instead of a
line in a report.

## What the investigation already ruled out — start here, not from the beginning

- **Not a swallowed exception.** The production code catches a failing final flush on purpose (an
  orderly shutdown must not become a crash loop over a dashboard number), which makes "it failed" and
  "it never ran" look identical from outside. A capturing logger was added for exactly that: on the
  instrumented run the warning list was **empty**.
- **Not a failed write.** The same instrumented run queried the table directly and found the row:
  `loads=1 opens=1`, on the right day, for the right site.
- **Not stale binaries.** The restore-after-mutation was `touch`ed and rebuilt, and the mutation test
  reddened and greened as expected either side of it.
- **Not the `RoleAssignmentProjectionBackfillFixture` truncate.** That fixture does
  `TRUNCATE ... sites CASCADE`, which would cascade into `site_widget_activity` — but it runs against
  **its own container**, so it cannot reach the shared one.
- **The instrumented run passed.** Which is the unsatisfying part: the diagnostics have never yet been
  present on a failing run.

## Where to look next, in order

1. **Run the instrumented version until it fails**, rather than once. Everything above was learned from
   runs that happened to pass.
2. **Dapper's binder cache.** `WidgetActivityReadStore`'s static constructor registers the
   `DateOnly` handler, and Dapper caches a compiled parameter binder per SQL. Whether any path can
   compile a binder for this store's query before that registration is the one hypothesis with a
   mechanism behind it that has not been checked.
3. **Whether `BackgroundService.StopAsync` is being awaited to completion under thread-pool starvation**,
   which the full project produces and a filtered run does not.

## Done when

- [x] The final flush on shutdown has a test that passes in the full project, repeatedly — **at least
      ten consecutive full-project runs**, not one. Ten runs of the whole `Ago.Chat.Integration.Tests`
      project, unfiltered, 952 of 952 each, zero failures — the exact condition under which the
      dropped predecessor failed about half the time.
- [x] `23-07`'s first Done-when clause is honestly covered, or this item records why it cannot be and
      what stands instead. Covered, and by a task-completion guarantee rather than a wait:
      `StopAsync(CancellationToken.None)` can only return through the task that runs the final flush,
      because the token-tied half of its own `Task.WhenAny` never completes. The dropped predecessor
      passed a *bounded* token, which is exactly how it could return early and lose.
- [~] If the cause turns out to be a real race rather than a test artefact, it gets its own item —
      that would be a defect in the flusher, not in the test. **No item filed, and the reason is
      evidence rather than confidence.** One failure with this assertion's signature appeared in an
      ad-hoc fifty-iteration loop and could not be reproduced in sixty-one further runs; that loop
      left `testhost` processes alive between iterations, which no real run does. Against that: the
      mechanism is a completion guarantee with no timing window to lose, and ten full-project runs —
      the historically flaky condition — were clean. **No diagnostics were captured for that one run
      and none can be now**, so this is the weight of evidence, not a closed investigation. If it
      ever recurs, that recurrence is the item, and this box is where the first occurrence is
      written down so nobody has to rediscover it.

## Out of scope

- Making the flush *guaranteed*. It is best-effort by design and `docs/design/decisions.md` §3 already
  accepts losing an unflushed batch. This item is about proving the behaviour that exists, not
  strengthening it.
