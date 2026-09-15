# 25-108 · Channel poller services crash the whole worker on a transient DB failure

- **Stage**: 25
- **Status**: done — fixed and merged (`ago-chat` [PR #310](https://github.com/golyakoff/ago-chat/pull/310)).
- **Depends on**: nothing
- **Found**: 2026-09-15, running `load/reports/2026-09-15-local-capacity-ramp.md`'s own memory-vs-CPU
  comparison run - `ago-chat-worker` restarted eight times in seconds under load, each time crash-
  looping straight back into the same failure.

## What is actually true

`MaxLongPollingService`/`TelegramLongPollingService.ExecuteAsync` (`adr/0089`'s own "identical
treatment" shape, one poll loop per active channel credential) calls `RefreshPollersAsync` in a loop -
a real database round trip (`IChannelCredentialRepository.GetAllActiveAsync`) - with no protection
beyond an `OperationCanceledException` catch scoped to shutdown. A transient failure there - live: a
`PostgresException` (`max_connections` under pressure) wrapped by EF Core's own execution strategy -
was unhandled, faulting `ExecuteTask`. `BackgroundService`'s own contract lets that fault propagate;
this host's `BackgroundServiceExceptionBehavior` was never set, so .NET's own default,
`StopHost`, turned **one bad refresh tick into the entire `Ago.Chat.Worker` process exiting** - not a
failed poll for one channel, every credential's own poll loop across every channel, gone with it.

**This is a local, isolated omission, not a systemic pattern** - `PollOneCredentialAsync`, the inner
per-credential poll loop in the same two files, already has exactly this resilience: its own final
`catch (Exception ex)` logs and backs off rather than propagating. `RefreshPollersAsync`'s own call site,
one level up, was the one place that resilience was missing - in both files identically, since both
were written to the same shape.

## Scope

- `ExecuteAsync` in both `MaxLongPollingService` and `TelegramLongPollingService`: wrap the
  `RefreshPollersAsync` call in its own `try`/`catch (Exception ex) when (ex is not
  OperationCanceledException)`, logging and continuing to the next refresh tick - the same shape
  `PollOneCredentialAsync`'s own inner loop already uses.
- A regression test proving the mechanism: `ExecuteAsync`'s own background `Task` must survive one
  failing `RefreshPollersAsync` call and keep retrying on the next tick, not fault permanently after
  the first failure - proven failing against the code above, passing after the fix.

## Out of scope

- **Every other `BackgroundService` in `Ago.Chat.Worker`** - a grep at the time this item was found
  turned up 40+ classes deriving from `BackgroundService` in that project alone (consumers, scheduled
  jobs). This item fixes the two demonstrated to share this exact gap (`adr/0089`'s own pairing); it
  does not claim the other 40+ are safe, only that auditing all of them is real, separate scope this
  item does not take on. Worth a dedicated audit as its own item if this class of bug is suspected
  elsewhere - not guessed at further here.
- Raising `postgres.max_connections` itself, or anything else about the load-testing overlay that
  surfaced this live - `load/reports/2026-09-15-local-capacity-ramp.md`'s own concern, not this item's.
- `BackgroundServiceExceptionBehavior` as a global host setting - deliberately not changed. Setting it
  to `Ignore` globally would also silence a genuinely fatal bug in some other service, turning a loud
  crash (which at least signals "something is wrong") into a permanently, silently broken consumer
  nobody notices. The per-service, per-call-site fix here keeps that signal for anything this item did
  not touch.

## Done when

- [x] A transient failure in `RefreshPollersAsync` no longer faults `ExecuteAsync` permanently - both
      `MaxLongPollingService` and `TelegramLongPollingService` log and retry on the next tick instead.
- [x] A test proves it - `ChannelPollerReapTests.
      RefreshPollersAsyncThrowsOnce_DoesNotFaultExecuteAsync_KeepsRetryingOnTheNextTick`, fails-before
      confirmed live (reverting the fix, the test's own call-count assertion failed, stuck at 1 for the
      whole window), restored from the staged fix, full suite re-run clean (3493/3493, 0 failed).
