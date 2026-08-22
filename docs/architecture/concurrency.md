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
genuinely skipping each other's locked rows. Neither has a caller yet - the loop that ties claiming
a conversation to claiming an operator's capacity is `4-02`; mechanism B (the Redis alternative) is
`4-03`.

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
