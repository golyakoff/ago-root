# 25-34 · Module-task routing bypasses the conversation's own retry-on-conflict pattern

- **Stage**: 25
- **Status**: ready — **corrected after further investigation; the first write-up misidentified where
  the fix belongs. Read this version, not the title's own first impression.**
- **Depends on**: nothing
- **Found**: 2026-09-09, live, continuing the author's own booking-flow test right after `25-32` fixed
  the previous step

## What is actually true

Once `25-32`'s fix reached the calendar's worker-choice step, picking a worker produced a new failure:
the widget shows *"Sorry, something went wrong on our end — a person will take over from here."*
Reproduced twice in a row, cleanly, with the calendar hosts fully stable.

`ago-chat-worker`'s log shows the proximate cause:

```
warn: Ago.Chat.Worker.ModuleTaskConsumer[0]
      Failed to process 01a08646-1527-7dbe-afd6-d60ecd776818 for module-task-routing.
      Microsoft.EntityFrameworkCore.DbUpdateConcurrencyException: The database operation was
      expected to affect 1 row(s), but actually affected 0 row(s); ...
         at ... Ago.Platform.Persistence.Postgres.EfInboxChecker`1.TryRecordAndSaveAsync(...)
         at Ago.Chat.Application.UseCases.RouteConversationToModule.RouteConversationToModuleHandler.AddSystemMessageAndSaveAsync(...) in RouteConversationToModuleHandler.cs:line 381
```

**This item's own first draft assumed the bug lives in `ago-platform`'s `EfInboxChecker<T>`** — a
narrower reading of the stack trace than the evidence supports. Two attempts to reproduce a genuine
concurrent-insert race against `EfInboxChecker` alone (via `Task.WhenAll` on two `TryRecordAndSaveAsync`
calls, both with and without unrelated entities batched alongside the inbox row) **did not** produce
`DbUpdateConcurrencyException` — Postgres serialises two competing single-row inserts against the same
key cleanly enough that the loser gets an ordinary unique-violation instead, which the checker already
handles correctly (and has tests for).

**Reading the actual caller settles it.**
`RouteConversationToModuleHandler.AddSystemMessageAndSaveAsync` (`ago-chat`) calls
`conversation.AddSystemMessage(...)` — mutating the tracked `Conversation` aggregate in memory — and
only then calls `inbox.TryRecordAndSaveAsync(...)`, whose own `SaveChangesAsync()` is what actually
flushes **both** the conversation's own update **and** the new inbox row in one batch. `Conversation`
carries Postgres's `xmin` as an EF row-version (`ConversationConfiguration.cs`:
`builder.Property<uint>("xmin").IsRowVersion();`) — a deliberate, already-established optimistic-
concurrency mechanism. Two genuinely concurrent deliveries of the same trigger message each load and
modify their own in-memory copy of the *same* `Conversation` row; the loser's `xmin` check fails, and
**that** is the real source of the `DbUpdateConcurrencyException` — a legitimate conflict on the
conversation aggregate, not a defect in the inbox primitive at all.

**This codebase already has the correct pattern for exactly this conflict, and this one handler
doesn't use it.** `IConversationRepository.SaveAsync` translates a raw EF `DbUpdateConcurrencyException`
into the technology-agnostic `ConversationConcurrencyConflictException` at the persistence-port
boundary (`ConversationConcurrencyConflictException.cs`'s own doc comment, `adr`/`6-08`), and
`CloseConversationHandler`/`AssignConversationHandler` both catch it and **retry once against freshly
reloaded state** — a deliberate, bounded "one transparent retry, or a clean conflict result" policy,
never an unbounded loop. `RouteConversationToModuleHandler.AddSystemMessageAndSaveAsync` never goes
through `IConversationRepository.SaveAsync` at all — it mutates the tracked entity and relies on
`EfInboxChecker`'s own raw `SaveChangesAsync()` to flush it, which means the conversation's own `xmin`
conflict surfaces as a *raw, untranslated* EF exception with no retry, is caught nowhere, and the
consumer just logs a warning and gives up — producing the fabricated "a person will take over"
fallback for what is actually an ordinary, expected race under concurrent redelivery.

## What was tried and discarded — recorded so it is not tried again the same way

A fix was drafted directly in `ago-platform`'s `EfInboxChecker<T>` (catching
`DbUpdateConcurrencyException` alongside the existing unique-violation catch) and tested against a
purpose-built concurrent-delivery integration test. **Discarded before landing**, once the caller-side
investigation above made clear the conflict belongs to the `Conversation` aggregate, not the inbox
row: swallowing the exception inside `EfInboxChecker` would have silently treated a lost conversation
update as "already processed" — the losing delivery's own system message would never be persisted and
would never be retried either, since `TryRecordAndSaveAsync` returning `false` short-circuits straight
to `RouteConversationToModuleOutcome.AlreadyProcessed`. That is a worse failure than the current
exception, just a quieter one.

## Scope

- `RouteConversationToModuleHandler.AddSystemMessageAndSaveAsync` (or its caller, `FinishStepAsync`/
  `ContinueActiveTaskAsync`/`HandleAsync` — read the actual call chain to decide the right level, the
  same way `CloseConversationHandler.HandleAsync` is the layer that owns its own retry, not
  `CloseAndSaveAsync`) needs the identical "catch `ConversationConcurrencyConflictException`, reload,
  retry once, then a clean conflict outcome" shape those two handlers already use.
- This means routing the conversation's own save through `IConversationRepository.SaveAsync` — the
  port that actually translates the EF exception — rather than relying on `EfInboxChecker`'s own
  `SaveChangesAsync()` to flush an entity it knows nothing about. Read how `SaveAsync` and the outbox
  enqueue interact for the *ordinary* message-send path (`MessageBatchWriter`, `CLAUDE.md` rule 4 — a
  state change and its integration event commit in one transaction) before restructuring this, since a
  `Conversation` save and its own outbox enqueue (`outbox.Enqueue(...)` a few lines above, already
  cleared via `ClearDomainEvents()`) must stay atomic with each other — moving the save to a different
  call site must not split that.
- **The inbox record's own atomicity with the conversation save must be preserved.** The whole point
  of doing both in one `SaveChangesAsync` was likely to keep "the message was added" and "this trigger
  was recorded as processed" atomic — check whether that invariant still holds once the conversation
  save moves through a different port, or whether the retry needs to re-check-and-re-record the inbox
  entry too on the retried attempt (it should not double-record if the first attempt's inbox insert
  actually succeeded while the conversation update failed in the same batch — read carefully whether
  Postgres's own batch semantics mean the whole `SaveChangesAsync` rolled back together, which the
  existing sequential duplicate-delivery test's own assertion — "the second call's own work is
  discarded together" — suggests it does).

## Where this is likely to go wrong

- **Do not just widen a catch block anywhere to make the error go away.** The failure mode this item
  guards against is exactly that: a silent swallow that quietly loses a visitor's own message under
  concurrent redelivery, which is worse than the loud failure today.
- **A retry must reload the `ChatBookingTask`/module-task state too, not only the `Conversation`.**
  The module task's own state (`ChatBookingTask`, `ago-calendar`, unrelated to this item — already
  fixed correctly in `25-32`) is a separate aggregate in a separate database; only the `Conversation`
  side needs the retry this item describes.
- **Verify the fix against a genuine concurrent-delivery reproduction**, not only a sequential one —
  `Task.WhenAll` on two calls into the real handler (or as close to it as a test can reach), each
  staging a real system-message add against the same loaded `Conversation`, is what actually exercises
  the `xmin` race; a sequential test proves nothing here, as this item's own discarded first attempt
  found out directly.

## Done when

- [ ] `RouteConversationToModuleHandler`'s own module-task-routing path retries once on a genuine
      `Conversation` concurrency conflict, matching `CloseConversationHandler`'s established shape,
      rather than letting a raw EF exception propagate to `ModuleTaskConsumer` and silently drop the
      delivery.
- [ ] A test drives two genuinely concurrent deliveries against the same conversation through this
      real handler (not just `EfInboxChecker` in isolation) and asserts both succeed correctly (one
      message added and the other's retry either succeeds too or lands the outcome the retry policy
      promises) with no unhandled exception.
- [ ] The inbox/idempotency guarantee still holds after the fix — a genuinely duplicate delivery (not
      a concurrency race, an actual redelivery of an already-fully-processed message) is still
      recognised and skipped, proven by a test.
- [ ] Re-verified against the live reproduction: picking a worker in the booking flow (site
      `01a06262-d4f0-7fb6-94e0-9ff702db8a43`, calendar `01a084eb-16be-7865-bcc1-7109fda9c9d9`, worker
      `01a084ec-0c41-78c9-b959-04cb7c1bebf9`) reaches the time-picker step instead of the "a person will
      take over" fallback.
