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

## Channel pollers - multi-replica by construction, contended per credential (`14-16`/`adr/0089`)

Every other section on this page is true of every `Worker` replica running the same code. This one
was not, silently, until `14-16`: `TelegramLongPollingService` and `MaxLongPollingService`
(`Ago.Chat.Worker`) each keep one poll loop per active `ChannelCredential`, and neither provider
tolerates two processes calling its own `getUpdates`-shaped endpoint for the same bot token at once -
Telegram answers the second with `409 Conflict`. Nothing coordinated which process polled which
credential; `replicas: 1` hid the defect rather than preventing it, and every rolling update still
produced a transient `409` because the old and new pod briefly overlapped.

**Ownership of a poll loop is claimed per `ChannelCredentialId`, by a session-scoped PostgreSQL
advisory lock** (`pg_try_advisory_lock`/`pg_advisory_unlock`, `adr/0089`) - held for the loop's life,
released explicitly on clean shutdown, and released by PostgreSQL itself when the holding session
ends otherwise (crash, kill, node loss). No TTL, no renewal, no heartbeat: takeover is the next
process's next acquire attempt, not a recovery procedure. The key is the *credential*, not a global
"poller leader" role, which is what turns this from a restriction back into the ordinary claim above:
several `Worker` replicas share the fleet of bots between them, each polling whatever credentials it
currently holds the lock for. **The exception is real but temporary by construction** - once every
credential's lock is contended fairly across replicas, "multiple `Worker` replicas compete" is true
of this path too, just contended differently (one lock per credential rather than `SKIP LOCKED` over
a shared queue) and for a different reason (an external provider's own single-poller constraint,
not this system's own capacity model).

One connection per `Worker` process, not per credential, is held open outside `NpgsqlDataSource`'s
own pooling for exactly this purpose (`PostgresChannelPollerOwnership`,
`Ago.Chat.Infrastructure.Postgres`) - many advisory locks can live on one session, and a session
returned to the pool has every lock it held reset by Npgsql, which is why this one connection is
never disposed until the process itself stops. `NpgsqlConnection` is not safe for concurrent use, so
every acquire/verify/release against it is serialised through the adapter's own gate, the same
`SemaphoreSlim`-around-shared-state shape `_pollers`/`_gate` already use in both poller classes.

**Advisory locks carry no schema and are invisible to anyone reading the database structurally** -
they exist only as rows in `pg_locks` for as long as a session holds one, visible with
`SELECT locktype, classid, objid, pid FROM pg_locks WHERE locktype = 'advisory'` against a live
connection, and nowhere else. A coordination mechanism nobody can find in the schema is one that gets
broken by accident by someone who does not know to look - `adr/0089` requires this stated plainly for
exactly that reason.

The half-open-connection case is the accepted, bounded weak spot: if a holder's TCP session
black-holes rather than closing cleanly, that process can believe it still owns a lock PostgreSQL has
already released. Each poll iteration verifies the lease is still backed by a live connection before
trusting it (`IChannelPollerLease.VerifyStillHeldAsync`) - a real round trip, not a re-acquire, since
`pg_try_advisory_lock` is re-entrant within one session and would trivially "succeed" again regardless
of whether anything is wrong. A broken connection surfaces there as an exception and stops that
credential's loop, which the next `RefreshPollersAsync` tick retries from scratch. This bounds the
window to roughly one poll iteration's worth of staleness; it does not eliminate it, which is why the
ordinary idempotency defences below are unchanged rather than treated as redundant.

**"Is the connection live" alone is not sufficient, and was found insufficient by review before it
shipped.** `PostgresChannelPollerOwnership` holds one connection for the whole process, and
`EnsureConnectionAsync` replaces a dead one with a fresh one the moment *any* credential's next
acquire attempt discovers it - including a credential that has nothing to do with the lease being
checked. A lease granted on the old session would see the new one open and wrongly report itself
still valid, even though its own lock died with the old session and was never re-acquired on the new
one. Each lease therefore also carries the session *generation* it was granted under
(`PostgresChannelPollerOwnership._generation`, bumped only when a new physical connection is actually
opened); `VerifyStillHeldAsync` and the release path both compare the lease's generation against the
current one first; a mismatch is treated exactly like a dead connection - and, for release
specifically, a stale lease's own unlock is skipped entirely rather than risking releasing a
different, currently-valid lease for the same credential that has since been granted on the newer
session. `ChannelPollerOwnershipConcurrencyTests` reproduces the exact sequence
(`SessionReplacedUnderALiveLease_MakesTheStaleLeaseDetectable`,
`DisposingAStaleLease_DoesNotRevokeAFreshLeaseForTheSameCredential`).

**How long takeover actually takes, as a number rather than "soon".** Every path back to polling runs
through `RefreshPollersAsync`'s reap-and-retry tick, so the bound is one tick —
`CredentialRefreshIntervalSeconds`, **30 seconds** by default, and the same default in both poller
services. On a clean stop the previous holder has already released its lock explicitly, so the next
tick is the whole delay. On a crash or node loss nothing releases anything: the lock survives until
PostgreSQL reaps the session, and the bound becomes that reap plus one tick. Telegram and MAX both
queue undelivered updates meanwhile, so this is delivery latency, not loss. If a deployment ever needs
faster takeover, that interval is the one knob — lower it, and pay for it in credential-repository
reads per tick.

**This lock reduces the probability of a double poller. It is not permitted to become the only thing
preventing duplicate messages**, and it has not: `ExternalMessageId`'s mapping to `ClientMessageId`
and the unique index on `(conversation_id, client_message_id, site_id)` are exactly as they were
before `14-16` - CLAUDE.md rule 5 (at-least-once, consumers idempotent) applies here unchanged, the
lock is a latency and correctness-under-normal-operation improvement layered on top of it, not a
replacement for it.

**The `bigint` key.** Advisory locks take a signed 64-bit key; `ChannelCredentialId` is a UUID.
`AdvisoryLockKey.For` (`Ago.Chat.Infrastructure.Postgres`) derives it via SHA-256 over the id's raw
bytes - deterministic across processes and runs, unlike `object.GetHashCode`, which .NET randomises
per process and would silently defeat the whole mechanism. A collision between two different
credentials is negligible at 64 bits and this system's scale but not zero, and a silent one means one
bot never polls - a bad enough failure mode that `adr/0089` requires it be observable:
`PostgresChannelPollerOwnership` records which credential it last computed each key for and logs at
`Critical`, naming both credential ids and the shared key, the moment one process itself computes the
same key for two different credentials. This does not catch every collision (only ones the same
process observes both sides of), but it is strictly better than never checking.

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

**The release half was missing until `6-09`, and this document did not notice.** The claim above was
built in `4-01`, proven under contention, and written up here - while the only thing that ever
executed its mirror image (`active_chats - 1`) was `4-04`'s bulk "this operator's last connection
anywhere dropped, redistribute their whole load" sweep. Closing a conversation, the ordinary way an
assignment ends, released nothing, so `active_chats` was a monotonically-increasing counter under
exactly the traffic pattern the product is for. Found by running `7-04`'s `assignment-contention`
scenario (`load/reports/2026-08-24-assignment-contention.md`: 51/150 assigned, then a flat plateau
for 210 s while 49 closes succeeded), not by inspection - the mechanism was correct and the
lifecycle around it was not, which is the failure mode a page like this one is least able to catch
by re-reading itself.

**Shipped in `6-09`**: `Conversation.HoldsCapacityClaim` (`Ago.Chat.Domain`) is the receipt for one
slot, set only by the two `IAssignmentClaimer` implementations in the same transaction as the
`TryClaimAsync` that took it, and consumed by `Close`/`ReleaseToQueue` in the same
`SaveChangesAsync` as the state transition itself. `CloseConversationHandler` releases when - and
only when - that consumption happened, and `OperatorConversationReleaser` now does the same per
conversation instead of assuming every assignment held a slot. The receipt exists because the two
ways a conversation becomes `Assigned` are genuinely asymmetric: the engine claims a slot first,
while `AssignConversationHandler` (behind `OperatorHub.JoinConversationAsync`) is capacity-blind end
to end - `adr/0033` records why that asymmetry was preserved rather than removed by making manual
assignment claim too. The invariant to hold any future change to: **`active_chats` equals the number
of conversations currently `Assigned` to that operator that hold a claim** - asserted exactly, not as
a range, by `CloseConversationCapacityConcurrencyTests` with real closes racing real assignment ticks
against real Postgres.

**`23-05` added the exception, and it is an exception to the rule rather than a hole in it.** A
conversation nobody has taken for longer than its own site's `assignment_penalty_seconds` is assigned
to the least-active `Online` operator **with the capacity comparison dropped** — through `23-04`'s
compare-free `ClaimAsync`, never `TryClaimAsync`, which would refuse by design. So `active_chats` may
exceed `capacity`, deliberately, and the invariant above still holds exactly: it counts conversations
holding a claim, and this path takes a claim like any other. What changes is not the accounting but
who may exceed the ceiling, and why.

Three properties keep it an exception rather than a second, laxer engine:

- **The period is read inside the claimer's own transaction**, never from the site-settings cache
  (`caching.md`). It is configuration a write decision depends on.
- **Both implementations have it.** `SkipLockedAssignmentClaimer` and `RedisLockAssignmentClaimer`
  implement one contract, and one having a second pass the other lacks would make the engine's
  behaviour depend on which lock strategy a deployment runs. Fourteen mirrored concurrency tests hold
  them to identical outcomes. The Redis-lock pass takes **no lock**, and that asymmetry is in mechanism
  only: a compare-free claim has no race for a lock to arbitrate, so correctness rests on the
  conversation's own `xmin`, exactly as that class's first pass already documents for itself.
- **`Online` still gates it.** An `Offline` or `Away` operator is never selected — inherited from the
  existing predicate with only the capacity clause removed, so no second `Online` literal exists to
  drift. With nobody online, nothing is assigned at any age; that case is `14-04`'s auto-reply and is
  untouched.

The one residual, stated rather than designed away: the release is issued *after* the close commits,
so a process death in that window leaks exactly one slot. Releasing before the commit would be worse -
a save that then loses on `xmin` would leave the conversation assigned with its slot already handed
back, and the operator over-subscribable for the rest of that slot's life. Making the window vanish
would mean driving the release from the `ConversationEnded` outbox event in `Ago.Chat.Worker`, at the
cost of freeing the slot only after the dispatcher and broker hop; `adr/0033` weighs both. `6-10`
added exactly one more way into that same residual - a release that loses a Postgres deadlock five
times running - and no new kind of residual; see the lock-order section below.

**Shipped in `18-06`**: a third releaser, alongside `CloseConversationHandler` and
`OperatorConversationReleaser` above - `AutoCloseInactiveConversationsJob` (`Ago.Chat.Worker`,
`PeriodicTimer`/`BackgroundService`, the same shape as `ConversationAssignmentJob` and `4-04`'s
disconnect sweep) closes an `Assigned` conversation nobody has touched inside its per-channel-kind
inactivity window, through `AutoCloseConversationHandler` - a second, system-triggered caller of
`Conversation.Close()` that shares `CloseConversationHandler`'s own release-strictly-after-save
ordering rather than re-deriving it. Its own candidate scan
(`AutoCloseInactiveConversationsQuery`) is a plain, unlocked `SELECT`, deliberately not a claim: unlike
`WaitingConversationClaimQuery`'s `FOR UPDATE SKIP LOCKED`, there is nothing to race for here, because
the actual state transition is gated downstream by the same `xmin` optimistic-concurrency check every
other write to this aggregate already relies on. A conversation the scan named that a message, an
operator's own close, or `4-04`'s disconnect release moved on from by the time the job reaches it is
simply not `Assigned` any more when `AutoCloseConversationHandler` re-reads it - refused by its own
explicit state guard (not by `Conversation.Close()`, which only refuses an already-`Closed` row; see
that handler's own remarks on why the guard has to be explicit here, unlike `CloseConversationHandler`,
which gets the same protection for free from its `OperatorId` comparison) - and left for the next
cycle to re-evaluate against fresh data, the identical "lost the race, not an error" shape this
section already gives a capacity claim that loses.

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

### The lock order on `operators`, and who absorbs the cycle (`6-10`)

**There is no global lock order, deliberately, and this is the record of that.** Both write paths
touch exactly one table under lock - `operators` - and they take it very differently:

| Path | `operators` rows locked | Order | Held for |
|---|---|---|---|
| `SkipLockedAssignmentClaimer` / `RedisLockAssignmentClaimer` (`TryClaimAsync`) | **several**, one per operator the batch assigned to | least-`active_chats`-first, so it depends on who had room at that instant - genuinely varies between batches | the rest of the batch transaction |
| `CloseConversationHandler` (`ReleaseAsync`) | **exactly one** | n/a - one row has no order | one statement, no transaction of its own |
| `OperatorConversationReleaser` (`ReleaseAsync`, `4-04`) | **exactly one** (one operator's sweep) | n/a | the sweep's transaction |

Only the first row of that table can invert against itself, and it is the only one that can start a
cycle. **The close cannot fix this by locking in a different order, because it takes one row.**

That matters because `6-09` made the close a *participant* in the engine's pre-existing cycle without
being able to cause it. `6-10` reproduced it deliberately and captured the graph (verbatim in
`docs/backlog/6-10-close-and-assign-deadlock-on-operator-capacity.md`); the mechanism is worth stating
here because it is not obvious from the source:

> Before a statement waits for the transaction that currently owns a row version, it takes a
> heavyweight **tuple lock** on that tuple - Postgres's FIFO queue for would-be updaters of one row.
> A single-row `UPDATE` in its own implicit transaction therefore *does* hold something while it
> waits, even though it owns no row lock, and an assignment batch already holding a different
> `operators` row can queue behind it. The cycle runs through a statement that had no locks of its own
> to create it, and Postgres aborts whichever process ran the deadlock check first - repeatedly the
> innocent release.

The captured graphs are unambiguous on two points that rule out the obvious wrong story: every wait is
on `operators` (`relation 16396`, resolved against the live container, and the only relation oid
anywhere in the log), and every participating statement is `active_chats + 1` or `active_chats - 1`.
There is no `conversations`↔`operators` ordering inversion; `conversations` is not in the graph.

**The decision, `adr/0037`: the release absorbs it, the engine is not changed.**
`OperatorCapacityStore.ReleaseAsync` retries its single statement on `40P01`, bounded at 5 attempts
with a jittered backoff, and **only when it owns no caller transaction** - inside one (the `4-04`
sweep) the deadlock has already aborted the transaction, so the retry unit is the caller's, and its
caller is a broker consumer whose delivery is redelivered. A `40P01` that survives becomes
`OperatorCapacityContentionException` at the port boundary (`Ago.Chat.Application.Abstractions`, the
same translation `6-08` gave `ConversationConcurrencyConflictException`); `CloseConversationHandler`
catches it, **keeps the close successful** - it already committed - logs at `Warning` and counts
`ago.chat.assignment.capacity_release_deadlocks{outcome="abandoned"}`. The residual is the one
`adr/0033` already accepts: one leaked slot, recovered by the disconnect sweep. **An operator never
sees `40P01` for pressing "close".**

Giving the engine a canonical order is the root fix and is deliberately deferred - it means either
pre-locking every online operator per batch (serialising assignment across replicas) or restructuring
`4-02`'s batch to decide in memory and apply one grouped update per operator in id order. Both are
performance changes this project may not merge without a load run behind them. `adr/0037` weighs both.

The rule for anyone adding a third writer to `operators`: **take one row, in no transaction, or take
many rows and own the retry.** `Ago.Chat.Concurrency.Tests` enforces the consequence rather than the
rule - `ConcurrencyTestFixture` runs Postgres with `deadlock_timeout=10ms` and `log_lock_waits=on`, and
`ClosesStormingAssignmentBatches_NeverSurfaceADeadlockAndNeverCorruptTheCount` runs a sustained storm
that asserts no close escapes with an exception, that the exact claim/assignment invariant survives,
and that Postgres genuinely detected deadlocks during the run, so a quiet run cannot pass vacuously.

**Shipped in `18-02`: a fourth writer, and a third branch of the rule above.** `TransferConversationHandler`
takes two `operators` rows - the source being released, the target being claimed - inside one
`IUnitOfWork` transaction, the codebase's first explicit-transaction port (`adr/0075`). Unlike the
engine's batches, a transfer always knows both rows before it starts, so it does not have to accept a
data-dependent order the way `4-02`'s batch does: it takes "many rows, own the retry" but with a
**fixed** order instead - whichever operator id sorts smaller is touched first, regardless of transfer
direction - which rules out a transfer inverting against an opposite-direction transfer of the same two
operators. It remains a plain participant in the engine's own accepted, data-dependent cycle above
(`adr/0037`) and absorbs that the same way: the whole transaction retries, 5 attempts, `Random 4-16ms
x attempt` jittered backoff, matching `ReleaseAsync`'s own proven bound - revised up from an initial
guess of 2 after `TransferringRacesTheAssignmentEngine_NeverCorruptsCapacityOrDropsTheConversation`
measured a bare single retry losing every transfer under a real storm. On exhausting its attempts the
handler returns a clean `Result` failure rather than throwing - **an operator never sees `40P01` for
pressing "transfer"**, the same guarantee `CloseConversationHandler` gives above, reached the opposite
way: nothing here ever partially commits, so there is no already-succeeded outcome to protect on the
way out, unlike the close's leaked-slot residual. See `adr/0075` for the full reasoning, including a
named gap in one concurrency test's own proof of the lock-order claim.

**Shipped in `23-04`: a fifth writer, and the first that charges capacity without ever comparing it.**
`adr/0033` preserved an asymmetry - the engine's claim is capacity-blind-and-checked
(`TryClaimAsync`, `WHERE active_chats < capacity`), a hand-picked assignment was capacity-blind-and-
uncharged (no write at all) - that `decisions.md` §2 replaced with a different one: **a deliberate take
still never checks capacity, but it now charges it.** `AssignConversationHandler` takes exactly one
`operators` row, `command.OperatorId`'s, via `IOperatorCapacity.ClaimAsync` - the compare-free sibling
of `TryClaimAsync`, `UPDATE operators SET active_chats = active_chats + 1 WHERE id = @id`, no
`capacity` comparison at all, so `active_chats` may end above `capacity` and that is the intended
state (`decisions.md` §2: "a manual claim increments `active_chats` and does not check it"). The claim
runs inside the handler's own explicit `IUnitOfWork` transaction, alongside the interval open and the
conversation's own save - needed because, unlike `CloseConversationHandler`'s release (deliberately
*after* the commit, accepting a bounded leak), a claim that outlived a losing `SaveChangesAsync` would
strand a slot on an operator holding nothing for it. That makes this handler a new, one-row participant
in the same accepted, data-dependent lock-order cycle `adr/0037` already documents for the engine's own
batches (a single-row `UPDATE` can still be the innocent statement Postgres picks as its cycle's
victim, `6-10`'s own finding) - so it follows the rule for a third writer of `operators` exactly:
"take one row... or take many rows and own the retry" resolves here to *taking one row inside a
transaction it cannot let fail silently*, so it owns the retry the same way `TransferConversationHandler`
does - the whole transaction retries on `OperatorCapacityContentionException`, 5 attempts, the identical
jittered backoff, reusing the proven bound rather than re-measuring it for this specific caller (no
fresh load-test run backs this bound for this handler; see the item's own commit-prep report). The two
racing-operators case resolves through either of two real Postgres guards, not through `xmin` alone -
found live, not anticipated, while proving it: both operators' claims land on different `operators`
rows (no conflict between them there), both stage a new open interval and call `AssignTo` in memory,
and one of them then loses on whichever guard fires first. The conversation row's own `xmin` is the
more obvious one; `23-03`'s own partial unique index (`ix_conversation_assignments_open`, "at most one
open interval per conversation") can equally be the one that actually fires, because EF's
`SaveChangesAsync` executes an Added entity (the new interval) before a Modified one (the conversation)
within the same call, so the loser can hit the unique index before its own `UPDATE` ever reaches the
`xmin` check. Left untranslated, that surfaced as a raw `DbUpdateException` wrapping Postgres's `23505`
rather than `ConversationConcurrencyConflictException` - `ConversationRepository.SaveAsync` now
translates both shapes identically (scoped to this one constraint by name, the same "translate exactly
the constraint this call site can explain" precedent `TagRepository`/`SiteRegistrationRepository`/
`OperatorInviteRedemptionRepository` already set for their own unique-violation catches), because both
mean the identical thing: someone else already committed a conflicting fact about this conversation.
Either way the loser's whole transaction never commits - its capacity claim rolls back with it, so
`active_chats` rises by exactly one regardless of how many operators raced for the same waiting
conversation.

**The schema gap this item found is closed.** `23-03`'s own migration constrained
`conversation_assignments.source` with a Postgres `CHECK (source IN ('Assigned', 'Transferred'))`,
deliberately not widened in advance. `23-04`'s first pass gave `ConversationAssignmentSource.Taken` its
first real C# writer without a migration to widen that constraint alongside it - the wave had one
EF-migration slot and a concurrent item held it, so this was reported as a known gap rather than a
second migration added out of turn. Once that concurrent item (`23-02`) merged, the slot was free and
this item's own follow-up (`Stage23WidenConversationAssignmentSourceCheckConstraint`) widened the
constraint to `source IN ('Assigned', 'Transferred', 'Taken')` and nothing else - confirmed by a
one-line model-snapshot diff, touching no column or constraint `23-02`'s own migration created.
`data-model.md`'s `conversation_assignments` bullet has the full account.

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
