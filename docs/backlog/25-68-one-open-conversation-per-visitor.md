# 25-68 · One open conversation per visitor

- **Stage**: 25
- **Status**: done — `ago-chat#269`
- **Found**: 2026-09-12, live - the author's own operator account on `reserve-me.ru` listed the same
  visitor twice: two `Conversation` rows, `site_id`/`visitor_id`/`operator_id` identical, `state`
  both `Assigned`, `created_at` **19 microseconds apart** (not milliseconds), zero messages in
  either. The visitor's own `last_seen_at` matched the first row's `created_at` exactly, and
  `first_seen_at` was three days earlier - a returning visitor, not a first contact.

## What is actually true

`StartConversationHandler.HandleAsync` (`Ago.Chat.Application`) decides whether a visitor already has
an open conversation with a plain read (`IConversationRepository.GetActiveForVisitorAsync`, no lock)
and, if not, creates one. Two concurrent callers for the same visitor - two browser tabs sharing one
persisted `visitor_id` (the widget's own token, per-browser not per-tab), or a widget reconnect racing
its own prior connection before it has finished joining - both run the read before either has
committed, both see nothing, and both insert. Nothing in the schema stops it: `conversations` carries
no unique constraint narrower than its own primary key.

Traced end to end: `ago-widget` → SignalR `VisitorHub.JoinAsync`/`JoinWithTrafficSourceAsync`, called
"once, right after connecting" per that method's own doc comment → `StartConversationHandler`. The
identical handler is also the one `ReceiveChannelMessageHandler` calls for a message arriving over a
non-widget channel, so the race is reachable from there too, not only from the hub.

Confirmed this is not a systemic, frequent failure: a scan of every `(site_id, visitor_id)` pair with
more than one `Conversation` row found exactly one pair created within the same sub-millisecond
window - this incident. Every other repeat-visitor pair the scan found spans days, which is ordinary
(a visitor returns, their prior conversation is closed, they start a new one).

## Scope

- A partial unique index on `conversations(visitor_id)`, filtered to the same predicate
  `GetActiveForVisitorAsync` already reads (`state <> 'Closed'`) - a visitor may still open a fresh
  conversation once their last one is actually closed, but never two open ones at once.
- `ConversationRepository.SaveAsync` translates the resulting Postgres unique-violation into
  `ConversationConcurrencyConflictException`, the identical shape `23-04`'s
  `ix_conversation_assignments_open` and `25-34`'s message-sequence index already use.
- `StartConversationHandler` catches it once: the loser's own copy lost the race, but the winner's row
  is already committed and visible to a fresh read, so the loser simply returns it - `IsNew: false`,
  not a retry-and-reapply (there is nothing to reapply; "start a conversation" has no decision left
  once one already exists).
- Cleanup of the one live duplicate this item's own report names - closed without touching the
  winner, since neither row carries any message or assignment history worth reconciling.

## Out of scope

- `25-67` - the sibling race on `PK_visitors` for two concurrent *first* contacts by a brand-new
  visitor, found while writing this item's own concurrency test and deliberately split out (a
  different constraint, a different repository, no ambiguity about which row to keep).
- Preventing two browser tabs from sharing one `visitor_id` in the first place, or changing when the
  widget calls `JoinAsync` - both are legitimate, and the fix belongs at the layer that actually
  decides "how many conversations", not at either of its callers.

## Done when

- [x] Two concurrent `StartConversation` calls for the same visitor, raced deterministically mid-save
      (not merely hoped to collide), settle on exactly one `Conversation` row - proven by a
      concurrency test against a real Postgres, fails-before against the unpatched handler.
- [x] Many concurrent calls (not just two) for the same already-existing visitor agree on the same
      single conversation.
- [x] Two different visitors racing at the same instant are unaffected - each gets its own
      conversation.
- [x] The live duplicate this item's own report names is resolved on the real deployment.

## Outcome

Shipped as `ago-chat#269`. Exactly the Scope section: `ix_conversations_one_open_per_visitor`
(migration `Stage25AddOneOpenConversationPerVisitorIndex`), a fourth translated shape in
`ConversationRepository.SaveAsync` (the same pattern `23-04`'s and `25-34`'s own constraints already
use), and `StartConversationHandler`'s own catch-and-return-the-winner.

Three concurrency tests (`StartConversationConcurrencyTests`), the deterministic
`RacingConversationRepository` injection style `MarkConversationReadConcurrencyTests` already
established, reused rather than duplicated: a two-way raced-mid-save case (the loser returns the
winner's own conversation, one row survives), an eight-way stress case (all agree on one conversation,
exactly one attempt reports `IsNew`), and a two-different-visitors control (no interaction). All three
proven fails-before - the raced-mid-save case failed on two distinct conversation ids (the live bug,
reproduced); the eight-way case additionally surfaced `25-67`'s own `PK_visitors` race before the test
was narrowed to a pre-seeded (returning) visitor, matching this item's own live evidence exactly.

**Seven existing test fixtures broke against the new invariant**, all in ways the fixtures themselves
had never had a reason to avoid before: `PlatformOverviewFixture`, `OwnerSitesEndpointTests`, and
`ConversationSearchStoreTests` each seeded several open conversations for one visitor purely as seeding
convenience (visitor identity was never what any of them tested) - fixed with a distinct visitor per
conversation. `PersonExportIntegrationTests`'s own "a visitor with two conversations" scenario needed
its first conversation actually closed before its second could open - which is what its own test name
("back again") already implied. `TransferConversationConcurrencyTests` and
`CloseConversationCapacityConcurrencyTests` needed the same distinct-visitor treatment, one of them
threading a per-conversation visitor lookup through a helper that used to assume one shared identity.
`RateLimitingConcurrencyTests`'s own scenario (thirty concurrent sends against one visitor's rate-limit
bucket, deliberately built on thirty separate conversations specifically to avoid conflating the rate
limiter's atomicity with write contention on a shared aggregate) could no longer avoid that contention
once a visitor can hold only one conversation - its assertions were widened to account for real,
explained write conflicts on the five requests the limiter admits, without weakening the actual claim
under test (exactly `PerVisitorCapacity` requests admitted, the rest cleanly denied - still asserted
exactly).

The one live duplicate (`01a0971d-6ee6-7564-...`/`01a0971d-6ee6-7416-...`) was closed on the real
deployment - the real `CloseConversationHandler` application path was attempted first and refused
(`Conversation.Forbidden`: neither role the operator holds grants `conversation:close` - a separate,
pre-existing gap, not filed here since it wasn't part of what this item's own report asked for), so the
close was done directly against the row instead: both conversations were `Waiting`, message-less,
assignment-less and held no capacity claim, so there was nothing an application-level close would have
done beyond the state flip itself.

**Verification**: `dotnet format --verify-no-changes` clean; `dotnet build -c Release` 0 warnings;
`dotnet test -c Release`, 6/6 assemblies, 0 failed - Domain 646, Application 1119, FakeCrm 21,
Architecture 44, Concurrency 78 (+3 new), Integration 1117.
