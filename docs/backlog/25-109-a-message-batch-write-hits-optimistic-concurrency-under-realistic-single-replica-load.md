# 25-109 · A message batch write hits optimistic concurrency under realistic single-replica load

- **Stage**: 25
- **Status**: ready — reproduced live, root cause found (Opus research pass, 2026-09-15).
- **Depends on**: nothing
- **Found**: 2026-09-15, running `capacity-ramp` against a topology matching the real `reserve-me.ru`
  deployment (1 `ago-chat-api` replica, 1 `ago-chat-worker` replica, `nfr.md`'s own per-pod resource
  budget) instead of the local dev overlay's 3+3 - a follow-up to
  `load/reports/2026-09-15-local-capacity-ramp.md`'s own postgres-tuning investigation, done to check
  whether that investigation's findings actually apply to the real deployment's own topology.

## What is actually true

They do not - postgres was never the constraint at 1+1 replicas. Three trials swept postgres's own
resources (1 CPU/1Gi/`max_connections=150` through 2 CPU/2Gi/`max_connections=300`, the last being
`local-capacity-ramp`'s own already-proven config) and postgres sat at **0-1.3% CPU and ~0.2% memory**
in every one, regardless of what it was given - it never became the limiting resource. What actually
capped each run at 1500-2000 connections, with a 9-18% message-error rate at the safety valve, was a
burst of identical failures at the api layer:

```
Microsoft.EntityFrameworkCore.DbUpdateConcurrencyException: The database operation was expected to
affect 1 row(s), but actually affected 0 row(s); data may have been modified or deleted since entities
were loaded.
```

confirmed live in `ago-chat-api`'s own pod logs during the run. `MessageBatchWriter.FlushAsync`
(`Ago.Chat.Infrastructure.Postgres/Pipeline/MessageBatchWriter.cs:294`) catches this at the
whole-transaction level and fails **every pending ack in that flush's batch** at once
(`MessageBatchWriter.cs:296-299`) - one concurrency conflict on one row takes down every other,
unrelated message that happened to be batched alongside it, which is why the client sees a burst of
~20 identical `HubException: Failed to save message, try again.` errors per conflict rather than one.

## Root cause (found by a dedicated research pass, 2026-09-15)

`ConversationSequencer` is not bypassed and has no gap - it correctly serialises every conversation
write **within** a process (verified: `BatchFlusherService` runs one sequential flush loop, and
`MessagePipelineWorkerHost`'s four concurrent dequeue loops each hold the per-conversation gate for the
item's *entire* lifetime, from "handed to `BatchAccumulator`" through "that item's flush committed" -
`MessagePipelineWorkerHost.cs:70-73` calls `accumulator.WaitForFlushAsync`, which awaits the same
`Ack.Task` that `MessageBatchWriter.FlushAsync` completes). Two messages for the same conversation can
never be mid-flight together inside `ago-chat-api`.

**The second writer is `Ago.Chat.Worker`'s `UnreadCounterConsumer` → `RecordUnreadMessageHandler`**, a
different process with its own, independent `ConversationSequencer` instance (both hosts register the
same five pipeline classes as singletons - `Ago.Chat.Api/CompositionRoot.cs:208-212`,
`Ago.Chat.Worker/Program.cs:100-105` - a leftover from `14-02` giving Worker its own producer, per that
file's own comment at lines 94-100). `UnreadCounterConsumer` subscribes `Competing` to every
`MessageAccepted` event and, for visitor traffic with no operator ever reading, unconditionally
increments `operator_unread_count` on the same `conversations` row (`Conversation.cs:781-796`'s visitor
branch: `sequence > OperatorLastReadSequence` always holds when nobody has read anything). `Conversation`
carries `xmin` as its EF row-version (`ConversationConfiguration.cs:71`), and `Conversation.AddMessage`
also mutates the root (`LastSequence++`, `Conversation.cs:902`) - so the api's own `SaveChangesAsync`
and the worker's own land on the same versioned row from two uncoordinated processes, and whichever
commits second gets `DbUpdateConcurrencyException`.

The window is wide enough to hit reliably because `MessageBatchWriter.FlushAsync` loads every
conversation in a batch **sequentially**, one round trip each (`MessageBatchWriter.cs:105`,
`ConversationRepository.GetByIdAsync`, each pulling the full `_messages`/`_moduleTasks` history) before
a single `SaveChangesAsync` at the end - the first conversation loaded stays exposed, unmodified in the
transaction's own view, for the whole remaining loop. The burst size observed (~15-25 failed acks per
conflict) implies flushes were taking ~450ms under this load, matching a load→save window wide enough
to cover ~20 unrelated conversations at once. This is also why the failure has a load *threshold*: at
low traffic the worker's unread update for message N lands long before conversation N+1 arrives, so the
windows never overlap; only once the worker (1 replica in this topology, six consumer groups sharing
one pod) falls behind does its update stream smear across the api's current flush window. One worker
replica instead of three would make this roughly three times more likely to surface - consistent with
this being found at 1+1 and not (yet) at 3+3.

`MessageBatchWriter` is the **one** conversation-write path in the codebase that bypasses
`ConversationRepository.SaveAsync` (which translates this exact exception into
`ConversationConcurrencyConflictException` and lets the caller reload-and-reapply - see
`RouteConversationToModuleHandler.AddSystemMessageAndSaveAsync` for the established pattern) and calls
`db.SaveChangesAsync` directly (`MessageBatchWriter.cs:291`). Its catch-all
(`MessageBatchWriter.cs:294-302`) has no retry, so it converts one lost row into a terminal failure for
every other, unrelated message staged in the same flush.

**A secondary, unconfirmed candidate**: `ConversationAssignmentJob`/`SkipLockedAssignmentClaimer` also
writes the same row (interval 2s, batch 20/site) whenever an operator is online for the site, and was
not ruled out - the research pass recommends logging `ex.Entries` (entity type + primary key) in the
existing catch block to distinguish the two conclusively on the next run, rather than guessing further.
`ConnectionFanoutConsumer` was checked and is **not** a candidate (no conversation write). The author's
own node/replica-affinity hypothesis was checked directly (grepped for affinity/pinned/owning/sticky
across `src/`) and no such mechanism exists on this path - `edge.md`'s own "no sticky sessions" holds;
the only per-conversation "ownership" concept is operator assignment, a different thing, though the
assignment job above is a legitimate second writer in its own right.

## Reproducing it

1. `local-capacity-ramp` overlay applied, then `ago-chat-api`/`ago-chat-worker` patched to 1 replica
   each (`kubectl patch deployment ago-chat-api|ago-chat-worker -n ago-chat --type=json -p
   '[{"op":"replace","path":"/spec/replicas","value":1}]'`) - both keep `base`'s own resource limits
   (api: 512Mi/500m; worker: 512Mi/1000m), not `local-capacity-ramp`'s.
2. Clean `demo_site` (`capacity-ramp` skill's own step).
3. Run `capacity-ramp` (`LOADDRIVER_STEP_SIZE=500`, `LOADDRIVER_STEP_HOLD_SECONDS=30`).
4. By ~1500-2000 cumulative connections, `kubectl logs -n ago-chat deploy/ago-chat-api | grep
   DbUpdateConcurrencyException` shows the exception; the console output shows bursts of ~20 identical
   `message send failed` lines per occurrence.

Reproduced in 3 separate trials (different postgres resource configs, same api/worker topology), same
signature each time - not a one-off.

## Scope

Three changes, in this order (each independently useful, but (2) is the real safety net - (1) alone
would leave every other cross-process writer named above unhandled):

1. **Diagnostic log line first, landed with the fix, not as a separate trip**: log `ex.Entries`
   (entity type + primary key) in `MessageBatchWriter`'s existing catch block
   (`MessageBatchWriter.cs:294-302`), so a re-run of the reproduction confirms which row/entity type
   actually conflicted - this either confirms `UnreadCounterConsumer` as the dominant racer or surfaces
   the assignment job instead, before the fix below is trusted.
2. **Remove the dominant racer**: rewrite `RecordUnreadMessageHandler`'s unread-count increment as a
   raw SQL `UPDATE conversations SET operator_unread_count = operator_unread_count + 1 WHERE id = @id
   AND @sequence > operator_last_read_sequence`, run on the handler's own connection/transaction -
   the same shadow-property/raw-SQL pattern `erasure_requested_at`
   (`ConversationConfiguration.cs:123-125`) and `SiteActivityWatchdogQuery.TouchManyAsync`
   (`MessageBatchWriter.cs:284`) already use for exactly this reason: a column that must not contend
   for `xmin` against every ordinary message send. Still commits atomically with the inbox-dedup row
   (`adr/0017`).
3. **Bounded retry in `MessageBatchWriter` regardless of (2)** - `ConversationAssignmentJob`,
   `AutoCloseInactiveConversationsJob`, module routing and offline auto-reply remain legitimate
   cross-process writers that (2) does not remove. Wrap the whole flush body (connection, transaction
   and `DbContext` creation included - the context is poisoned after a failed `SaveChangesAsync`) in a
   bounded retry loop (3 attempts, small jittered backoff), replaying only items whose `Ack.Task` is
   not yet completed. Nothing was committed on a failed attempt, so replay is safe: sequences are
   recomputed from the freshly reloaded aggregate, and `ClientMessageId` dedup
   (`Conversation.cs:888-899`) plus the `(conversation_id, sequence, site_id)` unique index are the
   existing backstops against a duplicate. On a final, still-failing attempt, fall back to per-
   conversation-group transactions so one contended conversation cannot take down the rest of the
   batch - matches every other conversation writer's own established pattern
   (`ConversationRepository.SaveAsync` translating to `ConversationConcurrencyConflictException`,
   `RouteConversationToModuleHandler.AddSystemMessageAndSaveAsync`'s reload-and-reapply).
4. A regression test proving the fix: `tests/Ago.Chat.Integration.Tests/MessageBatchWriterTests.cs`
   already drives `FlushAsync` against real Postgres via Testcontainers.
   `MessageBatchWriter`'s injected `IClock.UtcNow` call (`MessageBatchWriter.cs:167`) runs after the
   conversation is loaded and before `SaveChangesAsync` - a fake clock whose first call runs the
   `UnreadCounterConsumer`-style `UPDATE` on a separate connection reproduces the race deterministically
   with no new test seam in production code and no live cluster. Fails-before: every ack in a multi-
   conversation batch returns `Conversation.Unavailable`. After: all acks succeed, sequences stay
   gap-free ascending.

## Out of scope

- **Shrinking `MessageBatchWriter`'s own load→save window** (batch-loading every conversation in one
  `WHERE Id IN (...)` query instead of N sequential round trips) - real, independently valuable
  (narrows exposure and keeps flushes/batches smaller), but a distinct change from closing the race
  itself. Worth its own item if wanted; not required for this one's Done-when.
- **Auditing every other cross-process writer of `conversations`** for the same missing-retry gap -
  this item's own research pass named `ConversationAssignmentJob`,
  `AutoCloseInactiveConversationsJob`, module routing and offline auto-reply as writers that go through
  `ConversationRepository.SaveAsync` (which already translates and lets the caller retry) rather than
  `MessageBatchWriter`'s own bypass - the pattern already exists where those live; this item does not
  re-verify each of them.
- Postgres resource tuning - this item's own finding is that postgres was not the constraint in any of
  the three trials that found this; `local-capacity-ramp`'s existing config
  (`k8s/overlays/local-capacity-ramp/kustomization.yaml`) is not touched by this item.
- Re-running `capacity-ramp` at the 3+3 replica topology - this bug was found and reproduced at 1+1
  only; whether it also occurs at 3+3 (plausibly masked there by the more severe postgres bottlenecks
  `2026-09-15-local-capacity-ramp.md` already documents) is not established either way.
- The dual pipeline registration in `Ago.Chat.Worker` (`14-02`'s own stale-comment leftover) is a
  latent instance of this same class of bug for real inbound-channel traffic (worker's own
  `MessageBatchWriter` races the same way for MAX/Telegram messages) - fix (3) above covers it too
  since it is the same code path, so no separate scope is needed here.

## Done when

- [ ] `ex.Entries` logged in `MessageBatchWriter`'s catch block, confirming `UnreadCounterConsumer` (or
      naming whichever writer actually conflicted, if not that one) on a re-run.
- [ ] `RecordUnreadMessageHandler`'s increment no longer contends for `conversations`' own `xmin`.
- [ ] `MessageBatchWriter` retries a losing flush instead of failing every co-batched message, with a
      fails-before test proving it (the `IClock`-triggered race described above).
- [ ] A `capacity-ramp` re-run at the 1+1 topology (same reproduction steps above) no longer shows
      `DbUpdateConcurrencyException` in `ago-chat-api`'s own logs through at least 2000 connections.
