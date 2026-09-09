# 25-31 · A structured reply never sent `content` as a JSON string

- **Stage**: 25
- **Status**: done — `ago-widget#73`, deployed and confirmed live end to end
- **Depends on**: nothing
- **Found**: 2026-09-09, live — the author reported clicking a calendar booking choice in the widget
  and seeing "Не удалось отправить" under the echoed choice, on `golyakov.net`

## What was actually true

Every structured reply the widget ever sent from a real visitor — a booking choice, a form submission,
any click through `ui/primitives/render.ts`'s `choice_list`/`date_time_picker`/`form` handling — failed
silently, completely, and by construction: `sendStructuredReply` (`ui/widget.ts`) called
`this.dispatchSend(displayText, undefined, contentKind, { value })`, passing a **raw JavaScript
object** as `content`. `ago-chat`'s own wire contract, `MessagePayload`, is a `string` its constructor
parses as JSON (`JsonDocument.Parse`) — never an object. SignalR's JSON hub protocol serializes each
invocation argument by its own JS shape, so `{ value }` reached the server as a JSON *object* token
where `VisitorHub.SendStructuredMessageAsync`'s parameter is declared `string?` — a binding mismatch
SignalR's own dispatcher rejects **before the hub method is ever invoked**.

That is why nothing about this was ever visible server-side: no application log line (the method never
ran, so none of `Ago.Chat`'s own Serilog instrumentation ever executed), no row written (confirmed
directly against the database — a reproduced failure left only the visitor's trigger phrase and the
system's own `choice_list` prompt persisted, nothing for the reply), and a generic client-side error
("Failed to invoke 'SendStructuredMessageAsync' due to an error on the server") rather than one of
`ConversationErrors`' own specific messages, because a `HubException` — which *does* carry its message
to the client even without detailed errors enabled — was never the failure mode; SignalR's own
argument-binding rejection was.

**Live investigation, for the record.** Reproduced five times on the real production widget
(`golyakov.net`, embedding the real "АГО тест теннант" site), including after eliminating a
confounding factor found along the way (the shared/proxied IP this session's browser tooling uses was
also carrying unrelated concurrent traffic that tripped the edge's per-IP rate-limit zone — ruled out
as the cause once the failure reproduced identically from a single clean tab with no concurrent
traffic). `kubectl logs`, followed live during a reproduction, produced zero output despite confirmed
real traffic in that exact window — consistent with the request never reaching application code at
all, which is what led to reading the client's own source rather than continuing to chase server logs.

## Fix

`sendStructuredReply` now sends `JSON.stringify({ value })`. `content`'s type is tightened from
`unknown` to `string` through `dispatchSend` and `VisitorConnection.sendMessage`, so a future caller
cannot repeat this by passing an unserialized value. Two existing tests (`modules.test.ts`) had
asserted the raw-object shape as correct — the fake hub they exercise never performs real wire
serialization, which is exactly how a defect this total stayed uncaught. Both now assert the real
JSON-string shape and both fail against the pre-fix code.

## Where this is likely to go wrong for the next reader

- **This is not a narrow bug.** It broke every structured reply the widget could ever send, not one
  content kind — the calendar booking flow (choice/date-time selection) and any `form`-shaped reply
  were equally affected. Anyone reasoning about "how much of the booking flow has ever really worked
  in production" should start from zero, not from "mostly working with an edge case."
- **The fake SignalR test double's own fidelity gap is the real lesson.** A hub method's real
  contract — argument *types*, not just argument *count* — is only enforced by something that actually
  serializes. `HubMethodArityTests`-style coverage (checked count) did not, and could not, catch this;
  only a live click-through, or a fake that actually round-trips through JSON, would have.

## Done when

- [x] `sendStructuredReply` sends `content` as a JSON string.
- [x] `content`'s type is `string`, not `unknown`, end to end.
- [x] Both existing tests that encoded the wrong shape now assert the real one, and both are shown to
      fail against the pre-fix code.
- [x] Deployed live; a full choice-list reply → `date_time_picker` step confirmed to complete,
      verified directly against the database.
