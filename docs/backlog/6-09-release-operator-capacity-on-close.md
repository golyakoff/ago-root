# Release operator capacity when a conversation closes, not only on operator disconnect

- **Stage**: 6
- **Status**: ready
- **Depends on**: nothing — `ago-chat` only, no product-side prerequisite

## Goal

`CloseConversationHandler` releases the closing conversation's own operator-capacity claim as part of
closing it. After this item, an operator who works through many conversations one at a time — the
ordinary, ubiquitous case, not an edge case — keeps their real available capacity accurate, instead of
`active_chats` only ever going up until that operator's connection drops entirely.

## Context to read first

Found live, not by inspection, while verifying `7-04`'s `assignment-contention` load scenario
(`load/reports/2026-08-24-assignment-contention.md` — read in full for the exact reproduction and root
cause). `docs/architecture/concurrency.md`'s assignment section — `OperatorCapacityStore.TryClaimAsync`'s
atomic compare-and-set (`WHERE active_chats < capacity`) is proven correct and holds under contention;
this item is about the other half of the lifecycle, releasing the claim, not the claim itself.
`ago-chat/src/Ago.Chat.Infrastructure.Postgres/OperatorCapacityStore.cs` — `ReleaseAsync` is the only
thing that ever decrements `active_chats`. `ago-chat/src/Ago.Chat.Worker/OperatorConversationReleaser.cs`
— the *only* existing caller of `ReleaseAsync`, a bulk "operator's last connection anywhere dropped,
redistribute their whole load" sweep (`4-04`'s presence-lost handling) — correct for what it does, but
not a substitute for releasing one conversation's own capacity when that one conversation closes
normally. `ago-chat/src/Ago.Chat.Application/UseCases/CloseConversation/CloseConversationHandler.cs` —
transitions the conversation to `Closed`, enqueues `ConversationClosed`, saves — and never touches
`IOperatorCapacity` at all, the gap this item closes.

## Scope

- `CloseConversationHandler` (or its own `CloseAndSaveAsync` helper, per `6-08`'s own retry-on-conflict
  shape already living there) calls `IOperatorCapacity.ReleaseAsync` for the conversation's assigned
  operator when the close succeeds — symmetric with `TryClaimAsync` at assignment time.
- Only release a real capacity claim: a conversation assigned via the automatic engine
  (`OperatorCapacityStore.TryClaimAsync`, `Ago.Chat.Worker`'s `ConversationAssignmentJob`) holds a real
  claim to release; confirm whether manually-assigned conversations (`AssignConversationHandler`, which
  `7-04`'s own report found never calls `TryClaimAsync` at all) hold a claim to release or not, and
  handle both paths correctly rather than assuming symmetry that may not exist — this is the one real
  design question this item needs to resolve by reading the code, not guessed here.
- A test that reproduces the bug deterministically: assign a conversation via the automatic path
  (exhausting an operator's capacity), close it through the normal handler, and assert
  `active_chats` actually decrements — failing against current code, passing after the fix.

## Out of scope

- `OperatorConversationReleaser`'s own bulk-release-on-disconnect path — already correct, not touched.
- Re-running `7-04`'s `assignment-contention` scenario at full scale to prove the fix under real load —
  a real full-scale run is `7-04`'s own remaining gap (compose/reduced-scale only so far), not this
  item's job; a small-scale manual or automated re-run confirming the queue now drains past its first
  capacity's worth is enough for this item's own Done-when.

## Done when

- [ ] `CloseConversationHandler` releases operator capacity on a normal close, for conversations that
      hold a real capacity claim.
- [ ] A new test deterministically reproduces the bug (fails before the fix, passes after) — assign via
      the automatic path, close, assert `active_chats` decrements.
- [ ] `7-04`'s own `assignment-contention` scenario (`Ago.Chat.LoadDriver`,
      `LOADDRIVER_SCENARIO=assignment-contention`) re-run at the same small scale as
      `load/reports/2026-08-24-assignment-contention.md` and confirmed to no longer plateau after the
      first capacity's worth — a new dated report, not just a claim the fix works.

## Open questions

Whether a manually-assigned conversation (`AssignConversationHandler`'s own path) holds a real capacity
claim that also needs releasing on close, or whether that path is capacity-blind by design end to end
(as `7-04`'s report found it is on the *claim* side) — resolve by reading the code as part of this
item's own Scope, not left open past that.
