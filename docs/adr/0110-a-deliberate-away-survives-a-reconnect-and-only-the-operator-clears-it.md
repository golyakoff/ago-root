# ADR-0110: A deliberate Away survives a reconnect, and only the operator clears it

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 23 (`23-20`)

## Context

`OperatorStatus` has declared `Offline`, `Online`, `Away` since early in the project, and `Away`
occurred in no code path anywhere in the codebase - `23-20`'s own "Why this is small" section verified
this directly. Both downstream readers already treated it correctly: `SkipLockedAssignmentClaimer`/
`RedisLockAssignmentClaimer` filter assignment candidates on `Status == Online`, and
`OperatorRepository.AnyOnlineForSiteAsync` (which gates `14-04`'s offline auto-reply) uses the
identical filter. What was missing was a transition onto the state, a way for an operator to invoke
it, and a control - `flows.md` 2.5's own account of the consequence: "the act has no surface, so it is
not performed, and the visitor is told something untrue on the strength of it."

The one real design question the item's own Scope states as already decided, and asks this change to
implement faithfully: **`OperatorHub.OnConnectedAsync` goes online unconditionally today.** If adding
`Away` meant nothing else, an operator who marked themselves away and then had their connection
blip - an ordinary SignalR automatic reconnect, indistinguishable server-side from any other
disconnect-then-reconnect - would be silently carried back to `Online` with no act of theirs behind
it. That is not a rare edge case; a laptop going to sleep, a wifi handoff, or a token renewal that
briefly interrupts the transport all produce exactly this sequence, and every one of them is more
common than an operator's own click to come back.

Investigating the fix surfaced a second call site with the identical problem, not named explicitly by
the item's own Scope but required by its own stated rule ("cleared only by the operator"):
`OperatorHub.OnDisconnectedAsync` calls `Operator.GoOffline()` unconditionally too, whenever an
operator's last live connection anywhere drops. Left unconditional, a disconnect while genuinely away
would silently flip `Away` to `Offline` - and the very next reconnect's guarded `NoteConnected` would
then find `Offline`, not `Away`, and correctly (from its own point of view) carry the operator back to
`Online`. The defect is reachable through either call site alone; fixing only the connect side leaves
it reachable through the disconnect side instead.

## Decision

**A deliberate `Away` is changed only by an explicit operator action, never by a connection existing
or not existing.** Concretely:

1. `Operator.GoAway()` - a new transition, `Status = Away`, beside the existing `GoOnline`/`GoOffline`.
2. `Operator.NoteConnected()` - a new transition, replacing `GoOnline` as `OperatorHub.OnConnectedAsync`'s
   own call. It moves `Offline` to `Online` (preserving the entire pre-`23-20` behaviour for every
   operator who never went away) and leaves `Away` alone. `GoOnline` itself is unchanged and stays the
   one caller allowed to overwrite `Away` - it is now reached only through the operator's own explicit
   `SetAwayAsync(false)` ("I'm back"), never automatically.
3. `Operator.GoOffline()` gains the identical guard: it leaves `Away` alone rather than overwriting it
   with `Offline`. This costs nothing downstream - both states are already excluded from assignment and
   from `14-04`'s coverage check by the same `Status == Online` filter - and it is what makes point 2
   actually hold across a real disconnect-then-reconnect rather than only across a connect that never
   saw a disconnect first.
4. `OperatorHub.SetAwayAsync(bool away)` - the one new hub method the console calls, no `OperatorId`
   parameter (the caller's identity is always `Context.User!.GetOperatorId()`, the same shape
   `GoOnline`/`GoOffline` already use), so there is no "whose presence" question and no way for one
   operator to set another's. `true` calls `GoAwayAsync`/`Operator.GoAway`; `false` calls the
   pre-existing `GoOnlineAsync`/`Operator.GoOnline` - "coming back is `GoOnline`", the item's own
   Scope, reached through a caller it did not have before this item rather than a new domain
   transition.
5. `OperatorHub.GetMyPresenceAsync()` / `GetOperatorPresenceHandler` - a read, added because the
   console's own control needs to render the true current state after every connect and reconnect,
   not a locally-remembered value a reconnect has already made stale. The identical "snapshot, re-call
   after connect, not a push" shape `GetVisitorPresenceAsync` already established.
6. Going away releases nothing. `Operator.GoAway()` does not touch `OperatorConversationReleaser`, and
   `23-03`'s assignment intervals neither open nor close for it - the item's own Scope states this
   explicitly, and no code path introduced by this decision reaches either.

The invariant this maintains, checkable directly on the aggregate: **`Away` changes only inside
`GoAway()` and `GoOnline()`, both called only from an explicit operator action.** `NoteConnected()` and
`GoOffline()` - the two call sites a connection's own lifecycle drives without an operator's
involvement - can only ever move `Offline` to `Online`, or leave `Away` where it is.

## Consequences

- **Two guarded call sites, not one.** The item's own wording names only `OnConnectedAsync`; this ADR
  records the second guard on `GoOffline` as a necessary consequence of the same stated rule, found
  while implementing rather than anticipated by the item's own Scope. A test that reconnects an away
  operator (disconnect, then connect again) and asserts they are still away is the only kind of test
  that can catch a regression in either guard alone - one that merely calls `OnConnectedAsync` in
  isolation would pass even if `GoOffline` regressed to unconditional, because `NoteConnected` would
  still see `Away`, not `Offline`, and correctly leave it. `Ago.Chat.Concurrency.Tests`'
  `AnAwayOperator_SurvivesDisconnectAndReconnect_StaysAway` is that test, against real Postgres and
  Redis through the real hub.
- **`Operator.GoOffline()`'s contract changes slightly**: it no longer guarantees `Status == Offline`
  afterward, only `Status != Online` (unchanged) *and*, additionally, `Away` in particular survives.
  Nothing in this codebase read `GoOffline`'s post-condition as "definitely `Offline`" before this
  item - every consumer of `Status` after a disconnect already only ever asked "is this operator
  `Online`" - so no existing caller's assumption breaks; this is recorded because a future caller might
  otherwise assume the stronger, no-longer-true post-condition.
- **An operator who goes away and then closes their browser entirely stays `Away` indefinitely**, not
  `Offline` - including across days, until they explicitly come back. This is the literal reading of
  "cleared only by the operator" taken to its edge, and it is deliberate: the alternative (treating a
  long-gone away operator as `Offline` again after some timeout) is exactly the "scheduled or automatic
  away" mechanism the item's own Out of scope excludes, applied in reverse. Nothing user-visible
  depends on the distinction - both states are already identically "not a candidate" downstream - so
  the only cost is a status value that, read in isolation months later, still says `Away` for someone
  who left the company. `docs/architecture/authorization.md`/personal-data cleanup paths are unaffected
  (a removed operator is excluded by `RemovedAt`, not by `Status`).
- **A new hub method plus a new read handler, for a control most existing operators will rarely
  press.** Weighed and accepted: the item's own "Why this is small" already established that the state
  and its downstream readers cost nothing new; this decision's own cost is exactly the two guards plus
  the one new command and one new query, not a wider mechanism.
- **`23-05`'s own contract**: an `Away` operator is not `Online` and is therefore not assignable by the
  automatic engine, identically to `Offline` - `23-05` needs no new case for it, only the existing
  `Status == Online` filter it was already going to rely on.

## Alternatives considered

**Make `GoOnline` itself conditional on some “was this deliberate” flag, instead of adding
`NoteConnected`.** Rejected: it would require every caller of `GoOnline` to somehow declare its own
intent, turning one clear method into a parameterized one whose behaviour depends on who is asking - a
worse shape than two differently-named methods that each always do one thing. `NoteConnected` versus
`GoOnline` is also self-documenting at every call site without reading a flag's default.

**Track "was I ever away" as a separate boolean beside `Status`, and have `GoOffline`/`NoteConnected`
consult it instead of checking `Status == Away` directly.** Rejected as strictly more state for the
identical answer: `Status == Away` already *is* "was I ever away and have I not come back since" - a
second flag could only ever agree with it or be a bug.

**Leave `GoOffline` unconditional, and instead make `NoteConnected` distinguish "Offline because
GoOffline just ran" from "Offline because the operator was never away".** Rejected: nothing on the
aggregate or the row can carry that distinction once `Status` has already been overwritten to
`Offline` - by the time `NoteConnected` runs, the fact that the operator went away is already gone. The
guard has to live at the point that would erase the fact, not downstream of it.

**Add a scheduled/idle-timeout auto-away instead of, or alongside, the deliberate control.** Out of
scope by the item's own text ("An act with no surface is what this fixes; replacing it with a guess
reintroduces the same problem") and not reconsidered here - this decision is only about what a
deliberate `Away`, once set, has to survive.
