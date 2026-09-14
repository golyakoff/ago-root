# 25-67 · Two "first contacts" for the same new visitor race on `PK_visitors`

- **Stage**: 25
- **Status**: done — `ago-chat#286`. Both Done-when boxes closed after independent review.
- **Found**: 2026-09-12, while landing `25-68` (one open conversation per visitor) -
  `StartConversationConcurrencyTests`'s own stress test
  (`ManyConcurrentStartsForTheSameVisitor_AllAgreeOnExactlyOneConversation`) originally exercised a
  brand-new visitor and crashed on `PK_visitors` before it was rewritten to seed the visitor ahead of
  time, deliberately out of that item's scope (one promise: no two open conversations for one
  visitor, not "every race in `StartConversationHandler` at once"). The full crash, unpatched:
  `Npgsql.PostgresException 23505: duplicate key value violates unique constraint "PK_visitors"`.

## What is actually true

`StartConversationHandler.HandleAsync`'s visitor half has the identical read-then-write shape its
conversation half had (fixed by `25-68`): `visitors.GetByIdAsync` returns
null for a genuinely new visitor, and two concurrent callers for the *same* `visitor_id` - two tabs
opening a widget for the first time, sharing whatever `visitor_id` the host minted before either has
loaded - both see null and both try `new Visitor(...)` + `SaveAsync`. `VisitorRepository.SaveAsync`
inserts unconditionally; nothing catches the resulting primary-key violation, so it reaches the
caller as a raw, unhandled `DbUpdateException` - a `500`, not a graceful fallback to the visitor
either request actually wants to end up using.

Unlike the conversation race, there is no ambiguity about "which one wins" to resolve here - a
`Visitor` row has no fields worth reconciling between two racing inserts (both callers constructed it
from the same `visitor_id`/`site_id`; only the emoji pair could differ, and decision 4 already says
repeats are fine and nothing reads "this visitor's own pair" as a decision worth serializing on). The
fix is narrower than `25-68`'s conversation half: catch the constraint violation, discard the local
copy, and re-read - the same "the loser returns what already committed" shape, with no case where
the winner's row needs picking over the loser's for any reason beyond "it got there first."

## Scope

- A translated exception (or reuse of an existing one, if its shape fits) for `PK_visitors`,
  raised from `VisitorRepository.SaveAsync`.
- `StartConversationHandler` catches it and re-reads via `visitors.GetByIdAsync`, mirroring `25-68`'s own
  conversation-race fix.
- A concurrency test, the same deterministic-injection shape `StartConversationConcurrencyTests`
  already uses for the conversation half, proving two concurrent first-contacts for one new visitor
  settle on one `Visitor` row and no unhandled exception.

## Out of scope

- The conversation-creation race itself - already fixed, separately.
- Anything about `ReceiveChannelMessageHandler`'s own call into `StartConversationHandler` beyond
  what this fix already covers by fixing the shared handler.

## Implementation status (worker report, 2026-09-14)

Implemented on `fix/25-67-visitor-first-contact-race` in `ago-chat` (worktree `ago-chat-25-67`,
based on `origin/main` at `6b29011`, which already carries `25-68` and `25-69`):

- `VisitorConcurrencyConflictException` (new, `Ago.Chat.Application/Abstractions/`) - mirrors
  `ConversationConcurrencyConflictException`'s own shape (`VisitorId`-keyed); no existing exception's
  shape fit, since each one is keyed to its own aggregate's id type.
- `VisitorRepository.SaveAsync` translates `PK_visitors`'s unique violation into it, one catch clause,
  scoped to that constraint name only - no second `DbUpdateConcurrencyException` clause alongside it,
  since `VisitorConfiguration` configures no `xmin`/`IsRowVersion` for `Visitor`.
- `StartConversationHandler.HandleAsync` catches it once around the existing `visitors.SaveAsync`
  call and re-reads via `visitors.GetByIdAsync`, with the same unreachable-by-construction `winner is
  null` guard `25-68`'s own conversation-race catch uses.
- No new migration - `PK_visitors` already exists, unconditionally, unlike `25-68`'s
  `ix_conversations_one_open_per_visitor`.
- `StartConversationConcurrencyTests.ManyConcurrentStartsForTheSameVisitor_AllAgreeOnExactlyOneConversation`
  restored to its original brand-new-visitor shape (no more pre-seeded `Visitor`), plus a new
  deterministic two-way race test mirroring the conversation half's own
  `TwoConcurrentStartsForTheSameVisitor_RacedMidSave_...`.
- Fails-before proven: both tests raise the raw, unhandled `Npgsql.PostgresException 23505` on
  `PK_visitors` against the unpatched handler/repository; both pass after the fix.
- Full command set green: `dotnet format --verify-no-changes` clean, `dotnet build -c Release` 0
  warnings/0 errors, `dotnet test -c Release` 0 failures across all six test assemblies (Domain 692,
  Application 1239, FakeCrm 21, Architecture 46, Concurrency 88, Integration 1196).

Neither `Done when` box below is ticked by this note - that is the managing session's own call, after
its independent review, per `CLAUDE.md` rule 14. `docs/roadmap.md` and `docs/adr/README.md` are
untouched.

## Done when

- [x] Two concurrent `StartConversationHandler.HandleAsync` calls for the same new `visitor_id` never
      raise an unhandled exception - proven by a concurrency test, fails-before against the unpatched
      handler. — `TwoConcurrentFirstContactsForTheSameNewVisitor_RacedMidSave_TheLoserAgreesOnTheWinnersVisitor`,
      a real deterministically-injected race under real Postgres; independently re-run and confirmed by
      the managing session, not just the worker's claim.
- [x] Exactly one `Visitor` row exists afterward, and both callers' results agree on it. — asserted
      directly (`Assert.Single(visitorRows)`) and via the restored
      `ManyConcurrentStartsForTheSameVisitor_AllAgreeOnExactlyOneConversation` eight-way stress test,
      which now also asserts the visitor count settles to one, not only the conversation count.
