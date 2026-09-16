# 25-112 · The flusher's shutdown-flush test failed once in CI

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
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

- [ ] Reproduced deliberately (a loop, not waiting for another accidental CI failure) - in CI
      specifically, since that is the one environment this failure has now been seen in and the local
      fleet has not.
- [ ] Root cause identified, or `23-40`'s own honest-uncertainty box is updated with a second data
      point and a decision about whether a third occurrence gets a different response than a fourth
      item.
- [ ] If a real race is found in `WidgetActivityFlusherService`/`BackgroundService.StopAsync`'s own
      contract, the fix lands with a fails-before test reproducing it, not just a stronger assertion
      on the existing one.
