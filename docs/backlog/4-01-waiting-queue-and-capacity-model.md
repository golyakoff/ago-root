# Waiting queue and capacity model

- **Stage**: 4
- **Status**: done
- **Depends on**: nothing - foundational for the rest of Stage 4

## Goal

The schema and domain vocabulary the real assignment engine (`4-02`) needs, so the engine itself is
free to be entirely about the contended claim, not about inventing the model it claims against.
After this: `operators.active_chats` exists and is enforced by an atomic compare-and-set write, not
loaded-mutated-saved through the aggregate; `Conversation` can be released back to the waiting queue,
not just assigned once and left there; and a Dapper query can list waiting conversations with the
exact predicate the assignment loop will `SKIP LOCKED` against.

## Context to read first

`docs/architecture/concurrency.md`'s "Operator assignment - the contended path" section (the atomic
`UPDATE ... WHERE active_chats < capacity` statement is quoted there, verbatim - this item builds
exactly that, no more), `docs/architecture/data-model.md` (`operators` row shape, keys and indexes,
migration rules), `docs/vision.md` lines ~55-59 (the user-facing sequence this model exists to
support), `adr/0004` (EF writes / Dapper reads - and where this item's capacity write does *not*
fit that split cleanly, see Scope below), the `db-migration` skill, the `vertical-slice` skill.

Also read `src/Ago.Chat.Domain/Operator.cs` and `src/Ago.Chat.Domain/Conversation.cs` as they stand
today - both already carry doctor comments pointing at this exact item (`Operator`: "capacity
enforcement... is Stage 4"; `Conversation.AssignTo`: "not the queue/capacity-aware assignment
engine, which is Stage 4's centerpiece"). `AssignConversation`/`AssignConversationHandler` (the
existing direct-claim-by-one-operator use case, `1-02`) stays as-is and out of scope - it is a
different, narrower use case (an operator claiming a specific conversation by id from a UI list),
not the thing this stage replaces.

## Scope

- Migration: add `operators.active_chats integer not null default 0`. Additive, reversible
  (`db-migration` skill).
- The capacity claim/release write is a raw atomic `UPDATE`, not an EF aggregate load-mutate-save:
  `UPDATE operators SET active_chats = active_chats + 1 WHERE id = @id AND active_chats < @capacity`
  (claim) and `UPDATE operators SET active_chats = active_chats - 1 WHERE id = @id AND
  active_chats > 0` (release). This is a deliberate exception to "EF writes" (`adr/0004`) - the
  qualifying reason is in `concurrency.md` already: a compare-and-set write is exactly what EF's
  load-mutate-save cannot express as one round trip without a second optimistic-concurrency
  collision to handle. State this reasoning in the response when this port is implemented (teaching
  mode, `CLAUDE.md`) rather than silently doing EF for everything else and raw SQL only here.
  A row count of 0 from the claim is "lost the race" (or "no capacity left") and must be treated as
  a normal, expected outcome by every caller - not logged at `Error`, not retried in a loop that
  could livelock, just reported back as "did not claim."
- Port shape: a small, focused abstraction in `Ago.Chat.Application/Abstractions` (e.g.
  `IOperatorCapacity`) with `TryClaimAsync(OperatorId, CancellationToken) -> bool` and
  `ReleaseAsync(OperatorId, CancellationToken)`. Implemented in `Ago.Chat.Infrastructure.Postgres`
  via raw Npgsql/Dapper against the same connection the rest of that project already uses - not a
  new "technology" project under `adr/0004`'s one-project-per-technology rule, since this is still
  Postgres.
- `Conversation.ReleaseToQueue(DateTimeOffset now)`: the domain method that takes an `Assigned`
  conversation back to `Waiting`, clears `OperatorId`, and raises a `ConversationReleased` domain
  event (mirrors `AssignTo`'s shape and invariant checks - only `Assigned` may be released; releasing
  an already-`Waiting` or `Closed` conversation is the same kind of `InvalidConversationStateException`
  `AssignTo` already throws for the wrong-state case). No caller yet - `4-02`'s losing-the-race path
  and `4-04`'s disconnect release both need it, but wiring either is out of scope here.
- A read for the assignment loop to claim against: a Dapper query, `SELECT id FROM conversations
  WHERE site_id = @siteId AND state = 'waiting' ORDER BY created_at LIMIT @batchSize FOR UPDATE SKIP
  LOCKED`, following `OutboxDispatcher`'s own established shape for this exact SQL pattern
  (`src/Ago.Chat.Worker/OutboxDispatcher.cs`, `ClaimedOutboxRow.cs` - raw Npgsql in the Worker host,
  not a `Dapper`-through-Application-port read, because a `SKIP LOCKED` claim is a write-adjacent
  transactional read, not an ordinary query `IConversationReadStore` should ever expose). State
  explicitly where this lives and why it does not go through `IConversationReadStore` - the
  qualifying difference from an ordinary read is the `FOR UPDATE` lock, which only makes sense
  inside the same transaction the caller commits or rolls back, unlike every other read in this
  codebase.
- `data-model.md` gets `active_chats`'s actual shape and the compare-and-set statement recorded
  alongside `conversations`' existing partial waiting-queue index (already documented there - confirm
  it is still accurate once this item's query is real, and correct it if not).

## Out of scope

- The assignment loop itself that calls `TryClaimAsync`/the waiting-queue query together - `4-02`.
- Anything Redis-shaped - `4-03`.
- Calling `ReleaseToQueue` from anywhere - `4-02` (lost race) and `4-04` (disconnect) are the two
  real callers, neither exists yet.
- Changing `AssignConversationHandler`/`AssignConversation` (the existing direct-claim use case) -
  it does not touch `active_chats` today and this item does not add that; whether it should is a
  question for whoever picks up `4-02`, once the automated engine exists to compare it against.

## Done when

- [x] Migration applies cleanly to a real Postgres (Testcontainers, matching every prior
      `Ago.Chat.Infrastructure.Postgres` migration's own verified bar) and is reversible.
      Two migrations, both additive/reversible: `Stage4AddOperatorActiveChats` (the column, as an EF
      shadow property - see below) and `Stage4AddWaitingQueueIndex` (`ix_conversations_waiting`,
      replacing EF's default FK index on `conversations.site_id` - see the finding below).
- [x] `Ago.Chat.Integration.Tests`: concurrent `TryClaimAsync` calls against one operator at exactly
      their capacity - exactly `capacity` succeed, the rest return `false`, `active_chats` never
      exceeds `capacity` even under real parallel load (Testcontainers Postgres, real concurrent
      connections, not sequential awaits pretending to be concurrent).
      `OperatorCapacityStoreTests` - 20 real concurrent `TryClaimAsync` calls (separate pooled
      connections, `Task.WhenAll`) against capacity 5: exactly 5 succeed, `active_chats` lands at
      exactly 5. `ReleaseAsync` floors at zero under a duplicate/racing release. Stable across 5
      consecutive runs.
- [x] `Ago.Chat.Domain.Tests`: `ReleaseToQueue` - valid transition from `Assigned`, invalid from
      `Waiting`/`Closed`, `ConversationReleased` raised with the right payload.
- [x] `Ago.Chat.Architecture.Tests`: the capacity port's Postgres implementation lives only in
      `Ago.Chat.Infrastructure.Postgres` (same boundary `PersistenceBoundaryTests` already enforces
      for Npgsql/EF Core - confirm the raw-SQL path is covered by the same rule, not a gap in it).
      **Real finding, not fixed here (flagged as a separate task)**: `PersistenceBoundaryTests`'
      `AllProduct` list (`TestAssemblies.cs`) does not include `Ago.Chat.Worker` or `Ago.Chat.Api`,
      even though the test's own class comment says the rule covers "Module and the hosts." This
      slice's `WaitingConversationClaimQuery` uses raw Npgsql in `Ago.Chat.Worker` - the same
      pre-existing pattern `OutboxDispatcher` (`2-04`) already established there, so this item stayed
      consistent with the codebase rather than silently expanding scope to fix a Stage-2-era test gap
      and everything it might newly catch.
- [x] `data-model.md` updated with `active_chats`, the compare-and-set statement, and the waiting-
      queue claim query's actual location and shape.
      Also corrected: `concurrency.md`'s original wording compared `active_chats` against a
      `@capacity` *parameter* (implying a separate read); the shipped version compares against the
      `capacity` column of the same row being updated instead - strictly safer, no read to race
      against, and the doc now says so.

## Open questions

None - `concurrency.md` already specifies the compare-and-set statement verbatim; the rest is
applying `adr/0004`'s own qualifying logic to a case it did not originally enumerate.
