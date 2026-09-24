# 26-81 · The push payload names no kind of its own — only inferred from which keys are present

- **Stage**: 26
- **Status**: done — closed in the same change as `26-86` ([ago-chat#357](https://github.com/golyakoff/ago-chat/pull/357),
  [ago-android#73](https://github.com/golyakoff/ago-android/pull/73)), which needed a real discriminator
  for its own third push kind anyway.
- **Found**: 2026-09-24, by `26-18`'s own worker while writing `parseIncomingPush` (`ago-android`). Not a
  bug — the client's inference is correct today — but a fragile shape, found while wiring the very code
  that depends on it.

## What is actually true today, confirmed against real code

`Ago.Chat.Application.UseCases.NotifyOperatorDevices.NotifyOperatorDevicesHandler` (`ago-chat`) already
names the distinction server-side — `ReasonAssigned`/`ReasonMessage`, two private constants — but uses
them only for its own metric tags (`ChatMetrics.RecordPushSend(reason, ...)`). Neither ever reaches the
wire: `HandleAssignmentAsync` sends `data = {conversationId}`; `HandleMessageAsync` sends
`data = {conversationId, messageId}`. There is no `reason`/`kind` key in either.

`ago-android`'s `parseIncomingPush` (`26-18`) has no choice but to infer the kind from **whether
`messageId` is present** — a real, working signal today, but an implicit one: a third push kind added
later with no `messageId` of its own would silently misparse as `ConversationAssigned`, and nothing
would fail loudly when it did.

## Scope

- Add an explicit `reason` (or `kind`) string to the `data` dictionary both `HandleAssignmentAsync` and
  `HandleMessageAsync` build in `NotifyOperatorDevicesHandler` — the two constants already exist, this
  is putting them on the wire rather than only in a metric tag.
- Update `ago-android`'s `parseIncomingPush` to read that key directly instead of inferring from
  `messageId`'s presence, and update `IncomingPush.kt`'s own doc comment (which currently states the
  absence as "a finding, not a guess") to match.
- Update `docs/architecture/push-notifications.md` if it documents the wire payload shape.

## Out of scope

- Any change to which two kinds exist, or to `26-18`'s own decision logic (`decideAlert`, dedupe,
  channels) — this item only makes the kind explicit on the wire, it does not change what either side
  does with it.

## Done when

- [x] `data["reason"]` is present on all three push kinds now (not just the original two), server-side,
      added once centrally in `NotifyOperatorDevicesHandler.SendToOperatorAsync`.
- [x] `ago-android`'s `parseIncomingPush` reads that key directly; the `messageId`-presence inference is
      removed.
- [x] `dotnet format`/`build`/`test` (ago-chat) and `./gradlew ktlintCheck lint test` (ago-android) both
      green.
