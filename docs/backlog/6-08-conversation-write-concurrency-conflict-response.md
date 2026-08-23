# Translate conversation-close/assign concurrency conflicts to a clean 409, not a raw 500

- **Stage**: 6
- **Status**: done
- **Depends on**: nothing — a real bug found under `6-06`'s load run, independent of that item's own
  webhook scope

## Goal

`POST /api/v1/conversations/{id}/close` (and `JoinConversationAsync`'s own assignment path) stop
surfacing `DbUpdateConcurrencyException` as an unhandled `500`. After this item, a genuine optimistic-
concurrency race on a conversation row produces either a clean RFC 7807 `409 Conflict` or a single
transparent retry, matching `docs/conventions/api-design.md`'s own error convention.

## Context to read first

`docs/backlog/6-06-webhooks-load-proof.md`'s "Other real findings" section — hit 10 times across that
run's ~200+ close/assign calls (~5%) under concurrent load: a message send updates a conversation row's
`xmin`, and a concurrent close/(re)assign reads a now-stale version of the same row, producing a raw,
unhandled `500` instead of a meaningful response. `docs/conventions/api-design.md`'s error-response
convention (RFC 7807 problem details) — the shape every handled error already returns; this is a gap
where one currently isn't handled at all.

## Scope

- `CloseConversationHandler` / `AssignConversationHandler` (wherever the concurrency race actually
  surfaces — confirm both call sites named in `6-06`'s report): catch `DbUpdateConcurrencyException` and
  either retry once against a freshly-reloaded row (if the operation is safely idempotent against a
  concurrent write) or translate it to a clean `409 Conflict` problem-details response.
- A test that reproduces the race deterministically (two concurrent writers against the same
  conversation row, one committing while the other holds a stale read) and asserts the clean outcome,
  not a raw `500`.

## Out of scope

- Any change to the optimistic-concurrency mechanism itself (`xmin`-based) — this item is about the
  *response* to a detected conflict, not the detection mechanism.
- A broader audit of every other handler for the same unhandled-exception gap — scoped to the two call
  sites `6-06`'s report actually observed failing; a wider sweep is separate work if ever wanted.

## Done when

- [x] `DbUpdateConcurrencyException` on conversation close and on assign no longer surfaces as a raw
      `500` — either a single transparent retry succeeds, or a clean `409 Conflict` (RFC 7807 shape) is
      returned. Retry-once chosen for both (safe because `Close()`/`AssignTo()` re-validate their own
      invariant against fresh data on reload — a genuine business conflict still surfaces as the
      existing error, never silently papered over); a second conflict inside the retry becomes
      `Conversation.ConcurrencyConflict`, mapped to `409`.
- [x] A test reproduces the race against a real concurrent write and proves the new behaviour, not
      merely asserting the exception type is caught. `ConversationConcurrencyConflictTests` (3 tests,
      real Postgres container) injects a genuine, already-committed concurrent write via a second
      `DbContext` at the exact moment the handler under test calls `SaveAsync`.
- [x] `api-design.md`'s error-response table, if it doesn't already list `409` for this case, updated to
      name it. Added as a "Shipped in `6-08`" note, matching the file's existing narrative convention.

## Shipped in

`feat/6-08-conversation-write-concurrency-conflict-response` (`ago-chat`). New
`ConversationConcurrencyConflictException` declared at `IConversationRepository`'s own port boundary
(`Ago.Chat.Application.Abstractions`) rather than letting EF Core's exception type leak past the
dependency rule. A real bug found and fixed via the test itself: the first retry attempt silently
returned the same stale, already-mutated tracked entity on reload (EF's identity map hands back the
tracked instance rather than re-querying after a failed `SaveChangesAsync`) — fixed with
`db.ChangeTracker.Clear()` in the adapter's catch block. Full test suite: 374/374 passing.

## Open questions

None — the race, its two call sites, and the target response shape are already named by `6-06`'s report
and `api-design.md`'s existing convention.
