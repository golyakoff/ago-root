# 25-112 · The flusher's shutdown-flush test failed once in CI

- **Stage**: 25
- **Depends on**: nothing
- **Status**: done (2026-09-16), test-only — `ago-chat#315`. Not reproduced despite deliberate
  attempts (a local loop, and re-running the actual failing GitHub Actions workflow); a second data
  point for `23-40`'s own honest-uncertainty box, not a resolved mechanism. Lands no production fix -
  instead, the test's own `NullLogger` was discarding the one signal (`ExecuteAsync`'s own logged
  warning on a swallowed final-flush failure) that would tell "the write never ran" apart from "the
  write threw", the exact gap `23-40` already named and never closed. A `CapturingLogger` closes it,
  so a third occurrence, if there is one, is evidence rather than another guess.
- **Found**: 2026-09-16, `ago-chat` CI run
  [35121261341](https://github.com/golyakoff/ago-chat/actions/runs/35121261341), on a PR
  (`fix/25-110-...`) that touches nothing in `WidgetActivityFlusherService`'s own file, nor its test,
  nor anything upstream of the site-caching fixture it shares - the queue-and-caching hosts this
  failure sits alongside were all otherwise green.

## What happened

`23-40`'s own item file names exactly this possibility and asks that it become its own item rather
than be folded back into that one - see its "Done when" box:

> If the cause turns out to be a real race rather than a test artefact, it gets its own item... If it
> ever recurs, that recurrence is the item, and this box is where the first occurrence is written down
> so nobody has to rediscover it.

This is that recurrence. `WidgetActivityFlusherServiceTests.
StopAsync_WithTheOnlyPossibleFlushBeingTheFinalOne_StillWritesTheAccumulatedCounts` failed in CI:

```
Assert.Equal() Failure: Values differ
Expected: 1
Actual:   0
```

- `Ago.Chat.Integration.Tests` as a whole: 1306/1307, one failure, this one.
- The identical full-project suite ran clean twice, independently, the same day, against the
  identical commit range this PR carries: once locally by the worker that built `25-110`, once again
  by the managing session verifying that report before opening the PR. Both showed 1307/1307.
- `23-40`'s own fix (`CancellationToken.None` on `StopAsync`, so the token-tied half of
  `BackgroundService.StopAsync`'s internal `Task.WhenAny` can never win the race and return before the
  final flush task itself completes) was verified against **ten consecutive full-project runs, unfiltered,
  952/952 each** before that item was closed - the exact "historically flaky condition" it names. This
  is the first observed failure since.

## Where to look next

`23-40`'s own item file already has a "Where to look next" section with three live hypotheses (Dapper's
binder cache and static-constructor ordering; whether a filtered run vs. the full project changes
anything about when `StopAsync` is actually awaited to completion; thread-pool starvation under a
busier machine) - read that item in full before starting, rather than re-deriving the same three
candidates from scratch. GitHub Actions' own runner is a different machine shape than either of this
item's ten verifying runs (a fresh container each time, shared with every other job in the same
workflow) - the CI environment itself is a fourth variable neither of `23-40`'s own investigations
had, and is worth naming explicitly as a candidate rather than assumed to behave like the local
Docker Desktop fleet `23-40` tested against.

## Done when

- [~] Reproduced deliberately (a loop, not waiting for another accidental CI failure) - in CI
      specifically, since that is the one environment this failure has now been seen in and the local
      fleet has not. **Not reproduced** - one deliberate CI rerun of the actual failing workflow came
      back clean (1307/1307); further reruns were not chased once their marginal cost (~10 CI minutes
      each) stopped being worth it against a rare, unreproduced event - the same call `23-40` made.
- [~] Root cause identified, or `23-40`'s own honest-uncertainty box is updated with a second data
      point and a decision about whether a third occurrence gets a different response than a fourth
      item. **Not identified.** `BackgroundService`'s actual `net10.0` source was traced by hand
      (`StartAsync` dispatches via `Task.Run`, `StopAsync` awaits `_executeTask.WaitAsync(token, ...)`
      - not the `Task.WhenAny` shape `23-40`'s own comment described, which was the .NET Framework
      compat path) - `CancellationToken.None`'s guarantee holds under either mechanism, so `23-40`'s
      fix needed no change, only its explanation did. This is a second data point for that item's own
      box, recorded here rather than reopening it - a third occurrence stays a documentation update,
      a fourth escalates to a dedicated investigation with a captured warning in hand.
- [x] If a real race is found in `WidgetActivityFlusherService`/`BackgroundService.StopAsync`'s own
      contract, the fix lands with a fails-before test reproducing it, not just a stronger assertion.
      **N/A - no race found.** Landed instead: the test's own blind spot is closed - it used
      `NullLogger`, discarding the exact signal (`ExecuteAsync`'s own logged warning on a swallowed
      final-flush failure) that would tell "the write never ran" apart from "the write threw", which
      is precisely the gap `23-40`'s own text names ("no diagnostics were captured... and none can be
      now"). A `CapturingLogger` (`ago-chat#315`) surfaces any logged warning inline in the assertion
      failure message, proven to work via a controlled fault injection (reverted before commit) - the
      next recurrence, if any, is evidence instead of another entry in this box.
