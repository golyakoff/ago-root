# Console: queue, conversations, presence, history

- **Stage**: 5
- **Status**: done
- **Depends on**: `5-06-console-framework-and-scaffold.md`

## Goal

An operator can log in and actually work: see the waiting queue for their site, claim or receive an
assigned conversation, send and receive messages in real time, see who else is online, and page back
through history. This is the console half of Stage 5's own done-when bar - without this, `5-01`
through `5-06`'s backend work has no real client proving it end to end.

## Context to read first

`realtime.md` in full - the client protocol section (`clientMessageId`, `sequence`-based ordering and
resume, the `reconnect(after: jitteredDelay)` server hint) and the connection-registry/presence
sections describe exactly what this UI must implement, not a generic chat-UI design. `Ago.Chat.Api/
wwwroot/dev-harness.html` - the existing manual verification harness already exercises every hub method
this console needs (`JoinConversationAsync`, `SendMessageAsync`, `GetHistoryAsync`); read it as the
reference implementation of the protocol, not as something to literally port. `4-02`'s
`ConversationAssignedToOperator` event and `AssignConversationHandler` - how a conversation actually
reaches an operator (automatic assignment engine, `4-01`-`4-04`; this console does not itself claim
conversations out of a queue, since `adr/0021`'s engine already does that - confirm this understanding
against `vision.md` rather than assuming a manual "claim" button is wanted).

## Scope

- Login-gated shell (from `5-06`) routes into: a queue/dashboard view (conversations currently waiting
  or assigned to this operator, per-site), a conversation view (message thread, send box, typing/
  presence of the other participant), and reconnect handling matching `realtime.md`'s own protocol
  (resume by last known `sequence`, exponential backoff with jitter on disconnect, obey the server's
  `reconnect` hint).
- Presence: which of this operator's own conversations have a currently-connected visitor, using
  whatever the hub already exposes - do not invent a new endpoint if `realtime.md`'s existing surface
  already answers this.
- `clientMessageId` wired up for real on the send path - `realtime.md` names this as "still a design
  intent, not wired up" as of `3-03`; this is the first client that actually needs retry-dedup badly
  enough to justify it, so this item is where it finally ships (server-side support already exists per
  `realtime.md`'s wire-contract description - confirm and wire the client half, or flag if server-side
  work is still needed and route it back as a small `ago-chat` addition).
- History paging (keyset, `beforeSequence` cursor - `api-design.md`'s pagination rule, already how
  `GetConversationHistoryHandler` works server-side).

## Out of scope

- Attachment upload/view in the message thread - `5-08`.
- Admin/supervisor views (see every site's conversations, manage operators/roles) - `5-08`.
- Manually claiming a conversation from the queue, if `4-02`'s automated engine turns out to be the
  only assignment path `vision.md` calls for - confirm during this item's own design pass rather than
  building a claim button speculatively.

## Done when

- [x] Manually verified against the local cluster (`CLAUDE.md`: UI changes are exercised live, not just
      asserted): an operator logs in, a visitor (via the existing dev harness or a Stage-5 widget build
      if `5-09` has landed by then) starts a conversation, the operator sees it, both sides exchange
      messages in real time, and a mid-conversation reconnect on either side resumes with no gap and no
      duplicate - the same bar `3-03`'s own manual verification already proved for the harness, now
      proved for the real console.
      Verified against the real docker-compose stack: real Keycloak login, a fresh visitor conversation
      via `dev-harness.html` picked up by `4-02`'s real automatic assignment engine and surfaced in the
      console's queue, live two-way message exchange (console <-> harness), and three real
      `Ago.Chat.Api` process kills/restarts (same fixed `Auth__SigningKey` as `5-09`'s note) each
      resuming cleanly with no gap or duplicate on both sides - `local-dev.md`'s own "Shipped in `5-07`"
      note has the detail, including two real bugs found live and fixed
      (`dev-harness.html`'s broken 2-argument `SendMessageAsync` call, and a React-StrictMode
      connection-lifecycle race in `OperatorConnectionProvider`).
- [x] `clientMessageId`-based dedup proven: a message retried after a simulated flaky connection does
      not appear twice.
      Server-side support did not exist (confirmed against `realtime.md`'s own "not wired up" note) -
      wired up as this item's own companion `ago-chat` change (`Conversation.AddMessage`'s in-memory
      dedup check, a migration adding `messages.client_message_id` plus a partition-widened unique
      index). Proven twice: two real `SendMessageAsync` invocations with the same `clientMessageId`
      returned the identical `sequence` and left exactly one row in `messages`; the console's own
      `OperatorConnection.sendMessage` reuses the failed attempt's `clientMessageId` on retry
      (`SendOutcomeUnknownError`'s own doc comment).
- [x] History paging loads older messages without re-fetching the whole conversation.
      Proven directly against a real conversation: `GetHistoryAsync` with `pageSize=2` returned the two
      newest messages plus a `nextBeforeSequence` cursor, and a second call with that cursor returned
      the next-older two - no re-fetch of the whole conversation. `ConversationPage`'s "Load older
      messages" button drives the same call.
- [x] Unit tests for the protocol-handling layer (sequence ordering, dedup, backoff) - matching the
      widget's own testing bar in the `embeddable-widget` skill, since the console's realtime client
      code is solving the identical protocol problem independently.
      `ago-console/src/realtime/protocol/{backoff,dedup,sequence}.test.ts` - 12 tests, deliberately the
      same shape as `ago-widget`'s own `protocol/*.test.ts` (same class names, same test cases), since
      both clients solve the identical problem.

## Open questions

None - scope follows directly from `realtime.md`'s already-shipped protocol; the one genuine design
question (manual claim vs. automatic-only assignment) is resolved by reading `vision.md` during the
item rather than needing to block on it now.
