# Release operator capacity when a conversation closes, not only on operator disconnect

- **Stage**: 6 — **scheduled into Stage 15** (2026-08-24), at its original number for the same
  reason `5-13` keeps its own: existing references. It belongs to Stage 15's work because it is a
  capacity leak on a deployment that is now live and taking real conversations — an operator's
  usable capacity decays until their connection drops, which on a public deployment means the
  waiting queue silently stops being served.
- **Status**: done (2026-08-25) — except the load re-run below, see Done when
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

- [x] `CloseConversationHandler` releases operator capacity on a normal close, for conversations that
      hold a real capacity claim. `Conversation.HoldsCapacityClaim` is what "a real capacity claim"
      became — see Decisions below and `adr/0033`.
- [x] A new test deterministically reproduces the bug (fails before the fix, passes after) — assign via
      the automatic path, close, assert `active_chats` decrements.
      `CloseConversationCapacityConcurrencyTests` (`Ago.Chat.Concurrency.Tests`), four tests against
      real Postgres. Against pre-fix code three of them fail, with the load report's own symptom
      reproduced in miniature: 60 conversations, 12 rounds of closes racing assignment ticks, `closed=10,
      assigned=0, waiting=50, active_chats=[5, 5]` — the plateau. With the fix: `closed=54, assigned=6,
      waiting=0, active_chats=[2, 4]`, summing to exactly the live assignment count.
- [ ] `7-04`'s own `assignment-contention` scenario (`Ago.Chat.LoadDriver`,
      `LOADDRIVER_SCENARIO=assignment-contention`) re-run at the same small scale as
      `load/reports/2026-08-24-assignment-contention.md` and confirmed to no longer plateau after the
      first capacity's worth — a new dated report, not just a claim the fix works.
      **Still open, deliberately.** The local compose database is shared with other concurrent sessions
      whose `Ago.Chat.Api`/`Worker` processes are running pre-`6-09` code against it, and they were
      observed assigning conversations with no receipt and closing them with no release *during* this
      item's own verification. A load report measured on that database would not be honest about what it
      measured. The re-run wants a database no other session is writing to.

## Verified live instead, on the shared compose stack

Not a substitute for the load re-run above, but the causal chain end to end, on the real endpoint:

- Migration applied to the local dev database; 55 assigned conversations grandfathered as claim-holding,
  `active_chats` reconciled (it was already equal to the true assigned count there — the operators were
  pinned because they genuinely held 50 and 5 open conversations, not because the counter had drifted).
- One close through `POST /api/v1/conversations/{id}/close` with a real Keycloak operator token:
  `active_chats` 50 → 49. Before this item, that number never moved on a close.
- Three closes in a row: 50 → 47 immediately, and within 8 s the assignment engine had consumed all
  three freed slots (47 → 50) with three named conversations moving `Waiting` → `Assigned` and the
  waiting queue dropping 118 → 115. That is the queue draining past a capacity ceiling that had not
  moved for days.

## The demo deployment

Nothing to run by hand, and nothing was run against it from here. `ago-deploy/k8s/redeploy.sh` step 4
already runs `dotnet ef database update` before restarting the pods, so the next redeploy applies the
repair migration and the demo's waiting queue starts moving again on its own.

One caveat worth knowing rather than acting on: that script deliberately migrates *before* the restart,
so for the length of a redeploy the old code runs against the new column. A conversation closed by the
old code in that window keeps its `holds_capacity_claim` and its slot leaks, exactly as it does today —
inert afterwards (nothing revisits a closed conversation), a handful of slots at most, and cleared the
next time that operator goes offline. Not worth a second repair pass; worth not being surprised by.

## Decisions

**The open question below is resolved: a hand-picked conversation holds no claim, and after this item
it releases none.** `AssignConversationHandler` never calls `TryClaimAsync`, confirmed by reading it —
so the two assignment paths are genuinely asymmetric, and a close cannot tell them apart without being
told. `Conversation.HoldsCapacityClaim` is that receipt. Releasing unconditionally instead would have
decremented, for every hand-picked conversation ever closed, a slot a *different* conversation was
holding — over-subscription, which is worse than the leak this item fixes and which `ReleaseAsync`'s
floor at zero would hide rather than prevent. `adr/0033` records the full fork, including why the
tidier alternative — making manual assignment claim capacity too — was not taken here.

**`OperatorConversationReleaser` was touched after all**, despite the "out of scope" note below: it now
releases per conversation that holds a claim rather than per assigned conversation. The end state is
the same either way (it releases *all* of an operator's assignments and `ReleaseAsync` floors at zero),
so this fixes no observable number — it stops a second path obeying a different rule that only agrees
with the first by accident.

**Follow-up worth its own item**: manual assignment is capacity-blind on both sides. Consistent now,
still wrong as a product behaviour — an operator who picks up five conversations by hand looks idle to
the engine and keeps being handed more. Fixing it means deciding whether an operator at capacity may
refuse-or-be-refused a conversation they explicitly chose, and giving the Application layer a
transaction boundary it does not have.

## Open questions

~~Whether a manually-assigned conversation (`AssignConversationHandler`'s own path) holds a real capacity
claim that also needs releasing on close, or whether that path is capacity-blind by design end to end
(as `7-04`'s report found it is on the *claim* side)~~ — resolved above: capacity-blind end to end, and
kept that way deliberately (`adr/0033`).
