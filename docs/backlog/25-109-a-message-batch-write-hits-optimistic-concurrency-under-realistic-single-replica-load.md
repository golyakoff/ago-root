# 25-109 · A message batch write hits optimistic concurrency under realistic single-replica load

- **Stage**: 25
- **Status**: ready — reproduced live, root cause not yet located.
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

`ConversationSequencer` (`Ago.Chat.Module/Pipeline/ConversationSequencer.cs`) exists specifically to
prevent two flushes for the same `ConversationId` from being in flight at once, in-process, for exactly
this reason (its own doc comment: "without this, two concurrent flushes could both load the same
conversation, both read the same `LastSequence`, and both compute the same next sequence number").
This trial ran with a single `ago-chat-api` replica, so the gate's own in-process guarantee should
hold - which means either something bypasses the gate for this code path, or the conflicting writer is
outside the process the gate is scoped to (the sequencer's own doc comment distinguishes an
"in-process queue" case from the "broker-consumer case" it was adapted from - `Ago.Chat.Worker` also
writes messages, via a separate path). Not established further here.

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

- Locate the actual concurrent writer: confirm whether `ConversationSequencer`'s gate is bypassed for
  some path through `MessageBatchWriter`, or whether `Ago.Chat.Worker`'s own write path (not gated by
  the same in-process sequencer) is the second writer racing the api process on the same
  `ConversationId`.
- Once found: either close the gap in the gate, or give the batch writer a bounded retry-on-conflict
  (reload the aggregate, reapply, retry the transaction) instead of failing every co-batched message -
  `capacity-ramp` is visitor-only traffic (one message per conversation per interval), so this is not
  an inherent multi-writer scenario at the conversation level; something is causing two writers to
  race that the architecture intends to keep single.
- A regression test proving whichever mechanism was actually racing, fails-before against the
  unfixed code.

## Out of scope

- Postgres resource tuning - this item's own finding is that postgres was not the constraint in any of
  the three trials that found this; `local-capacity-ramp`'s existing config
  (`k8s/overlays/local-capacity-ramp/kustomization.yaml`) is not touched by this item.
- Re-running `capacity-ramp` at the 3+3 replica topology - this bug was found and reproduced at 1+1
  only; whether it also occurs at 3+3 (plausibly masked there by the more severe postgres bottlenecks
  `2026-09-15-local-capacity-ramp.md` already documents) is not established either way.

## Done when

- [ ] The actual concurrent writer racing `MessageBatchWriter`'s update is identified and named.
- [ ] The race is closed (gate fix or retry-on-conflict), with a fails-before test.
- [ ] A `capacity-ramp` re-run at the 1+1 topology (same reproduction steps above) no longer shows
      `DbUpdateConcurrencyException` in `ago-chat-api`'s own logs through at least 2000 connections.
