# Fix: the widget's own visitor-side send never worked against a real server

- **Stage**: 5
- **Status**: done
- **Depends on**: nothing — `ago-widget` only, no product-side prerequisite

## Goal

A visitor typing a message into the embedded widget and hitting Send currently fails every single
time against a real server, silently on the wire and confusingly in the UI ("Failed to send.", no
further detail). After this item, a visitor send reaches `VisitorHub.SendMessageAsync`, succeeds, and
is delivered to the operator, proven live against the real public deployment, not just against a
mock or a local harness that never exercised this exact code path.

## How this was found

Found live while verifying `8-02` (public demo page) — the first time the widget's own real client
code ever ran an end-to-end send against a real, deployed `Ago.Chat.Api`. A visitor sent a message
through `https://demo-shop1.reserve-me.ru`; the bubble rendered, then flipped to "Failed to send.";
the operator console, watching the same conversation, never saw it arrive.

Diagnosis, in order:

- Server-side API logs showed no exception at all for the send attempt, and — decisively — zero
  `INSERT INTO messages` in the database despite the real, repeated attempts. Whatever was failing,
  it was failing before `SendVisitorMessageHandler` ever ran.
- A raw hub invocation, replicated by hand over the real `wss://chat.reserve-me.ru/hubs/visitor`
  connection with the exact 3 positional arguments the widget's own `connection.ts` sends
  (`conversationId, body, attachmentId`), reproduced the failure deterministically:
  `{"type":3,...,"error":"Failed to invoke 'SendMessageAsync' due to an error on the server."}` —
  every time, no server-side log entry either.
- The same invocation with a 4th argument (`clientMessageId`, a real GUID) succeeded cleanly every
  time: `{"type":3,...,"result":1}`, message delivered, `MessageReceived` broadcast to the operator.

Root cause, confirmed by reading the code, not guessed: `VisitorHub.SendMessageAsync` is a
4-parameter hub method (`5-07`: `conversationId, body, attachmentId, clientMessageId`) — its own
comment already flagged this: *"the position (not just optionality) matters for every caller built
before this shipped."* `ago-widget`'s `connection.ts`/`protocol/dedup.ts` had already built the
client-side half of `clientMessageId` support (`newClientMessageId()`, generated per send, kept in
`widget.ts`'s own `pendingSends` for the optimistic-bubble echo) — but the actual wire wasn't
finished: `VisitorConnection.sendMessage` never accepted the id, so `widget.ts`'s `dispatchSend`
generated it, stored it locally, and then called `connection.invoke("SendMessageAsync", ...)` with
only 3 arguments. This server's SignalR dispatcher does not fill a missing trailing argument from
the C# default value for a client-supplied invocation with fewer arguments than the method declares
— every real send failed at the hub-invocation layer itself, before the handler, before any
application-level logging.

`ago-console`'s own `operatorConnection.ts` was never affected — it already threads `clientMessageId`
through correctly (`sendMessage(conversationId, body, clientMessageId, attachmentId)` →
`invoke("SendMessageAsync", conversationId, body, attachmentId, clientMessageId)`), which is why
operator-side sends worked throughout and only the visitor-side widget was broken.

**Blast radius**: as shipped, `5-09`'s widget could never successfully send a single real message to
a real server — the exact core interaction the whole product exists for. Every previous "verified
live" claim touching the widget's send path either tested against a mock/stub transport, never
actually exercised a full send, or (most likely) never ran the built widget bundle against a real
`Ago.Chat.Api` at all before this deployment did.

## Scope

- `ago-widget/src/connection.ts`: `VisitorConnection.sendMessage` takes `clientMessageId: string` as
  a required parameter, passed as the hub invocation's 4th positional argument.
- `ago-widget/src/ui/widget.ts`: `dispatchSend` passes the `clientMessageId` it already generates
  (`newClientMessageId()`) through to `connection.sendMessage(...)` instead of discarding it.
- Corrected two doc comments (`connection.ts`'s `SendOutcomeUnknownError`, `protocol/dedup.ts`'s
  `newClientMessageId`) that predated `5-07` shipping `clientMessageId` server-side and were left
  claiming the server "does not accept one yet" — a stale premise that would have misled the next
  reader into thinking this was still an open design gap rather than a finished wire that was simply
  never connected.

## Out of scope

- Building the retry-by-same-`clientMessageId` path `SendOutcomeUnknownError`'s own doc comment
  names as still missing (`widget.ts` surfaces "not sure it sent" rather than auto-retrying) — a
  real, separate UX decision, not required to fix "sends fail every time."
- Correlating an incoming `MessageDto.clientMessageId` against the locally generated one for
  optimistic-bubble reconciliation (`widget.ts`'s `handleIncoming` still reconciles by queue order,
  not by matching the id) — the wire now carries the id both ways, but nothing reads it on this side
  yet. A real, separate improvement, not required to fix the send failure itself.

## Done when

- [x] `npm run typecheck`, `npm run lint`, `npm run test` (20 tests) all pass against the fix.
- [x] Reproduced the exact failure and its fix directly against the real hub protocol (not a mock):
      3 arguments fails deterministically, 4 arguments (with `clientMessageId`) succeeds and delivers.
- [x] Rebuilt the real widget image, redeployed it live, and re-verified through the actual UI: opened
      the widget, typed and sent a real message, no "Failed to send." — the bubble stays clean, and
      the message shows up in Postgres (`messages` table) immediately after, correct site, correct
      author.

## Open questions

None — the bug, its root cause, and the fix shape are all confirmed by reading the actual source and
reproducing the exact failure against the real protocol, not inferred.
