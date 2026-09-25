# 26-120 · [chat] Dedup operator push notifications per (operator, conversation) within a short window (fix C for the push storm)

- **Stage**: 26 — fix **C** (safety net) for `26-83`; complements `26-119` (fix A).
- **Status**: ready — direction decided (A+C); this is C.
- **Depends on**: nothing (independent of A; the two compose — A removes the churn source, C guarantees no
  repeat push slips through regardless of cause).

## Why (on top of A)

Fix A (`26-119`) stops the specific 5-min re-assignment churn. C is the belt-and-suspenders: even if some
other path re-triggers an operator push for the same conversation in quick succession (a reconnect, a
redelivery, a future job), the operator should not get the **same** notification again within a short
window. This is the same shape `26-108` used for `OperatorPresenceLost`: an atomic, cross-replica,
short-TTL claim before sending, reusing the existing `IRateLimiter` (RedisRateLimiter) — no new port, no
`IConnectionMultiplexer` in Domain/Application, fail-open if Redis is down (never drop a genuine first push).

## Scope

- At the operator-push send path (the shared chokepoint for `OperatorMessagePushConsumer` /
  `OperatorAssignmentPushConsumer` / `OperatorWaitingPushConsumer` — likely `NotifyOperatorDevices` /
  `NotifyOperatorDevicesHandler`), before dispatching a push, **claim a short-TTL per-(operator,
  conversation, push-kind) marker**; if already claimed within the window, **skip** the send.
- Reuse `IRateLimiter` with a `Capacity:1` rule refilling after the TTL (the `26-108` pattern), keyed by
  operator+conversation(+kind). Fail-open (send) if the marker store is unreachable.
- TTL is its own validated option; a sensible default (e.g. 60–120s) that suppresses a burst of duplicates
  for the same conversation without hiding a genuinely new message a couple of minutes later — pick and
  justify it in a comment, do not invent an unmeasured large number.
- **A genuinely new, distinct message** must still push (the marker is per-conversation-per-window, not a
  blanket mute) — do not suppress a real second message the operator needs to see. If distinguishing
  "same notification repeated" from "new message in the same conversation" is needed, key the marker so a
  new message id / new inbound resets it (decide and document).

## Out of scope

- Fix A's assignment change (`26-119`).
- Any Android change.

## Done when

- [ ] A repeated operator push for the same (operator, conversation, kind) within the TTL is suppressed;
      the first one always sends; a genuinely new message still pushes.
- [ ] Cross-replica safe (shared marker), fails open if the marker store is down.
- [ ] A test proves dedup within the window and send-again after TTL / on a new message.
- [ ] `dotnet format` / build (0 warnings) / full suite green, counts reported.
