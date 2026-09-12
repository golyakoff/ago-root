# 25-67 · Two "first contacts" for the same new visitor race on `PK_visitors`

- **Stage**: 25
- **Status**: ready
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

## Done when

- [ ] Two concurrent `StartConversationHandler.HandleAsync` calls for the same new `visitor_id` never
      raise an unhandled exception - proven by a concurrency test, fails-before against the unpatched
      handler.
- [ ] Exactly one `Visitor` row exists afterward, and both callers' results agree on it.
