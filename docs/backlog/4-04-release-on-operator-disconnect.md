# Release conversations on operator disconnect, with a grace period

- **Stage**: 4
- **Status**: ready
- **Depends on**: `4-01-waiting-queue-and-capacity-model.md`, `4-02-assignment-engine-skip-locked.md`
  (needs a real assignment engine to observe a released conversation being re-claimed - the release
  half can be built and tested standalone, but the end-to-end story needs `4-02` to exist)

## Goal

`docs/vision.md`: "Either side disconnects -> presence updates -> conversation is released back to
the queue after a [grace period]." An operator who drops every connection (crash, network loss, tab
close) without explicitly going offline stops silently holding capacity forever - after a grace
period with no reconnect, their active conversations return to `Waiting` and their `active_chats`
capacity is released, so `4-02`'s engine can hand them to someone else.

## Context to read first

`docs/vision.md`'s disconnect line, `docs/architecture/realtime.md`'s presence section (`3-01`'s
connection registry - `presence:operator:{op_id}` already exists as a Redis key with a TTL/heartbeat
shape; this item is the first thing to actually *read* operator presence for a business decision,
not just track it), `adr/0009` ("Redis is not truth" - presence going stale or expiring early must
never be treated as certain proof the operator is gone; state explicitly how this item stays honest
about that), `4-01`'s `ReleaseToQueue`/`IOperatorCapacity.ReleaseAsync` (the two things this item's
release path calls), `concurrency.md`'s `BackgroundService`/timer rules.

## Scope

- Detect "this operator has zero live connections" **both ways** (author's decision): a
  query-at-disconnect fast path (`OperatorHub.OnDisconnectedAsync` already deregisters one connection
  from the registry, `3-01`; this item queries the registry for any remaining connections right
  there, and starts the grace-period timer immediately if none remain) plus a periodic sweep backstop
  (catches an operator whose disconnect never fired a clean event at all - a hard process kill on the
  client side - by periodically checking presence for every operator with an active grace-period-
  eligible conversation and starting a timer for any with none). The sweep's own interval bounds how
  late the backstop path can be; state that bound plainly next to its config.
- A grace-period timer per operator, started when their last connection drops, cancelled if any
  connection for that operator reappears before it elapses (a reconnect within the grace window must
  not trigger a release - re-read `3-03`'s reconnect/resume precedent for how "this is the same
  session coming back" is already distinguished from "this is new").
- On grace-period expiry with still no connections: for every conversation currently assigned to that
  operator, `Conversation.ReleaseToQueue(now)`, save, `IOperatorCapacity.ReleaseAsync`, write
  `ConversationReleased` to the outbox in the same transaction as the state change (`adr/0005`) so the
  visitor side can be notified ("your operator disconnected, you're back in the queue" - or whatever
  UX text Stage 5's widget eventually shows; this item's job is the event and the state change, not
  the wording).
- Grace period is config, unmeasured, stated as such (matching `DrainOptions`/`MessageSendRateLimit
  Options`'s precedent).
- Where this runs: a `BackgroundService`, most likely `Ago.Chat.Worker` (matches every other
  timer-driven job in that host) rather than `Ago.Chat.Api` (which does not currently run
  business-logic timers, only connection-lifecycle ones like `ConnectionHeartbeat`) - decide and
  state which, since "an operator's presence is known via Redis, readable from anywhere" means either
  host technically could.

## Out of scope

- Explicit "go offline" (an operator manually setting `OperatorStatus.Away`/`Offline`) releasing
  their conversations immediately, no grace period - not named in any roadmap deliverable; would be a
  natural follow-on if the author wants it, as a separate item.
- Visitor-side disconnect handling beyond what already exists (a visitor's own reconnect/resume,
  `3-03`) - vision.md's "either side" line's operator half is this item; nothing in the roadmap asks
  for new visitor-disconnect business logic beyond reconnect/resume.
- Notifying the *previous* operator that their conversation was released - only the visitor-facing
  half is named in vision.md; add the operator-facing echo only if it turns out to be free once the
  event exists (do not scope-expand to build it deliberately).

## Done when

- [ ] `Ago.Chat.Concurrency.Tests` or `Integration.Tests`: an operator with an assigned conversation
      disconnects (last connection drops), the grace period elapses with no reconnect, the
      conversation is `Waiting` again and `active_chats` decremented - proven against real Redis and
      real Postgres (Testcontainers), not a mocked registry.
- [ ] A reconnect *within* the grace period cancels the pending release - the conversation stays
      `Assigned`, capacity untouched. Proven, not just implemented (a race here - reconnect landing
      exactly as the timer fires - is exactly the kind of case this project's concurrency tests exist
      to catch, per `concurrency.md`'s own stress-test bar).
- [ ] The released conversation is visible to `4-02`'s assignment engine on its next tick and gets
      reassigned - an end-to-end proof, not two separate unit tests that never meet.
- [ ] `docs/architecture/realtime.md` gets a note that presence is now read for a real decision, not
      only tracked, with the honesty caveat from `adr/0009` stated explicitly (a stale/expired
      registry entry biases toward "assume still connected" or "assume gone" - state which this item
      chose and why, since getting it wrong in either direction has a real cost: too eager releases a
      conversation from an operator who is actually fine; too slow leaves it stuck).

## Open questions

None - the author confirmed both query-at-disconnect and a periodic sweep backstop, stated in Scope.
