# Fix: the connections gauge counts heartbeats, not connections

- **Stage**: 7
- **Status**: done
- **Depends on**: nothing — `ago-platform` only

## Goal

`ago.platform.realtime.connections` reports how many connections a node holds. Today it reports how
many times `RegisterAsync` has been called, which on an idle deployment climbs forever.

## How this was found

While investigating a report that an operator's own message did not appear in their console
(2026-08-25). The report turned out to have a different cause (`5-16`), and this metric — the one that should have
answered "is the operator's connection receiving anything" in a minute — is why it took an hour
instead.

Measured on the live deployment, which had no users on it:

| | |
|---|---|
| Gauge, 30 minutes apart | 564 → 2476 |
| Rise per minute | ~47, and growing |
| API log lines in 2 minutes | 10 |
| Connection entries in Redis | 13 |

## The mechanism

`RealtimeMetrics.ConnectionRegistered(nodeId)` increments a per-node counter that an
`ObservableGauge` reports, and `ConnectionUnregistered` decrements it. That pairing would be correct
if `RegisterAsync` were only called on connect. It is not:
`ConnectionHeartbeat.RefreshAllAsync` calls `registry.RegisterAsync(...)` **every ten seconds for
every tracked connection**, because that is how the TTL is extended — its own doc comment says so
plainly ("each call is the same idempotent 'extend the TTL' `RegisterAsync` already is for an
existing entry, so there is no separate 'refresh' operation to keep in sync with 'register'").

That design decision is fine. Counting a metric inside it is not. Thirteen tracked connections times
six heartbeat cycles a minute is about seventy-eight increments a minute against at most a handful of
real disconnects, so the value diverges upward and never returns.

The gauge's own description reads "Connections this platform's connection registry believes each node
currently holds." It does not, and has not since the heartbeat existed.

## Context to read first

`ago-platform/src/Ago.Platform.Realtime/RealtimeMetrics.cs` — the instrument, the counter and the two
internal methods. `ConnectionHeartbeat.cs` — the second caller, and the comment explaining why
refresh and register are deliberately the same operation. `RedisConnectionRegistry.RegisterAsync` —
where the increment is triggered from. `docs/architecture/nfr.md`'s observability requirements, which
name "connection count per node" as something that must be visible without a debugger.
`docs/backlog/7-02-metrics-instrumentation.md` — where this instrument came from.

## Scope

- Count connections, not registrations. The obvious fix is to increment where a connection is
  genuinely new rather than inside a call that doubles as a refresh — `LocalConnectionTracker` already
  knows the difference, since it holds exactly the set the gauge is supposed to describe, and an
  `ObservableGauge` reading that set's size directly needs no counter at all. Decide and state which
  shape is taken; the second removes a class of drift rather than fixing an instance of it.
- **A test that fails on the current behaviour**: several heartbeat cycles over a stable set of
  connections must not move the gauge. This is a unit-level test, and its absence is why a metric
  could be wrong for as long as the heartbeat has existed.
- Check the sibling instruments from `7-02` for the same shape — a metric written next to a mechanism
  that is called more often than it looks. Presence and node-set maintenance are the candidates.
- **A platform change**: `CHANGELOG.md` entry and a version bump, or CI republishes the old package
  and nothing downstream sees the fix.

## Out of scope

- Any dashboard or alert that reads this metric — `7-03` and `15-03`. They inherit a working value
  once this lands; nothing there needs changing for the wrong reason.
- The delivery-observability gap this investigation also exposed — `5-17`.
- Anything about connection *behaviour*. The registry, the heartbeat and the TTL are all working as
  designed; only the counting is wrong.

## Done when

- [x] The gauge equals the number of connections the node actually holds, checked against the
      registry's own entry count — see the Outcome's note on where that check was made.
- [x] A test proves repeated heartbeats over a stable connection set leave it unchanged.
- [x] The sibling instruments have been checked for the same mistake, with the result written down
      either way.
- [x] `CHANGELOG.md` and the package version are updated.

## Outcome

The second shape in Scope was taken: the gauge **reads the set it describes** instead of maintaining
a second number next to the calls that maintain the first. `LocalConnectionTracker` gains a `Count`,
`RealtimeMetrics`' `ObservableGauge` callback reads it at collection time, and
`RedisConnectionRegistry` no longer touches the metric at all — `ConnectionRegistered`,
`ConnectionUnregistered` and `NodeRemoved` are gone rather than moved. There is no longer a counter
that could drift, so this removes the class of defect, not the instance. It is also the shape
`ResilienceMetrics`' breaker-state gauge already uses (register a live handle, read it in the
callback), so the two gauges in the platform now work the same way.

The tracker learns which node it belongs to from the composition root:
`AddConnectionRegistry` builds it and calls the new public
`RealtimeMetrics.TrackNode(NodeId, LocalConnectionTracker)`. That is the only place that knows both
facts. The alternative — a required `NodeId` constructor parameter on `LocalConnectionTracker` — was
rejected because it is a breaking change to a published package for no gain here, and would have
broken `ago-chat`'s existing `new LocalConnectionTracker()` test call sites for a metrics reason.
No `ago-chat` change is needed: a host that calls `AddConnectionRegistry` picks the fix up by
restoring the new package.

**Fails-before, passes-after.** `RealtimeConnectionsGaugeTests`'
`HeartbeatCycles_OverAStableConnectionSet_LeaveTheGaugeAtTheRealConnectionCount`
(`ago-platform`, Integration.Tests) registers
three connections on one node, then runs the real `ConnectionHeartbeat` against the real
`RedisConnectionRegistry` on the Testcontainers Redis until fifteen refreshes have gone through
(awaited on the call count, not on wall clock). Against the code as it was: `Assert.Equal() Failure:
Values differ / Expected: 3 / Actual: 18` — the three real connections plus fifteen heartbeat
refreshes, exactly the mechanism this item describes. After the fix it passes. This is an
integration test rather than the unit test the Scope section assumed: the defect only exists in the
seam between the real registry and the real heartbeat, so a fake registry could not have reproduced
it — which is itself part of why it survived unnoticed.

The same test asserts the gauge against the registry's **own** entry count (`node:{id}:conns`
cardinality read straight off Redis) in the same breath, which is the first Done-when bullet made
repeatable in CI rather than eyeballed once on a live deployment. It was not additionally re-checked
against the running cluster, because that would have meant packing, rebuilding and deploying while
other Stage 7 work was in flight; the assertion it stands in for is exactly the one that was asked
for.

**Sibling instruments, checked, all four clean:**

| Instrument | Verdict |
|---|---|
| `ago.platform.resilience.circuit_breaker.state` | Already the right shape — reads Polly's live `CircuitBreakerStateProvider` in the callback, tracks nothing itself. |
| `ago.platform.resilience.bulkhead.rejections` | Counter incremented in Polly's `OnRejected`; a rejection is a genuine event, never a refresh. |
| `ago.platform.caching.redis.cache_access` | Counter, once per `RedisCache.GetAsync`; every call is a real access, and the counter's rate is what a dashboard reads. |
| `ago.platform.messaging.rabbitmq.consumer.*` / `...dead_lettered` | Counters/histogram at the handler-invocation boundary, once per delivery; a redelivery counting again is correct for "processing attempts". |

Presence and node-set maintenance — the two candidates this item named — have no instruments of
their own; they were only ever visible through this gauge, and `RemoveNodeAsync`'s
`NodeRemoved(nodeId)` was part of the same defect (it zeroed the gauge at the *start* of a drain,
while connections were still open). It is gone; the gauge now falls to zero as the connections
actually close.

**Package:** `CHANGELOG.md` `0.15.0` — a `### Fixed` entry for the gauge and an `### Added` entry for
`TrackNode`/`Count`. No ADR: the shape was a choice between two fixes for one defect, both stated
here and in the changelog, not a decision that changes a guarantee or deviates from a rule.

**Verified:** `dotnet format --verify-no-changes`, `build -c Release` (0 warnings), `test -c Release`
— 77 tests, all green.

## Note on what this does not invalidate

Stage 7's load report does not rest on this metric — checked. `2026-08-24-connection-storm.md` counted
connections from the load driver's own side ("300/300 connected") and memory from process metrics, not
from this gauge. Its numbers stand.

## Open questions

None.
