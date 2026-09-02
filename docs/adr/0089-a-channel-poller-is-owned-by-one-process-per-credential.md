# ADR-0089: A channel poller is owned by one process, per credential, by a Postgres advisory lock

- **Status**: Accepted
- **Date**: 2026-09-02
- **Decides**: `14-16`
- **Amends**: `docs/architecture/concurrency.md` (its unqualified "multiple `Worker` replicas" claim
  gains the one exception it always had in fact, and then loses it again by construction)
- **Does not amend `adr/0013`**: the pollers stay inside `Ago.Chat.Worker`; no fourth host.

## Context

`Ago.Chat.Worker` hosts `TelegramLongPollingService` (`14-07`) and `MaxLongPollingService` (`14-02`).
Each keeps a `_pollers` dictionary of one poll loop per active `ChannelCredential`, and each loop
keeps its `offset` cursor as a **local variable**. All of that is per-process state, coordinated by
nothing: there is no advisory lock, no lease and no leader election anywhere in `ago-chat`.

Telegram refuses a second concurrent `getUpdates` on one bot token with `409 Conflict`. So the number
of processes running these services is a correctness parameter, and nothing states or enforces its
value.

`concurrency.md` states the opposite, without qualification — *multiple `Worker` replicas compete to
assign waiting conversations* — which is the premise of its whole contended-path section and true of
that path, where `SKIP LOCKED` makes it safe. It is false of these two hosted services. `replicas: 1`
hides the contradiction entirely; a manifest comment now labels it (`14-16`), which is a label, not a
guarantee.

The symptom that exposed this is small and was measured rather than assumed: every Worker rolling
update overlaps the old and new pod (`maxUnavailable` resolves to `0` on a single replica), producing
a transient `409` that clears itself. Nothing is lost — Telegram replays an update until the cursor
passes it. Nothing is duplicated — `client_message_id` carries a unique filtered index. The cost is
seconds of latency.

**The symptom is not why this ADR exists.** It exists because the constraint is unwritten and
unenforced, and because the obvious future action — scale the Worker for throughput — silently breaks
inbound Telegram and MAX permanently rather than transiently.

## Decision

**Ownership of a channel poll loop is claimed per `ChannelCredentialId`, by a session-scoped
PostgreSQL advisory lock, held for the life of the loop and released by the database itself when the
holding session ends.**

A Worker instance polls a credential if and only if it holds that credential's advisory lock. A
process that cannot acquire one does not poll that credential; it retries on the existing refresh
tick.

Three properties follow, and the third is the reason for the choice of key:

1. **No TTL, and no renewal.** A session-scoped advisory lock is bound to the connection. When the
   holder dies — crash, `SIGKILL`, node loss, network partition — PostgreSQL releases the lock when
   the session ends. There is no lease duration to tune and no heartbeat to get wrong.
2. **Takeover is the normal path, not a recovery path.** The next process to attempt an acquire gets
   it. Bounded by the refresh interval plus however long the database takes to notice the dead
   session, both stated numbers rather than hopes.
3. **The key is the credential, not the service.** A global "poller leader" lock would have been
   simpler and strictly worse: it would confine every bot to one process forever. Keying on the
   credential means several Worker replicas **share** the bots between them, each holding the locks
   it won. So this ADR does not forbid scaling the Worker — it is what makes scaling the polling
   path work at all.

Point 3 turns the item from a restriction into a capability, which is why the per-credential key is
part of the decision rather than an implementation detail.

### What happens when the holder dies mid-poll

Stated plainly, because a guarantee that only holds while nothing dies is not one:

- **Clean shutdown** (`SIGTERM`): the loop is cancelled, the lock is released explicitly, the
  connection closes. The next process acquires on its next tick.
- **Crash / node loss**: the lock is released when PostgreSQL reaps the session. Until then no other
  process polls that credential, and Telegram queues the updates. Nothing is lost; delivery is
  delayed by the reap plus one tick.
- **Half-open connection** — the honest weak spot. If the TCP session black-holes, the holder can
  believe it still owns a lock PostgreSQL has released, and two pollers appear. This is bounded, not
  eliminated: the holder verifies ownership on its own connection on each refresh tick, and a broken
  connection surfaces as an exception there, which stops the loop. The window is TCP-keepalive-shaped
  and is smaller and better-behaved than a TTL race, but it is a window, and it is the reason the
  application-level defences below stay in place rather than being deleted as redundant.

**The idempotency defences are not removed.** `client_message_id`'s unique index and the offset-only-
after-dispatch rule remain exactly as they are. This lock reduces the probability of a double poller;
it is not permitted to become the only thing standing between the system and duplicate messages.
That is `adr/0005`'s at-least-once posture applied here rather than an exception carved out of it.

## Alternatives considered

**Reuse `RedisDistributedLock` (`Ago.Platform.Caching.Redis`).** The strongest alternative, because
the primitive already exists, is already good — `SET NX`, token-checked Lua release, deliberately
fail-closed — and is **already used in this very host**: `RedisLockAssignmentClaimer` claims operator
assignment with it. Rejected on **duration**, which is the whole difference. That claimer holds the
lock for a short critical section, where a TTL comfortably longer than the work is a correct design.
Poller ownership is held indefinitely, and a TTL without renewal has no good setting: short enough to
recover from a crash means it expires under a live holder — two pollers, silently and permanently,
which is the exact failure being fixed — and long enough to be safe means a crashed holder blocks its
own bots for that duration. The fix is renewal, and renewal is precisely the part of a lease that is
hard to get right (what the holder must do when a renewal fails, mid-poll, is a new correctness
question). The advisory lock has no such question because liveness is the connection.

Secondary, but real: CLAUDE.md's rule that Redis is never a source of truth. Which process owns a
poller is not a cache.

**A separate host, pinned to one replica.** The honest expression of "this does not scale", and it
adds a fourth host against `adr/0013`'s split-by-failure-profile reasoning. Rejected for a stronger
reason than that: it does not even solve the observed symptom — a rolling update of a one-replica
host still overlaps — and it caps polling at one process forever, discarding the capability that the
per-credential key buys.

**A `poller_leases` table with `SELECT … FOR UPDATE SKIP LOCKED`.** Would reuse the pattern the
assignment path already demonstrates. Rejected because holding a row lock for a poller's lifetime
means holding a **transaction** open for that lifetime, which is a long-running transaction in the
worst sense: it pins the oldest snapshot and works directly against autovacuum. Advisory locks exist
precisely so ownership need not be transactional.

**Do nothing beyond the manifest comment.** Rejected, but it is the option the author explicitly
weighed rather than dismissed: the comment does remove the immediate foot-gun. It leaves a documented
contradiction between an architecture document and the code, and leaves the constraint enforced by
somebody reading a YAML comment.

## Consequences

- **Positive**: the Worker's polling path becomes genuinely multi-replica. Bots distribute across
  replicas by whoever wins each lock, with no configuration and no partitioning scheme.
- **Positive**: the rollout `409` disappears rather than being explained — the new pod cannot poll
  until the old pod's session ends.
- **Positive**: `concurrency.md` stops carrying a claim that is false in a named case.
- **Negative**: each Worker process holds one dedicated PostgreSQL connection outside `NpgsqlDataSource`'s
  pooling, for the life of the process, because a session-scoped lock is only meaningful on a
  connection that is not returned to a pool. One connection per Worker, not one per credential — many
  advisory locks can be held on a single session — but it is a connection that must be excluded from
  pooling deliberately and will look wrong to anyone who does not know why.
- **Negative**: advisory locks are keyed by `bigint`, and `ChannelCredentialId` is a UUID. A hash is
  required, and a hash collision would mean one bot silently never polls. 64 bits makes this
  negligible in this system's scale but not zero, and "silently never polls" is a bad failure mode, so
  the collision must be made observable rather than merely improbable.
- **Negative**: advisory locks are invisible to anyone reading the schema. They exist only in
  `pg_locks`. This is documented in `concurrency.md` as part of this change, because a coordination
  mechanism nobody can find is a coordination mechanism that gets broken by accident.
- **Consequence for `adr/0005`**: none. Idempotency defences are explicitly retained above.

## Placement, and the promotion this ADR declines

The port is `Ago.Chat.Application/Abstractions`; the adapter is `Ago.Chat.Infrastructure.Postgres`;
the wiring is `Ago.Chat.Worker`. The pollers live in `Ago.Chat.Infrastructure.Telegram` and
`Ago.Chat.Infrastructure.MaxBot` and depend on the Application port, which the dependency rule allows.

**It is deliberately not promoted to `Ago.Platform.Persistence.Postgres`, even though that project
exists and a sibling primitive (`RedisDistributedLock`) already lives in the platform.** Applying
`clean-architecture.md`'s three qualifying tests: it contains no domain concept (passes) and can be
described without naming chat, visitors or operators (passes), but *a second product would plausibly
use it unchanged* is a guess — AGO Calendar has no polling loop and no singleton background work that
needs this. That file's own instruction covers exactly this case: treat anything ambiguous as product
code and promote later, because promotion is cheap. `adr/0027` is the standing precedent that a real
second product makes promotion *possible*, not automatically correct.

The practical half of the same argument: promotion means a platform package version, a `CHANGELOG.md`
entry and a pin move in the consuming repository, spent on a guess about a second caller. If AGO
Calendar ever grows one, the promotion is a move and a version bump, and this paragraph is the record
of why it was not done pre-emptively.
