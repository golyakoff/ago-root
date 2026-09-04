# an operator can say they are away

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-05` must treat `Away` as not a candidate; that is stated there.
- **Decision**: none — the need is `docs/design/flows.md` 2.5

## Goal

An operator can deliberately stop being the person expected to answer, without closing the tab and
hoping. Today the only presence the system has is a side effect of the hub connection —
`OperatorHub` goes online on connect and offline when the last connection drops — so "I am stepping
away for twenty minutes" has no representation at all. `flows.md` 2.5 records the consequence: the
act has no surface, so it is not performed, and the visitor is told something untrue on the strength
of it.

## Why this is small

The state already exists and nothing writes it. `OperatorStatus` declares `Offline, Online, Away`,
and **`OperatorStatus.Away` occurs in no code path in the repository** — verified. Both readers
already behave correctly for it:

- `SkipLockedAssignmentClaimer` and `RedisLockAssignmentClaimer` both select candidates with
  `Status == OperatorStatus.Online`, so an `Away` operator is already excluded from assignment.
- `OperatorRepository.AnyOnlineForSiteAsync` is `Status == OperatorStatus.Online`, so an `Away`
  operator already does not hold off `SendOfflineAutoReplyHandler` — a visitor arriving while
  everyone is away gets `14-04`'s honest answer rather than silence.

What is missing is a transition on the aggregate, a way to invoke it, and the control.

## Context to read first

- `docs/design/flows.md` 2.5, and 1.2 for the visitor's side of the same act
- `docs/design/ui-inventory.md` §3.1 — the rail's `ConnectionStateBadge`, whose five labels are about
  the *connection*, not about the person, which is exactly the confusion this must not add to
- `Ago.Chat.Domain/Operator.cs` — `GoOnline`/`GoOffline` and their remarks on why a disconnect is
  immediate rather than deferred
- `Ago.Chat.Application/UseCases/SetOperatorPresence/SetOperatorPresenceHandler.cs`, whose own doc
  comment already notes that assignment has always required `Online`
- `docs/backlog/14-04-offline-auto-reply.md` and `adr/0066`
- `docs/architecture/realtime.md` — presence, and what a hub reconnect does

## Scope

- `Operator.GoAway()` beside `GoOnline`/`GoOffline`; coming back is `GoOnline`.
- `SetOperatorPresenceHandler` gains the command, and a route or hub method the console can call.
- **The interaction with the hub is the whole subtlety.** `OperatorHub.OnConnectedAsync` goes online
  unconditionally today, so an away operator whose connection blips would come back online without
  saying so. Deciding and stating the rule is part of this item: the sticky choice is that a
  deliberate `Away` survives a reconnect and is cleared only by the operator, which means
  `OnConnectedAsync` must not overwrite it.
- The operator's own assigned conversations are untouched. Going away is not going offline and is not
  a release; `4-04`'s grace period and `OperatorConversationReleaser` are not involved — and by
  extension `23-03` opens and closes no interval for it.
- A control in the console, distinct from the connection badge, that says what it does to the
  visitor's experience.

## Out of scope

- Per-operator offline auto-reply text. `ui-inventory.md` §2.5 records that auto-reply is configured
  per site; making it per operator is a different item with its own tenant-facing question.
- Scheduled or automatic away (idle timers). An act with no surface is what this fixes; replacing it
  with a guess reintroduces the same problem.
- Showing an operator's away state to the visitor. `flows.md` 1.2's *"must not be led to believe
  somebody is sitting there when nobody is"* is satisfied by the auto-reply already reacting to it.

## Done when

- [ ] An operator marks themselves away and the assignment engine stops selecting them, with no
      change to what they already hold.
- [ ] While every operator is away, a new visitor gets `14-04`'s offline auto-reply.
- [ ] A hub reconnect does not silently return an away operator to `Online` — asserted, because it is
      the behaviour today.
- [ ] Coming back makes them assignable again.
- [ ] An operator cannot set another operator's presence.
- [ ] `realtime.md` states the three-state presence and which of them the hub owns.

## Open questions

None.
