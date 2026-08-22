# ADR-0021: Operator assignment - `SKIP LOCKED` (default) vs. a per-operator Redis lock

- **Status**: Accepted
- **Date**: 2026-08-23
- **Stage**: 4

## Context

`concurrency.md`'s "Operator assignment - the contended path": multiple `Worker` replicas compete to
assign waiting conversations to operators with limited capacity, with no coordination between
replicas beyond what the database or a shared lock provides. Two ways to get exclusive access to "try
this claim" were named from the start (`docs/roadmap.md`'s Stage 4 goal), specifically to demonstrate
the trade-off rather than to pick one and never look at the other: `SELECT ... FOR UPDATE SKIP LOCKED`
over the waiting queue (`4-02`), and a distributed lock in Redis, one per operator (`4-03`).

Both sit behind one port, `IAssignmentClaimer` (`Ago.Chat.Application.Abstractions`) - a single method,
"attempt to assign up to N waiting conversations for this site, return how many succeeded." Neither
implementation is allowed to let its own coordination mechanism stand in for the actual correctness
guarantee: `adr/0009` ("Redis is not truth") and `CLAUDE.md` rule 8 ("never cache what a write
decision depends on... capacity checks... come from the database inside the transaction") apply
identically to both. The lock - Postgres row lock or Redis key - only ever decides who gets to
*attempt* a claim; `IOperatorCapacity`'s atomic `UPDATE ... WHERE active_chats < capacity` is the
actual compare-and-set, every time, under both mechanisms.

## Decision

`SkipLockedAssignmentClaimer` is the default (`Program.cs`'s `AssignmentEngine:Mechanism`, unset ->
`"SkipLocked"`). One Postgres transaction per site per tick: `WaitingConversationClaimQuery` claims a
batch with `FOR UPDATE SKIP LOCKED`, holding each claimed row's lock for the transaction's full
lifetime; for each claimed conversation, find a candidate operator, attempt `IOperatorCapacity.
TryClaimAsync` through the *same* transaction (`Database.UseTransactionAsync`), and assign on success.
A claimed-but-unassignable conversation is simply left untouched - its lock releases on commit, and it
is claimable again next tick. No extra infrastructure: Postgres is already the transaction boundary
and already the source of truth.

`RedisLockAssignmentClaimer` is the alternative (`AssignmentEngine:Mechanism` = `"RedisLock"`). No
`SKIP LOCKED` at all - a plain, non-locking read of waiting conversations, then for each, try each
candidate operator in least-loaded order until one's `RedisDistributedLock` is free (`SET NX`
acquire, token-checked Lua-script release, TTL as the correctness backstop if release never runs).
Holding the lock, attempt the capacity claim and the conversation assignment in one Postgres
transaction, exactly as mechanism A does - so a losing attempt's capacity claim rolls back with it,
never a leaked slot.

**The Redis lock does not, by itself, prevent a double-assignment race on the conversation row** -
only `SKIP LOCKED` does that structurally, by making the row genuinely unavailable to a second reader.
Two replicas can both read the same waiting conversation in their own non-locking scan and both
attempt to assign it through two *different* operators' locks simultaneously. Correctness under
mechanism B rests on the `Conversation` aggregate's own `xmin` optimistic-concurrency check on
`SaveChangesAsync` - a losing concurrent save throws `DbUpdateConcurrencyException`, caught and
treated exactly like any other lost race. This is not a gap found and patched; it is the same "last
line of defense" principle `data-model.md` already generalizes from the partitioned `messages` unique
index (`adr/0019`) - the lock is the contention-avoidance optimization, the database write underneath
is what makes the outcome correct regardless of what the lock did.

Global config switch, not per-site: this item's purpose is comparison, not a per-tenant production
choice, and a global switch is the smaller change.

## Consequences

**Mechanism A (default)**:
- \+ No extra infrastructure, no lock-lease expiry problem, no separate failure mode to reason about -
  Postgres being unreachable already fails the whole attempt the same way either mechanism would.
- \+ Structurally prevents the conversation-row race, not just the capacity race - one fewer thing to
  reason about under load.
- − A batch that assigns several claimed conversations to *different* operators holds more than one
  `operators` row lock at once until it commits. Two replicas' batches touching the same site's
  operators in a different order can genuinely deadlock (Postgres detects it, `SqlState 40P01`) - a
  real risk found live while building `4-02`, not anticipated by this doc's original design. Handled
  per-site: caught, logged at `Debug`, retried next tick, so one site's contention never stalls
  another's - but it is a real, occasional wasted attempt under contention that mechanism B's
  per-operator locking sidesteps by construction.

**Mechanism B (alternative)**:
- \+ Per-operator granularity avoids the whole-batch lock escalation that causes mechanism A's
  deadlock risk - two replicas contending for *different* operators never block each other at all.
- \+ A conversation whose top candidate's lock is busy tries the next candidate immediately, in the
  same attempt, rather than waiting for the next tick - cheaper to retry within one pass than
  mechanism A's "lost the capacity race, wait for next tick" for the equivalent situation.
- − A second operational dependency's availability now gates this specific code path too (fail-closed
  by design - `RedisDistributedLock`, unlike the fail-open `RedisLock` `3-04` already uses for cache
  stampede protection - see the type's own remarks for why fail-open would be wrong here). Redis being
  down does not corrupt anything (proven: `RedisLockAssignmentContainerFailureTests`), but it does
  mean zero assignment progress until it recovers, where mechanism A would keep working unaffected.
- − Two extra database round trips per attempt (read waiting conversations, read candidate operators)
  that mechanism A gets from one `SKIP LOCKED` query - not measured against mechanism A's own cost,
  Stage 7's job.
- − Relies on `xmin` optimistic concurrency to catch the conversation-row race that mechanism A
  prevents structurally - correct (proven under real concurrent load,
  `RedisLockAssignmentConcurrencyTests`), but a subtler invariant for a future reader to trust than
  "the row was locked."

## Alternatives considered

- **Fencing tokens on the Redis lock itself** (a monotonically increasing token checked by the
  eventual writer, the textbook fix for "lock expired mid-work, a second holder proceeded, the first
  holder's stale write lands after"): not needed here, because the atomic capacity `UPDATE` and the
  conversation's own `xmin` check already provide that protection at the database layer - adding a
  second, Redis-side fencing mechanism would duplicate a guarantee the write path already has, not
  strengthen it. Worth naming explicitly since fencing tokens are the standard answer to "is your lock
  actually safe," and the answer here is "the lock does not need to be, the database write does."
- **Reusing `RedisLock` (`3-04`) as-is**: rejected during `4-03` - its fail-open behaviour on an
  unreachable Redis is correct for cache-stampede protection (worst case: a redundant cache load) and
  wrong here (worst case: every caller proceeding as if it held an exclusive lock it never got,
  defeating the entire point of serializing access). `RedisDistributedLock` is a fresh implementation
  with the opposite failure mode, not a reuse.
- **Making mechanism B the default**: rejected - `concurrency.md` named mechanism A the default from
  the start ("no extra infrastructure, no lock-lease expiry problems, and the database is already the
  source of truth"), and nothing found while building `4-03` changes that reasoning; mechanism B's
  real advantage (avoiding the deadlock risk) is a real trade-off against a real cost (a second
  dependency gating progress), not a strict improvement.
