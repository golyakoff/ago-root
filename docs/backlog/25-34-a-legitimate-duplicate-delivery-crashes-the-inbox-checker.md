# 25-34 · A legitimate duplicate delivery crashes the inbox checker

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing — `ago-platform`, `Ago.Platform.Persistence.Postgres.EfInboxChecker<T>`
- **Found**: 2026-09-09, live, continuing the author's own booking-flow test right after `25-32` fixed
  the previous step

## What is actually true

Once `25-32`'s fix reached the calendar's worker-choice step, picking a worker produced a new failure:
the widget shows *"Sorry, something went wrong on our end — a person will take over from here."*
Reproduced twice in a row, cleanly, with the calendar hosts fully stable (no restarts in the window
either reproduction happened in) — this is not deploy noise.

`ago-chat-worker`'s log shows the real cause:

```
warn: Ago.Chat.Worker.ModuleTaskConsumer[0]
      Failed to process 01a08646-1527-7dbe-afd6-d60ecd776818 for module-task-routing.
      Microsoft.EntityFrameworkCore.DbUpdateConcurrencyException: The database operation was
      expected to affect 1 row(s), but actually affected 0 row(s); data may have been modified or
      deleted since entities were loaded.
         at ... NpgsqlModificationCommandBatch.ThrowAggregateUpdateConcurrencyExceptionAsync(...)
         at ... Ago.Platform.Persistence.Postgres.EfInboxChecker`1.TryRecordAndSaveAsync(Guid messageId, String consumer, CancellationToken cancellationToken)
         at Ago.Chat.Application.UseCases.RouteConversationToModule.RouteConversationToModuleHandler.AddSystemMessageAndSaveAsync(...) in RouteConversationToModuleHandler.cs:line 381
         at ...FinishStepAsync(...) in RouteConversationToModuleHandler.cs:line 309
         at ...ContinueActiveTaskAsync(...) in RouteConversationToModuleHandler.cs:line 265
         at ...HandleAsync(RouteConversationToModule command, ...) in RouteConversationToModuleHandler.cs:line 109
         at Ago.Chat.Worker.ModuleTaskConsumer.HandleAsync(EventEnvelope envelope, IMessageContext context, ...)
```

**`EfInboxChecker<T>.TryRecordAndSaveAsync` is the platform's own idempotency primitive** — the thing
every at-least-once consumer in this codebase relies on to make "I have already processed this
`messageId`" a safe, cheap check. CLAUDE.md rule 5 ("consumers are idempotent") rests on this
primitive working. Here, a second delivery of the same message — RabbitMQ's own ordinary at-least-once
guarantee, nothing exotic — raced a first delivery that had already inserted the inbox row, and instead
of the checker recognising "already recorded, this is a duplicate, do nothing" as a normal, successful
outcome, EF Core's own optimistic-concurrency machinery threw, and nothing downstream caught it. The
consumer logged a warning and gave up, which is exactly what produced the visitor-facing "a person
will take over" fallback — a real infrastructure failure surfacing as a fabricated apology.

## Where this is likely to go wrong

- **This is `ago-platform`, not `ago-chat`.** The fix belongs in the shared package
  (`Ago.Platform.Persistence.Postgres.EfInboxChecker<T>`), not a workaround in `ago-chat`'s own
  consumer. `ago-chat`'s `nuget.config` points at the local file feed
  (`C:\git\ago\.nuget-feed\`) — packing a fixed `ago-platform` there and bumping `ago-chat`'s package
  reference is how this actually reaches the running system; a fix that only edits `ago-chat` fixes
  nothing, because the primitive itself is what's broken.
- **New public API in `ago-platform` needs a `CHANGELOG.md` entry**, or CI silently republishes the
  old package version — a standing gotcha this project has hit before.
- **Every at-least-once consumer in every product uses this primitive.** A fix here is worth
  re-verifying broadly, not just against this one call site — check whether other consumers'
  integration tests already exercise the duplicate-delivery path, or whether they all share the same
  blind spot this item found live.
- **The likely correct fix is narrow**: an `INSERT ... ON CONFLICT DO NOTHING`-shaped upsert (or
  catching the specific concurrency exception and treating zero-rows-affected as "already recorded,
  return false/already-processed" rather than letting it propagate) is very likely the whole change —
  read the actual current implementation before assuming the shape, but this is not expected to be a
  large fix.

## Done when

- [ ] `EfInboxChecker<T>.TryRecordAndSaveAsync` treats a concurrent duplicate insert as a normal
      "already processed" outcome, not an unhandled exception.
- [ ] A test reproduces two concurrent deliveries of the same `messageId` and asserts neither throws.
- [ ] `ago-platform`'s `CHANGELOG.md` gets an entry; `ago-chat`'s package reference moves to the fixed
      version.
- [ ] Re-verified against the live reproduction: picking a worker in the booking flow (site
      `01a06262-d4f0-7fb6-94e0-9ff702db8a43`, calendar `01a084eb-16be-7865-bcc1-7109fda9c9d9`, worker
      `01a084ec-0c41-78c9-b959-04cb7c1bebf9`) reaches the time-picker step instead of the "a person will
      take over" fallback.
