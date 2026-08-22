# Concurrency model

This is the doc the project exists to justify. Every mechanism here must be visible in code,
tested, and measurable.

## Guarantees we make

| Guarantee | Scope | How |
|---|---|---|
| Ordering | Per conversation | Server-assigned `sequence`, partition key = `conversation_id`, single-flight per conversation on the consumer |
| No loss after ack | Per message | Ack sent only after the DB transaction commits (outbox in the same transaction) |
| At-least-once delivery | Broker path | Consumers deduplicate by `message_id` (inbox table / unique index) |
| Bounded memory | Per node | Every in-process queue is a **bounded** `Channel<T>`; a full channel means backpressure, never unbounded growth |
| Clean shutdown | Per node | `SIGTERM` -> stop accepting -> drain channels -> flush batch writer -> close connections, within the pod's `terminationGracePeriodSeconds` |

We explicitly do **not** guarantee global ordering across conversations, exactly-once delivery, or
ordering between a REST call and a hub message from the same client.

## In-process pipeline (Api)

```
hub method --> [bounded Channel<InboundMessage>] --> N pipeline workers --> [batch writer] --> Postgres
                     ^ backpressure                        |
                     +------- reject / slow the sender <----+
```

- `System.Threading.Channels` with `BoundedChannelFullMode.Wait` and a capacity from config.
- Pipeline workers are `BackgroundService`s; the worker count is configurable and load-tested, not guessed.
- **Batch writer**: accumulates up to `N` rows or `T` milliseconds, whichever comes first, then does
  one multi-row insert. This is the single highest-leverage throughput mechanism in the project and
  the one to have numbers for (per-row insert vs batch, at several concurrency levels).
- A caller waiting on the ack is completed via a `TaskCompletionSource` carried with the queued item.

**Shipped in `4-05`**: `ChannelMessagePipeline`/`MessagePipelineWorkerHost`/`ConversationSequencer`/
`BatchAccumulator`/`BatchFlusherService` (`Ago.Chat.Module.Pipeline`) plus `MessageBatchWriter`/
`InboundMessage` (`Ago.Chat.Infrastructure.Postgres.Pipeline` - `PersistenceBoundaryTests` forbids
Npgsql/EF Core outside `Infrastructure.Postgres`, so the one piece that actually opens a connection
lives there, not beside the rest of the pipeline in `Module`) are exactly this diagram, built for
real. Defaults (`MessagePipelineOptions`): 4 workers, 1000-capacity channel, 5s enqueue timeout,
50-row/50ms batch, 20s shutdown drain timeout - unmeasured starting points, Stage 7's job, same as
every other tuning knob in this stage.

`SendVisitorMessageHandler`/`SendOperatorMessageHandler` (`Ago.Chat.Application`) still run every
synchronous check they always did (rate limits, RBAC, body shape) and still return exactly the same
`Result<int>` a caller sees - only the write itself (conversation load, `AddVisitorMessage`/
`AddOperatorMessage`, outbox insert, `SaveChangesAsync`) moved off the hub call's own thread, into
`MessageBatchWriter`, batched. `IMessagePipeline` (`Ago.Chat.Application.Abstractions`) is the port;
`ChannelMessagePipeline` is its only implementation, registered once in `ChatModule` for every host
(only `Ago.Chat.Api` ever actually drains it - the same "registered everywhere, resolved where it
matters" shape `4-04`'s `OperatorPresencePublisher` established, needed here because `ChatModule`
cannot depend on `Ago.Chat.Api`).

`ConversationSequencer` is a ref-counted per-conversation gate (`ConcurrentDictionary<ConversationId,
Gate>`, `Gate` wrapping a `SemaphoreSlim` plus a ref count) - not the bare
`ConcurrentDictionary<ConversationId, SemaphoreSlim>` with opportunistic removal-on-release this
section originally implied, which has a real removal-vs-acquire race (found while designing this, not
from a failing test): removing an entry the instant its semaphore frees can race a new caller already
mid-`GetOrAdd` on that same instance, letting a third caller create and acquire a *different*
semaphore for the same conversation and defeat the guarantee entirely. The ref count makes "safe to
remove" exact - an entry exists only while genuinely in use, so the dictionary never grows unbounded
either.

Batching is proven with Postgres's own `xmin` system column, not an instrumentation hook: several
messages for different conversations, sent concurrently, land with the same `xmin` when one flush
covers all of them (`MessagePipelineTests.BatchWriter_ActuallyBatches...`). Shutdown drain is proven
live: messages already past `EnqueueAsync` when `ApplicationStopping` fires are still committed before
`MessagePipelineWorkerHost`/`BatchFlusherService` finish stopping - `ChannelMessagePipeline`'s
constructor completes the inbound channel on that signal (the same "register in the constructor, not
`ExecuteAsync`" lesson `3-06` learned), and the whole drain cascades through channel completion rather
than reacting to a cancellation token directly, so nothing already queued is aborted mid-flight.

## Per-conversation ordering under parallel consumers

Parallel consumers are required for throughput and destroy ordering by default. Approach:

1. Publish with `partition key = conversation_id`. Kafka gives ordering per partition natively;
   RabbitMQ gets consistent-hash routing to N queues, one consumer each. The abstraction exposes the
   key, which is exactly why the port carries a `PartitionKey` (`adr/0006`).
2. Inside a consumer, a `ConversationSequencer` keeps a `ConcurrentDictionary<ConversationId, Channel>`
   so two messages of one conversation are never processed concurrently even if they arrive on
   different threads. Entries are evicted on idle to bound memory.
3. Consumers still apply the `sequence` on write: an out-of-order or duplicate `sequence` is caught
   by the unique index `(conversation_id, sequence)`, making the database the last line of defence.

Test: `Ago.Chat.Concurrency.Tests` fires K messages from M threads into one conversation and asserts the
persisted sequence is a gap-free ascending run, repeated under stress.

## Operator assignment - the contended path

Multiple `Worker` replicas compete to assign waiting conversations to operators with limited
capacity. Two mechanisms, both implemented, compared, and written up:

- **A. `SELECT ... FOR UPDATE SKIP LOCKED`** over the waiting queue, batch-claimed inside a
  transaction. Default choice: no extra infrastructure, no lock-lease expiry problems, and the
  database is already the source of truth.
- **B. Distributed lock in Redis** per operator, kept as an alternative implementation behind the
  same port, to demonstrate the trade-off (fencing tokens, clock skew, lock expiry vs work duration).

Capacity is enforced with optimistic concurrency:
`UPDATE operators SET active_chats = active_chats + 1 WHERE id = @id AND active_chats < capacity`.
A row count of 0 means "lost the race", which is a normal outcome to retry, not an error to log at
`Error` level.

In-process, each Worker's assignment loop is single-threaded per shard, so intra-process contention
is designed away rather than locked away.

**Shipped in `4-01`**: `IOperatorCapacity`/`OperatorCapacityStore` (`Ago.Chat.Application.Abstractions`,
`Ago.Chat.Infrastructure.Postgres`) is exactly this statement - `capacity` compared against the same
row being updated, not a value read separately and passed as a parameter (the doc's own original
wording implied a separate read; the shipped version has no such read to race against, which is
strictly safer and is what the code actually does). `WaitingConversationClaimQuery`
(`Ago.Chat.Worker`) is mechanism A's claim half, proven with two concurrently open transactions
genuinely skipping each other's locked rows.

**Shipped in `4-02`**: `ConversationAssignmentJob` (`Ago.Chat.Worker`, `PeriodicTimer`, 2s interval,
20-conversation batch per site per tick - unmeasured starting points, Stage 7's job) is the loop that
ties `4-01`'s two halves together. Per site, per tick, one Postgres transaction: claim up to
`BatchSize` waiting conversations (`WaitingConversationClaimQuery`), then for each, select the
least-`active_chats`-first `Online` operator at that site with room (`AsNoTracking`, no lock - the
atomic claim right after it is what makes the decision safe, not a lock on the read) and attempt
`IOperatorCapacity.TryClaimAsync` through the *same* `AgoChatDbContext`, built on the claim's own
connection via `Database.UseTransactionAsync` - `OperatorCapacityStore` was refactored during `4-02`
specifically for this (`ExecuteSqlInterpolatedAsync` against an ambient transaction instead of a
standalone connection), because a capacity claim and the assignment it enables must commit
atomically: crash between the two under the original design and a slot leaks forever, invisible to
any future claim, with no assigned conversation to account for it. A conversation whose candidate
loses the capacity race, or whose whole batch hits a transaction-level deadlock (below), is simply
left `Waiting` - retried next tick, never a second candidate the same tick.

**A real deadlock risk found live, not anticipated by this doc's original design**: a batch that
assigns different claimed conversations to *different* operators holds more than one `operators` row
lock at once (each successful `TryClaimAsync`) until it commits. Two replicas' batches touching the
same site's operators in a different order can genuinely deadlock - Postgres detects the cycle and
aborts one side (`SqlState 40P01`). Handled exactly like every other "lost the race" outcome here:
caught per-site inside the tick, logged at `Debug`, retried next tick - one site's contention must
not stall every other site's batch in the same tick.

Both participants are notified through the same fan-out path `3-02` built:
`ConversationAssignedToOperator` (a new integration event, named differently from the domain event
`ConversationAssigned` - `Contracts`/`Domain` naming split established in `3-02` for the same
`MessageAdded`/`MessageAccepted` reason) carries `VisitorId`/`OperatorId` directly, so
`ConversationAssignmentFanoutConsumer`/`ResolveConversationAssignmentTargetsHandler` need no
conversation load at all (unlike message delivery's own resolve step) before calling
`INodeFanoutPublisher`. Proven end to end (`ConversationAssignmentFanoutEndToEndTests`): a real
`ConversationAssignmentJob` tick against real Postgres/RabbitMQ/Redis reaches both the visitor's and
the operator's own node.

**Shipped in `4-03`**: mechanism B, a per-operator `RedisDistributedLock`
(`Ago.Platform.Caching.Redis`, public and deliberately fail-closed - unlike `3-04`'s `RedisLock`,
which fails open, correctly, for cache-stampede protection). Both mechanisms now sit behind
`IAssignmentClaimer` (`Ago.Chat.Application.Abstractions`), chosen once at startup by
`AssignmentEngine:Mechanism` config (default `SkipLocked`) - `ConversationAssignmentJob` itself
knows nothing about either implementation, just runs the tick loop and calls the claimer.
`RedisLockAssignmentClaimer` does a plain, non-locking read of waiting conversations (no `SKIP
LOCKED` at all), then for each tries candidate operators in least-loaded order until one's lock is
free, attempting the capacity claim and the conversation assignment in one Postgres transaction so
a losing attempt's capacity claim rolls back with it.

**The lock does not, by itself, prevent a double-assignment race on the conversation row** - only
`SKIP LOCKED` does that structurally. Two replicas can both read the same waiting conversation and
attempt it through two different operators' locks at once; correctness rests on the `Conversation`
aggregate's own `xmin` optimistic-concurrency check catching the losing `SaveChangesAsync` - the
same "last line of defense" principle `data-model.md` already generalizes from the partitioned
`messages` unique index, not a gap patched after the fact. `adr/0021` compares both mechanisms in
full, including this finding and the real transaction-level deadlock risk mechanism A carries that
mechanism B's per-operator locking sidesteps by construction. Proven under the same real-concurrency
bar as mechanism A (`RedisLockAssignmentConcurrencyTests`) and fail-closed for real
(`RedisLockAssignmentContainerFailureTests`: a stopped Redis assigns nothing, never throws, never a
false-positive claim).

## Rules for every async code path

- `CancellationToken` accepted, honoured, and passed down. A loop without a token is a hang.
- No `.Result` / `.Wait()` / `.GetAwaiter().GetResult()`, and no `Task.Run` to fake async.
- No `lock` around `await`. Use `SemaphoreSlim` when mutual exclusion must span an await.
- Shared mutable state is `ConcurrentDictionary`, `Interlocked`, or immutable-and-replaced.
  A `Dictionary` reachable from two threads is a bug even if it "works".
- Fire-and-forget is forbidden. Background work belongs to a `BackgroundService` with a supervised
  lifetime, so failures surface instead of vanishing.
- Every `BackgroundService` catches, logs with context, and continues; an unobserved exception must
  not silently kill a consumer loop.
- Timers: `PeriodicTimer`, not `System.Timers.Timer`.

## Graceful shutdown

`IHostApplicationLifetime.ApplicationStopping` -> stop reading from the broker -> stop accepting new
hub messages (existing connections are told to reconnect) -> drain the pipeline channel -> flush the
batch writer -> commit and ack in-flight work -> dispose. Kubernetes `preStop` and
`terminationGracePeriodSeconds` are set to make this survivable, and Stage 7 verifies it by killing a
pod mid-load and asserting zero acknowledged-but-lost messages.

**`Ago.Chat.Api`'s connection half shipped in `3-06`**: `ConnectionDrainCoordinator`
(`Ago.Platform.Realtime`, generic - reused as-is by any product hub) registers on
`ApplicationStopping` in its constructor, not inside `ExecuteAsync` - `BackgroundService.StartAsync`
returns as soon as `ExecuteAsync` is scheduled, not once it has run, so registering there raced a
shutdown that started immediately after start (found by a real intermittent test failure under the
full suite, not by inspection). `StopAsync` then tells every connection this node owns to reconnect
(`ILocalConnectionDispatcher`, the same delivery path `3-02` built for messages, pushing `"Reconnect"`
instead of `"MessageReceived"`), removes this node's `IConnectionRegistry` entries, and waits up to
`DrainOptions.DrainTimeout` for connections to actually drop before letting the host stop.
`VisitorHub`/`OperatorHub` additionally reject a new connection outright (`Context.Abort()`) the
moment `DrainState.IsDraining` flips, closing the window between readiness going false and a new
connection still landing on this node. Live-verified against the local 3-replica cluster: a visitor
held one hub connection through a real `kubectl rollout restart deployment/ago-chat-api`, sent 25
messages at the sustained rate limit (`3-05`), was disconnected exactly once as its pod cycled,
reconnected and resumed via `lastKnownSequence`, and all 25 were confirmed present in the final
history - zero acknowledged-but-lost, one clean reconnect. Two more real bugs only this multi-replica
run could surface, both fixed in the same slice: each replica generated its own random JWT signing
key at startup (any token failed validation the instant a request landed on a different pod under
`least_conn` - see `edge.md`'s "no sticky sessions"), and a SignalR client that negotiates before
connecting needs the negotiate response and the transport upgrade to land on the same pod, which the
Gateway does not guarantee - `SkipNegotiation` + WebSockets-only transport removes the need for that
affinity entirely rather than trying to add it back.

## What we will measure (Stage 7)

Throughput and p50/p95/p99 for message ingest, end-to-end delivery, and assignment latency under a
waiting-queue backlog; the batch-size vs latency curve; behaviour at channel saturation; recovery
time after killing one Api replica and one Worker replica.
