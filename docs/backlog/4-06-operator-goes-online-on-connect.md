# Operator presence actually flips to Online on connect

- **Stage**: 4
- **Status**: fixed, not deployed (2026-08-27). Code written and fully tested (846/846, fails-before
  demonstrated), `ago-chat#94` open; the live cluster still runs the broken code until it merges and
  is deployed.
- **Depends on**: `4-02-assignment-engine-skip-locked.md`, `4-03-assignment-engine-redis-lock-alternative.md`,
  `4-04-release-on-operator-disconnect.md` (this item closes a gap in all three: they have always
  filtered/reacted on `OperatorStatus`, and this is the first thing that ever wrote it to `Online`)

## Goal

Found live, on the deployed cluster, on 2026-08-27: the author minted a demo tenant
(`8-07`/`MintDemoTenantHandler`), signed into the operator console with the minted credentials, sent a
visitor message from the matching demo-shop page, and watched the conversation sit in the console's
"Waiting" column forever - never assigned, never appearing under "Assigned to me", even with the
operator hub showing "Live".

Root cause: `SkipLockedAssignmentClaimer`/`RedisLockAssignmentClaimer` (`4-02`/`4-03`) have always
required `OperatorStatus.Online` from every assignment candidate. Every operator created at runtime -
`MintDemoTenantHandler` for a minted demo tenant, `RegisterSiteHandler` for a real registration - is
constructed `Offline`, and until this item nothing anywhere ever moved that status to `Online`.
`RegisterSiteHandler`'s own comment named the intended mechanism and never built it: "Offline, not
Online - this operator has not connected yet (presence, Stage 3, is what actually flips this once
their console session opens)". `OperatorHub.OnConnectedAsync` has always registered the SignalR
connection in the realtime registry (which is why the console correctly shows "Live") but never wrote
anything to the `operators.status` column. `OperatorStatus` itself had no setter at all.

The pre-seeded demo tenant (`demo-operator`/`demo-shop1`) never showed this bug because
`ago-deploy/seed/create-demo-tenant.sh` writes `status = 'Online'` directly in raw SQL, bypassing the
application layer entirely - and nothing ever wrote it back to `Offline` either, so it has looked
correct by accident since `1-05`. Every runtime-created operator - which is every real tenant this
product has ever had, demo or not - has been permanently unassignable since Stage 4 shipped.

## Context to read first

`docs/architecture/concurrency.md` (Stage 4's own assignment/capacity rules), `4-02`'s and `4-04`'s
own backlog files (the claimer's candidate query, the disconnect-release grace period this item
deliberately does not touch), `RegisterSiteHandler`'s own comment (now updated to point here),
`Operator.cs`'s class remarks.

## Scope

- `Operator.GoOnline()`/`Operator.GoOffline()`: the domain now owns its own presence transition,
  `Status` changed from a get-only property to `{ get; private set; }`. Idempotent - a second
  connection (another tab) while already `Online` is a no-op, not an error.
- `IOperatorRepository.GetByIdAsync`/`SaveAsync`, implemented in `OperatorRepository` - the by-id
  lookup and persistence this needed, following the same "grow the port only when a second real
  caller needs a different question answered" rule its own doc comment states.
- `SetOperatorPresenceHandler` (`Application/UseCases/SetOperatorPresence`): `GoOnlineAsync`/
  `GoOfflineAsync`. No permission check, unlike every other handler here - the operator id is the
  caller's own identity from the connection's JWT, not a resource named by the caller that needs
  checking against someone else's claim.
- `OperatorHub.OnConnectedAsync` calls `GoOnlineAsync` on every connection (idempotent, so a second
  tab is harmless). `OperatorHub.OnDisconnectedAsync` calls `GoOfflineAsync` only when
  `HubConnectionRegistration.OnDisconnectedAsync` reports this was the operator's *last* connection -
  immediately, not deferred to `4-04`'s grace-period consumer, which is a different and costlier
  decision (releasing an already-*assigned* conversation) that this item does not touch at all.

## Out of scope

- `4-04`'s grace period and release-on-disconnect logic - unmodified. This item only changes when
  `operators.status` itself flips; `OperatorPresenceLost`/`OperatorDisconnectGraceConsumer` still make
  their own independent decision about releasing already-assigned conversations, on their own timeline.
- An explicit "go offline" UI control (an operator manually stepping Away/Offline without
  disconnecting) - `4-04`'s own Out-of-scope section named this as a possible follow-on; still is.
- Publishing `OperatorStatusChanged` as an integration event (`messaging.md`'s contract table already
  lists it, aspirationally) - nothing in this codebase consumes it yet (assignment reads the status
  column directly, not a cache), so adding the event now would be unused infrastructure. Add it only
  when a real second consumer needs it.

## Done when

- [x] `Ago.Chat.Domain.Tests.OperatorTests`: `GoOnline`/`GoOffline` set `Status` correctly;
      `GoOnline` on an already-`Online` operator is a no-op.
- [x] `Ago.Chat.Application.Tests.UseCases.SetOperatorPresence.SetOperatorPresenceHandlerTests`:
      both directions persist through the repository port; a missing operator row throws rather than
      failing silently.
- [x] `Ago.Chat.Concurrency.Tests.OperatorConnectAssignabilityTests` - the real regression proof,
      against real Postgres and real Redis, reproducing the exact live symptom: an operator seeded
      `Offline` (matching `MintDemoTenantHandler`/`RegisterSiteHandler`, not the demo seed script's
      hand-set `Online`), a real `Waiting` conversation, `SkipLockedAssignmentClaimer` finds nothing
      before connect and claims it immediately after `OperatorHub.OnConnectedAsync` - then the
      operator's last disconnect flips it back to `Offline`.
- [x] `RegisterSiteHandler`'s comment updated to point at this item instead of describing a mechanism
      that did not exist.
- [ ] Fix deployed live and independently verified in the browser: mint a fresh demo tenant, sign
      in, send a visitor message from the matching demo-shop page, watch it move from "Waiting" to
      "Assigned to me" in the operator console without a manual claim.

## Fails-before

| Test | Mutation | Result before fix | Result after fix |
|---|---|---|---|
| `OperatorConnectAssignabilityTests.AnOperatorBornOffline_BecomesAssignable_OnConnect_AndUnassignable_OnLastDisconnect` | Removed the `GoOnlineAsync` call from `OperatorHub.OnConnectedAsync` | `claimedAfterConnect` asserted `1`, actual `0` - fails exactly where the live bug did | Passes |

## Open questions

None - the author confirmed the immediate-on-last-disconnect timing (not deferred to `4-04`'s grace
period) and the "no `OperatorStatusChanged` event yet" scope call live, while reviewing this item.
