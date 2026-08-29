# ADR-0075: An explicit-transaction port, and a canonical lock order, for transferring a conversation

- **Status**: Accepted
- **Date**: 2026-08-29
- **Stage**: 18

## Context

`18-02` gives an operator a second way to move a conversation onto another operator's plate: `4-02`'s
assignment machinery does it automatically, from the queue; a transfer does it deliberately, operator
to named operator. Underneath, it is the same contended state `concurrency.md` spends its length
protecting — `operators.active_chats`, moved only by an atomic compare-and-set — except a transfer
needs *two* of those to agree in one breath: release the source, claim the target, move the
conversation, or none of it.

Two things about that shape had no precedent in this codebase yet, and both had to be decided rather
than assumed:

**Nothing here gets a transaction for free.** Every other multi-statement write in `Ago.Chat` rides on
one aggregate's own implicit `SaveChangesAsync` transaction. `CloseConversationHandler` is the closest
precedent and is explicit that it does *not* need more than that: its capacity release happens **after**
the close commits, deliberately, because the only residual an already-committed close can leave behind
is one leaked slot — bounded, self-healing, recovered by the disconnect sweep (`adr/0033`). A transfer
cannot accept that shape on either side. Releasing the source before a save that then loses on `xmin`
would over-subscribe them for a conversation they no longer hold — `adr/0033`'s own original objection
to an early release, this time with nothing to undo it. Claiming the target without also committing the
conversation's new `OperatorId` would strand a slot on an operator holding no conversation for it. The
two capacity statements, the conversation's state change, and its outbox row have to rise and fall
together, which means something in `Ago.Chat.Application` has to be able to say "begin a transaction"
and mean it — a capability nothing in this codebase currently exposes above `Infrastructure`.

**A transfer touches two `operators` rows, and `concurrency.md`'s own rule for that case
(`### The lock order on operators, and who absorbs the cycle`) says: take one row in no transaction, or
take many rows and own the retry.** The assignment engine is the existing "many rows" writer, and it
cannot take those rows in a fixed order because *which* operators a batch assigns to is data-dependent
— least-`active_chats`-first, decided at run time. `adr/0037` accepts the resulting engine-vs-engine
cycle rather than serialising assignment to remove it. A transfer is a different shape: it always knows
both rows before it starts (the caller names both operators explicitly), so unlike the engine, it *can*
commit to a fixed order — and without one, two transfers of the same pair of operators in opposite
directions would each issue "claim target, then release source" in program order and invert against
each other for no reason the engine has anything to do with.

## Decision

### `IUnitOfWork` / `IUnitOfWorkTransaction` (`Ago.Chat.Application.Abstractions`)

A minimal explicit-transaction port — `BeginTransactionAsync`, `CommitAsync`/`DisposeAsync` roll back if
never committed — implemented by `EfUnitOfWork` in `Infrastructure.Postgres`, scoped over the same
`AgoChatDbContext` instance the request's other Scoped adapters (`ConversationRepository`,
`OperatorCapacityStore`) already share. Beginning a transaction on that shared context is enough for
every `ExecuteSqlInterpolatedAsync`/`SaveChangesAsync` call already made through those adapters in the
same request to participate — no further wiring needed per adapter.

This is the first port of its kind here. The alternative — inject `AgoChatDbContext` (or `IDbContextTransaction`)
directly into `TransferConversationHandler` — was rejected for the reason every other port in this
codebase exists: `Application` would then know `AgoChatDbContext` is a real EF Core type, untestable
without a database, and in violation of the dependency rule CLAUDE.md states as non-negotiable. The
port is declared in `Application.Abstractions` because the dependency rule forbids `Application` from
knowing about Npgsql or EF Core directly, and implemented in `Infrastructure.Postgres` because that is
the only project allowed to.

### Canonical lock order: whichever operator id sorts smaller is touched first

Inside the one transaction, `TransferAndSaveAsync` compares `command.ToOperatorId` against
`command.FromOperatorId` and always claims/releases the smaller-sorting id's row first — regardless of
which direction the transfer runs. Two transfers of the same two operators, in either direction, now
take those two rows in the same relative order, which rules out the self-inflicted inversion described
above. This is deliberately narrower than `adr/0037`'s problem: it fixes a cycle a transfer can cause
between transfers, not the pre-existing, data-dependent engine cycle, which this transaction remains a
plain participant in (and absorbs the same way the engine's other participants do — see the retry bound
below). `concurrency.md` gains a "Shipped in `18-02`" paragraph recording this as the first writer to
take the "many rows, own the retry" branch of its own rule with a *fixed* order, rather than a
data-dependent one.

### Retry bound: 5 attempts, jittered — revised after measuring, not assumed

The first version of this handler bounded retries at 2 (one retry, no backoff), reasoning that
`OperatorCapacityStore.ReleaseAsync`'s own five-attempt bound is calibrated against the cost of an
*abandoned* retry — a leaked slot — and a transfer's transaction is all-or-nothing, so there is no leak
to weigh against extra attempts, only latency. That reasoning about the residual was correct. The
conclusion — "so fewer attempts are fine" — was not: `TransferringRacesTheAssignmentEngine_...`
(`Ago.Chat.Concurrency.Tests`), a storm of assignment batches, closes, and transfers producing 200+ real
Postgres deadlocks over 15 seconds, showed a bare single retry with no backoff let **zero** transfers
succeed, run after run. The mechanism: retrying immediately, with no jitter, re-issues the failed
attempt back into the same contended row at the same instant every other loser does — recreating the
next cycle instead of escaping it, the same effect `OperatorCapacityStore.ReleaseAsync`'s own remarks
already warn about for a different statement.

`TransactionAttempts` is 5, with the identical jittered backoff formula (`Random 4-16ms x attempt`)
`ReleaseAsync` uses, matching that bound because it is a proven one in this exact codebase against this
exact class of contention — not because the original per-attempt reasoning transferred unchanged. Once
the actual failure mode was "no backoff", the residual argument runs the other way from where it first
pointed: an abandoned attempt here costs nothing but the caller's own patience (no leak, no partial
state), so there is *more* room to retry generously than `ReleaseAsync` has, which is bounded partly by
"how long may a close wait for a slot the disconnect sweep recovers anyway" — a question this handler's
all-or-nothing failure mode does not ask.

**What this bound does and does not prove.** `TransferringRacesTheAssignmentEngine_...` proves the
*safety* properties that hold at any attempt count ≥ 1 by construction — no transfer ever escapes with
an unhandled exception, the capacity invariant holds afterward — because on exhausting its attempts the
handler returns a clean `Result` failure rather than throwing (`ConversationErrors.TransferContended`).
It deliberately does not assert `transferred > 0`: CLAUDE.md rule 7 forbids asserting a throughput
guarantee this suite has not measured holding under every run, and the same storm occasionally lets zero
transfers land even at 5 attempts, in the specific worst case, without any of them corrupting anything.
What is measured, and is the actual claim this ADR makes: 5-with-jitter got transfers through the same
storm that made 2-with-no-jitter get zero through, repeatedly. Throughput under contention this extreme
is a load-test question (`load/`, Stage 7), not a concurrency-suite invariant.

### A known gap in this handler's own test coverage, found and left honest

`OppositeDirectionTransfersBetweenTheSameTwoOperators_NeitherHangsNorCorruptsCapacity`'s own doc comment
claims to prove the canonical lock order prevents transfer-vs-transfer self-deadlock. Its assertions —
all transfers eventually succeed within the 5-attempt budget, capacity stays correct — do not actually
distinguish "the lock order works" from "the lock order is broken but the retry mechanism absorbs the
extra contention it causes." Confirmed directly: mutating the lock-order comparison to always take the
same (wrong) branch did not make this test fail, run three times. The production safety guarantee still
holds — proven independently via direct code review of the comparison itself and via the storm test
above, which does not depend on this property at all — so this is a coverage gap in one test's proof
claim, not a production defect. Left as a named residual rather than silently fixed, because the fix (an
assertion that actually forces the lock-order branch to matter — e.g. a tighter timeout that a
correctly-ordered pair would clear and a cycling pair would not) is itself a design decision this ADR
is not the place to make unreviewed.

### What the visitor and the receiving operator see: the existing fan-out, not a new one

`ConversationTransferredMapper` maps `ConversationTransferred` onto the *existing*
`ConversationAssignedToOperator` wire contract rather than introducing a new one. What the event
announces — "this conversation now has this assigned operator" — is exactly what that contract already
says, and every existing consumer already treats "an assignment happened" generically:
`ConversationAssignmentFanoutConsumer` pushes the SignalR `ConversationAssigned` event to both the
visitor and the newly-assigned operator, and `ConversationAssignmentWebhookDispatchConsumer` fires the
`conversation.assigned` webhook. This satisfies the backlog item's own open call ("both participants are
told... what the visitor sees is a stated decision") with zero new consumer code: the operator identity
the visitor's widget displays updates live, the same push an initial assignment produces, and nothing
else is announced in the thread — no system message, no separate "you were transferred" signal.
`ConversationTransferred.FromOperatorId` does not travel on the wire because no consumer today needs to
know who a conversation moved *from*, only who it is with now; it stays on the domain event for the day
one does.

## Consequences

- `Application.Abstractions` gains its first explicit-transaction port. Any future handler with the
  same "several statements must rise or fall together, and none of them is a self-healing residual"
  shape has a precedent to follow instead of reaching for a `DbContext` directly.
- `concurrency.md` gains a third case in its "who takes `operators` rows and how" table: a writer that
  takes many rows, in a transaction, in a *fixed* order — distinct from both existing rows (one row, no
  transaction; many rows, data-dependent order).
- A named, unfixed gap in `OppositeDirectionTransfersBetweenTheSameTwoOperators_...`'s own proof claim:
  it does not currently distinguish the lock-order fix from the retry mechanism alone. Tracked here
  rather than in the test's own comment alone, so it survives a future read of just the ADR index.
- No new wire contract, no new webhook event type, no schema change — `ConversationTransferred` reuses
  `ConversationAssignedToOperator`'s shape entirely.

## Alternatives considered

- **Inject `AgoChatDbContext` directly into the handler** instead of a new port — rejected: makes
  `Application` depend on a concrete EF Core type, violating the dependency rule CLAUDE.md states as
  non-negotiable, and makes the handler untestable without a real database.
- **A data-dependent lock order for transfers, matching the assignment engine's own approach** —
  rejected: unlike a batch, a transfer always knows both operators before it starts, so there is no
  reason to accept a cycle a fixed order can rule out for free.
- **Bounding retries at 2, matching `6-08`'s original bare-single-retry precedent** — this item's own
  first version, rejected after the storm test measured it losing all transfers under real contention;
  see *Retry bound* above.
- **A new `ConversationTransferredToOperator` wire contract and two new `Competing` consumers**,
  mirroring how most new domain events get their own contract — rejected: the backlog item's own Scope
  never asks for a distinct visitor-facing signal, and every fact the new contract would carry is
  already carried by the existing `ConversationAssignedToOperator` shape.
