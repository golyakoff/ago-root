# RabbitMqConnection.DisposeAsync throws on a slow broker, and leaks its lock when it does

- **Stage**: 17
- **Status**: done (2026-09-03)
- **Found**: 2026-09-03

## Found by CI, on a change that could not have caused it

`ago-chat`'s CI failed on a **doc-only** pull request — one comment line — with:

```
System.Threading.Tasks.TaskCanceledException : A task was canceled.
   at RabbitMQ.Client.Impl.MainSession.SetSessionClosingAsync(...)
   at RabbitMQ.Client.Framing.Connection.CloseAsync(ShutdownEventArgs reason, Boolean abort, TimeSpan timeout)
   at RabbitMQ.Client.Framing.AutorecoveringConnection.DisposeAsync()
   at Ago.Platform.Messaging.RabbitMq.RabbitMqConnection.DisposeAsync()
   at UnreadCounterShutdownTests.KillingTheConsumerMidBatch_...  line 112
```

Line 112 is **the scenario, not the teardown** — the test kills a consumer mid-batch by disposing its connection. So what threw is the thing under test's own shutdown path.

## The defect

```csharp
public async ValueTask DisposeAsync()
{
    if (_connection is not null)
    {
        await _connection.DisposeAsync();
    }

    _lock.Dispose();
}
```

Two problems in six lines.

**Disposal is not best-effort.** The client's `DisposeAsync` performs a *graceful* close — a handshake with the broker, which can be cancelled or time out. `CloseAsync` takes an `abort` flag precisely so a caller can say "go away regardless"; nothing here uses it. So a host shutting down while the broker is slow, restarting, or gone **throws out of `DisposeAsync`** — and an exception during shutdown is noise that hides the reason the process was stopping in the first place. `concurrency.md` treats shutdown as a first-class concern; this is the adapter that decides whether it is clean.

**And the lock leaks when it does.** `_lock.Dispose()` sits after the `await`. On the throwing path it never runs.

## Not a flake, or not only one

CI history: every recent `ago-chat` run is green and this is the first failure. So the test is not chronically flaky — it caught a rare condition, which is what a shutdown test is for. A worker separately saw a *different* concurrency test deadlock locally the same day, under load right after a cold Docker start; both point at contention rather than at the changes under test.

Treating this as "rerun and move on" is the failure mode worth naming: the rerun unblocks a doc-only PR, and the finding stays true.

## What this must produce

- **`DisposeAsync` does not throw.** Whatever the broker does, disposal completes — abort rather than close, or catch and swallow with a reason, argued either way.
- **The lock is released on every path**, including the throwing one.
- A test that proves it: dispose against an unreachable or wedged broker and assert no exception escapes. That is the check that would have caught this without waiting for a loaded CI runner.

## Done when

- [x] Disposing a connection whose broker is gone completes without throwing — proven by making the broker gone, not by reading the code. — against a paused Testcontainers broker, and shown failing first with this item's own stack trace verbatim.
- [x] The lock is disposed on the failure path, proven the same way. — a `SemaphoreSlim` exposes no "am I disposed"; a `WaitAsync()` throwing `ObjectDisposedException` is the only observable proof, and it was shown absent before the fix.
- [x] `resilience.md` says what disposal guarantees, since it currently says nothing about shutdown at all. — a new **Shutdown** section, added with this item.

## Context

`ago-platform`, `Ago.Platform.Messaging.RabbitMq`. Found 2026-09-03 by CI on `ago-chat#155`; that PR is doc-only and its rerun is unrelated to this fix.

## Outcome

Done 2026-09-03, `ago-platform#43`, released as `0.19.0`.

**This item's own diagnosis was half wrong, and finding that out is most of what the work was.** The
text above says the client performs a *graceful* close and that nothing uses the `abort` flag. Reading
RabbitMQ.Client 7.2.2 rather than assuming: `Connection.DisposeAsync` already takes the abort path. The
real defect is one await inside that path — `MainSession.SetSessionClosingAsync`, reached via
`Connection.CloseAsync` — which sits **outside every try/catch in the client itself**, so a timeout
escapes regardless of the flag. The client's own guarantee is incomplete, which is why the adapter
absorbs it at the boundary the platform owns rather than switching a flag that was already set.

**"Pause the broker, then dispose" does not reproduce it.** An idle connection, an idle channel, a
connection with an idle consumer, concurrent racing calls — all completed cleanly, repeatedly. What
reproduces it is this item's own named scenario taken literally: a competing consumer with deliveries
genuinely in flight, blocked inside its handler, when the broker stops answering. The client then has
dispatch work to reconcile while the close handshake goes nowhere. Anyone tempted to call the original
CI failure a flake would have had to build that scenario to disprove it.

**Two things deliberately not done here.** `RabbitMqEventPublisher.DisposeAsync` had the identical
six-line shape around an `IChannel` and gets the same fix, but on code shape and the same documented
client mechanism — not an independently reproduced failure. The `CHANGELOG` says so rather than
implying it was proven. And a pre-existing race was found and left: disposing a `SemaphoreSlim` while
another thread is blocked in `WaitAsync()` neither unblocks nor faults that waiter, it hangs. Different
promise, so it does not get folded in here.

`ILogger<T>` became a required constructor parameter, matching every other adapter in the solution
rather than being the one exception with an optional `NullLogger` default. Source-breaking for a direct
`new`, which only this repository's own tests do — recorded under `### Changed` in the `CHANGELOG`.

**Not yet delivered to the products.** `ago-chat` and `ago-calendar` still pin `0.18.0`; a merged
package is not a delivered one until those pins move, and that waits for `22-05` to stop holding
`Directory.Packages.props` in `ago-calendar`.
