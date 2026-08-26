# ADR-0066: An auto-reply fires only when nobody is on duty, and is authored by the system

- **Status**: Accepted
- **Date**: 2026-08-27
- **Stage**: 14 (`backlog/14-04-offline-auto-reply.md`)
- **Related**: `adr/0016` (RBAC — `site:configure` gates this too), `adr/0017` (the inbox ledger is
  the idempotency mechanism), `adr/0020` (derived, best-effort notifications bypass the outbox — this
  one deliberately does *not*), `adr/0029` (per-site widget config, the cached-DTO precedent this
  extends), `adr/0055` (a channel message becomes an ordinary AGO Chat message)

## Context

`14-04` asks for one sentence of behaviour: *when no operator is available, a visitor gets an
automatic reply instead of silence*. Two words in that sentence are doing a great deal of work, and
neither has an obvious answer.

**"No operator is available" is not one condition.** The codebase already distinguishes at least
three, and they are genuinely different situations:

1. **Nobody is on duty.** No `operators` row for the site has `status = 'Online'`. The shop is closed.
2. **Everybody is full.** Operators are online, but every one of them is at
   `active_chats >= capacity`, so `4-02`'s assignment engine (`SkipLockedAssignmentClaimer`) finds no
   candidate and the conversation stays `Waiting`.
3. **Nobody has picked it up yet.** The conversation is `Waiting` — which is where it sits for the
   fraction of a second between being started and being assigned, and also where it sits for the
   duration of case 1 or case 2.

From inside the waiting queue, all three look identical: `state = 'Waiting'`. The assignment engine
itself does not need to tell them apart, because its answer to all three is "try again next tick."
An auto-reply has to tell them apart, because its answer must be different for each.

**"An automatic reply" is a message.** That is the whole appeal of it — it means one mechanism reaches
the widget, `14-02`'s MAX, `14-03`'s SMS and anything `14-05` adds, because those channels already
converge on the message. It is also the whole problem: a message arriving is what triggers the
evaluation that produced it.

## Decision

### 1. The trigger is "nobody is on duty **and** nothing has picked this up" — cases 1 and 3 together, never case 2

The auto-reply fires when **the conversation is still `Waiting`** *and* **no operator at that site is
`Online`**. Both are read from Postgres, inside the same unit of work as the write they authorise
(`CLAUDE.md` rule 8).

**Case 2 is deliberately excluded, and it is the interesting half of this decision.** An online
operator who is momentarily at capacity is a human being who will get to this conversation, probably
within a minute; telling that visitor "we are closed, we will reply in the morning" would be *false*,
and it would land seconds before a real answer. An auto-reply that talks over a person about to
respond is worse than no auto-reply at all — which is exactly what makes "everyone is busy" a queue
wait rather than an absence.

The concrete consequence is that `IOperatorRepository.AnyOnlineForSiteAsync` is deliberately
**weaker** than the assignment engine's own candidate query sitting a few lines away in
`SkipLockedAssignmentClaimer.FindCandidateOperatorAsync`: the engine asks for `Online` **and**
`active_chats < capacity`, this asks only for `Online`. Two predicates that look like they should be
shared, and must not be. Both read the same `operators.status` column, so the two can never disagree
about who is on duty.

**The alternatives, and why each loses.**

- *Fire on `Waiting` alone.* Simplest, and wrong for the reason above: it fires in the gap before the
  assignment engine's next tick, on a fully-staffed site, every time.
- *Fire on "no candidate with capacity".* This is case 2, and it is the mistake this ADR exists to
  name.
- *Fire after a delay ("nobody answered within N seconds").* Genuinely defensible, and rejected as a
  second mechanism: it needs a scheduler, a per-conversation timer that survives a restart, and a
  cancellation story for the operator who answers at second N-1. It also answers a different product
  question — "we are slow" rather than "we are closed" — and the item is called *offline* auto-reply.
  Named here as the obvious next variant if a real tenant asks for it.
- *Read presence from Redis instead of `operators.status`.* Rejected on `CLAUDE.md` rule 8 and
  `adr/0009`: this read decides whether to write, and Redis is never a source of truth.

### 2. The reply is authored `MessageAuthorKind.System`, and that is the loop guard

`Conversation.AddSystemMessage` is the only way a `System`-authored message can exist, and it takes no
author-kind parameter — the value is hardcoded. `SendOfflineAutoReplyHandler` acts only on
`MessageAuthorKind.Visitor` and refuses everything else, before any I/O.

Together those two facts make a second reply **unreachable**, not merely unlikely. There is no
ordering, retry, redelivery or concurrent-replica interleaving that produces one, because there is no
code path that could: the only thing that can trigger an evaluation is a visitor message, and an
auto-reply structurally cannot be one.

This is stated as a decision rather than an implementation detail because the alternatives are all
worse in the same way — they are *runtime* guards that a future change can quietly step around:

- *A `generated_by_bot` boolean on `messages`.* A column a handler must remember to check. The check
  can be forgotten; a type cannot.
- *A per-conversation "already auto-replied" flag.* Answers a different question (once per
  conversation, not once per trigger), and needs its own reset story for a conversation that goes
  quiet again the next day.
- *Authoring the reply as `Operator`.* Would remove the guarantee outright *and* be a lie — there is
  no operator, which is the entire precondition for sending. It would also have to invent an operator
  id for a column whose only job is to record who said something.

The proof is a test that removes the guard and watches a reply trigger a reply, against a real
RabbitMQ that really does deliver the reply's own `MessageAccepted` back to the consumer that wrote
it (`OfflineAutoReplyDeliveryEndToEndTests`), not an argument.

`MessageAuthorKind` gaining a member is additive at every level that matters: `messages.author_kind`
is `text` holding the member name, so there is no schema change, and both clients treat an
unrecognised kind as "not mine" and render it on the incoming side — which is where a message nobody
on this side wrote belongs anyway.

### 3. The reply is produced by a consumer of `MessageAccepted`, not by the send path

`SendVisitorMessageHandler` is upstream of the write — since `4-05` it enqueues onto an in-process
pipeline and never touches Postgres — so a reply produced there would be deciding against a
conversation state that had not been committed yet. Reacting to `MessageAccepted` means the trigger is
durable before anything looks at it, and the reply travels back out through the fan-out
(`ConnectionFanoutConsumer`) that already delivers every other message. One mechanism, every channel.

**Idempotency is `adr/0017`'s inbox ledger and nothing new.** The reply row and its own outbox row are
staged on the consumer's `DbContext`, and `IInboxChecker.TryRecordAndSaveAsync(triggerMessageId,
"offline-auto-reply")` performs the single `SaveChangesAsync` that commits all three together. A
redelivery re-stages the identical work, loses on the composite key, and persists **nothing** — not
the reply, not the outbox row. `SendOfflineAutoReplyHandler` therefore never calls
`IConversationRepository.SaveAsync`; a second `SaveChangesAsync` would split the two into different
transactions and let a reply survive a duplicate check meant to void it.

A derived `ClientMessageId` (the `adr/0055` shape) was considered as a second, index-backed guard and
left out: the inbox key already covers the two-replicas-race case, and a second dedup mechanism that
is never the one that fires is a mechanism nobody maintains.

### 4. The rule shape is a fallback plus an ordered keyword list, and the LLM variant is named, not built

`OfflineAutoReplySettings` is `Enabled`, a required `FallbackReply`, and up to twenty
`OfflineAutoReplyRule`s. Matching is: first rule whose keyword occurs in the message text
(`OrdinalIgnoreCase` substring), else the fallback.

- **A fallback, not rules alone.** A rule list answers only the messages somebody anticipated and
  answers the rest with the silence the feature exists to remove. So `FallbackReply` is *the* reply
  and the rules are refinements of it — which is why an enabled configuration with no fallback is
  refused rather than accepted as a no-op.
- **First-match-wins in the tenant's own order**, not longest-keyword-wins: the operator can act on
  list order, and cannot see keyword length in the editor.
- **Substring, not regex.** A tenant-supplied regular expression evaluated on the server is a
  denial-of-service surface (catastrophic backtracking) for a feature that gains nothing from one.
- **Ordinal, not culture-aware**, so the outcome does not depend on which node's locale ran the match
  — the same class of invisible per-node disagreement `CLAUDE.md` rule 11 rejects for timestamps.
- **No decision tree.** It would need per-conversation state (which node are we at) — a second thing
  to persist, invalidate and reason about under redelivery — for a v1 whose whole purpose is saying
  something rather than nothing while the shop is closed.

**The LLM-backed variant stays a named future item**, per the backlog item's own instruction: it is a
real per-message external-API cost and a different pricing tier, and `CLAUDE.md` forbids inventing a
per-token figure. A future item names a real provider and a real, cited cost — the research discipline
`adr/0026` applied to VPS hosting — before anyone commits to building it.

### 5. The toggle is `site:configure`, read cache-aside, and evicted on write

No new permission for a boolean: `site:configure` already reads as "configure this site" and already
gates `5-08`'s site-wide conversation view and `11-01`'s widget appearance. This is its third caller.

The toggle and its script ride the existing cached `SiteConfigDto`, populated identically by
`GetSiteConfigByPublicKeyHandler` and `GetSiteConfigByIdHandler` — the additive-field precedent
`11-01` set, not a second cached object. It is not put on the wire by the visitor handshake:
`VisitorSessionResponse` is built field by field and a tenant's scripted answers are not on that list.

Making that read *live* required fixing something that had been half-true since `5-01`:
`SiteCacheInvalidationConsumer` evicted only `SiteCacheKeys.ForPublicKey`, never `ForSiteId`, so the
id-keyed entry — the one this feature reads on every message — survived a settings write for its full
five-minute TTL. `caching.md`'s claim that a config write is evicted well before the TTL was true of
one key out of two. It now publishes both.

## Consequences

- **A visitor can receive a message from a shop that never typed one.** The widget labels it
  ("Automatic reply") rather than passing it off as a person; the console renders it on the incoming
  side. Nothing about this is hidden from either side.
- **`MessageAuthorKind` now has a third member**, and every future `switch` over it has a third case.
  The two existing readers were written as "operator, else incoming", so both were already correct.
- **The unread counter counts an auto-reply against the visitor**, which is right — they have not read
  it — and never against the operator, which is also right.
- **A dead-letter is possible and is not silent.** A handler failure (site row missing, database
  unavailable) is thrown, retried by `RabbitMqEventConsumer`, and dead-lettered to
  `offline-auto-reply.dlq` after `MaxAttempts`. A *decision not to reply* is not a failure and is
  acked immediately.
- **Every visitor message now costs one extra consumer hop** on every site, including the
  overwhelming majority with the feature off. The cost of a skip is one cached config read and no
  database work at all — the flag is checked before the conversation is loaded. Unmeasured; if a
  Stage 7 load test finds it, the cheap fix is filtering on the topic rather than in the handler.
- **The condition is stated in the console UI**, because an operator who does not know that a busy
  colleague counts as online will read a missing reply as a bug.
