# 25-170 · A tenant can run past what it is entitled to, with nothing noticing

- **Stage**: 25
- **Status**: code merged — `ago-chat#342`, `ago-console#260`. Live verification (a real subscription
  downgrade / a real channel entitlement lapse on the demo stand) not yet done — see Outcome.
- **Found**: 2026-09-19, discussing a future item (a platform-owner override on the Operator-role and
  Admin-role seat counts, mirroring the existing channel-quantity override). Checked directly whether
  today's entitlement system actually *enforces* anything once granted, or only *reports* it - it only
  reports. This item is the prerequisite the override item depends on; the override item is deliberately
  not this one (see `Depends on`/next steps below).
- **Depends on**: nothing open. Blocks a not-yet-filed future item (owner-set temporary seat/admin
  override, mirroring `ModuleQuantityGrant`'s own `UnconditionallyGrantedByOwner`/`ExpiresAt` shape) -
  that item needs *this* item's active enforcement to exist first, or an override's own expiry would be
  exactly as unenforced as everything else described here.

## A word this item has to use carefully

`Ago.Chat.Domain.Operator` is the account aggregate - **any** person with a console login in a tenant,
regardless of which role(s) they hold. Separately, **"Operator"** is also the name of one specific seeded
role (the other being "Admin") - the one that carries `ConversationRead`/`Send`/`Assign`, the permission
to actually answer a visitor. A founder is one `Operator` account holding *both* roles at once. This item
is precisely about telling those two things apart where today's code does not, so every sentence below
says **"an operator account"**/**"a person"** for the first sense and **"the Operator role"**/
**"Operator-role holder"** for the second - never bare "an Operator" where either reading would work.

## What is actually true today, checked directly rather than assumed

Two independent gaps, same root cause - every "is this tenant entitled to X" fact in this codebase is
computed lazily, for display, and nothing ever re-checks it once granted:

**Channels have zero enforcement at the point that matters.** `ModuleQuantityGrant.EffectiveQuantity(now)`
(`Ago.Chat.Domain/ModuleQuantityGrant.cs:166`) is read by exactly two callers:
`GetSiteForOwnerHandler` (renders the owner's own entitlement table) and `ModuleQuantityGrantStore`'s own
outbox-publishing helpers. **`ReceiveChannelMessageHandler`, `ReceiveChannelAttachmentHandler`, and every
webhook/long-polling entry point that calls them contain zero references to any grant, quantity, or
entitlement check** - confirmed by direct search, not inferred. A channel's inbound message flow keeps
working identically whether its owner-granted override expired five minutes ago or was never granted at
all. `Ago.Chat.Worker` has 70 job/consumer files and not one of them scans for a lapsed
`UnconditionalGrantExpiresAt`.

**Seat/admin capacity is reported, never enforced, and the two roles are handled inconsistently with
each other.** `Operator.HoldsSeat` (`Ago.Chat.Domain/Operator.cs`) gates sign-in for the seeded
"Operator" role (`CanSignIn(bool holdsManageOperatorsPermission) => HoldsSeat || holdsManageOperatorsPermission`
- note the Admin-permission exemption, below). Capacity is checked **only** at the moment of inviting a
*new* person (`OperatorInviteRedemptionRepository.LockSiteAndReadCapacityAsync`) - never re-checked
against anyone already in. When a subscription downgrade shrinks `Site.SeatLimit`, nothing happens to
the operator accounts already active; `GetSeatAssignmentSummaryHandler` computes a fresh `OverSeats` flag
on every read and `OperatorsTeamPage.tsx` shows a banner, but the **tenant** must notice it and manually
pick who to disable (`ToggleOperatorSeatHandler`) - this is `ADR-0073`'s own deliberate decision, cited
and kept below for the Operator role specifically, but currently has no equivalent whatsoever for the
Admin role.

**The Admin role is the one case with *some* active enforcement today, and it does something different
from what this item wants.** `AdministratorLimitEnforcer.DemoteExcessAdministratorsAsync`
(`Ago.Chat.Infrastructure.Postgres/AdministratorLimitEnforcer.cs`) runs inside the same transaction as a
subscription renewal/downgrade (`SubscriptionRenewalApplier.cs`), picks whichever Admin-role holder was
granted that role most recently (via `RoleChangeRecords.ChangedAt`), and **demotes** them to the Operator
role - they keep working, just without Admin permissions. Two problems found while checking this: (1)
`RoleChangeRecords` is written **only** by `ChangeOperatorRoleHandler` (a role *change*) - an operator
account invited directly into the Admin role, never promoted into it from something else, has no row in
it at all, so the "most recent" comparison is blind to most real Admin-role holders; (2)
`Operator.CanSignIn`'s own Admin-permission exemption means an Admin-role holder's own `HoldsSeat` is
irrelevant to their own ability to sign in - so even if this item wanted to reuse `HoldsSeat` to "disable"
someone over the Admin-role limit the same way someone over the Operator-role limit is disabled, it would
silently do nothing.

## The design, worked through with the author before writing code

**The core decision: stop treating "holds a seat" as a fact about an `Operator` account, and start
treating it as a fact about one `(operator account, role)` pairing.** This is not primarily a database
refactor for its own sake - it is what makes the Operator role's own capacity and the Admin role's own
capacity genuinely the same mechanism, instead of one built first and the other bolted on beside it
(which is what a `HoldsSeat`-plus-a-new-`HoldsAdminSeat` pair of fields directly on the `Operator`
account would have produced). A founder holds both roles from registration (confirmed:
`RegisterSiteHandler`/`SiteRegistrationRepository` seed two `operator_roles` rows for one operator
account) and should be able to lose one role's seat independently of the other's - that only falls out
naturally if the seat itself lives on the role assignment, not on the account.

- **`operator_roles` gains `HoldsSeat: bool` and `GrantedAt: DateTimeOffset`**, one pair of columns
  covering both roles today and any future one without a third bolt-on field. `HoldsSeat` replaces
  `Operator.HoldsSeat` outright (migrated: the existing value becomes the Operator-role row's own
  `HoldsSeat`; every currently-provisioned Admin-role row backfills `HoldsSeat = true`, since nothing
  today has ever disabled one). `GrantedAt` is written at both places a role is ever assigned to an
  operator account - `ChangeOperatorRoleHandler` (already writes `RoleChangeRecords`, now also stamps
  this) **and** `OperatorInviteRedemptionRepository`'s invite-acceptance path (today writes nothing at
  all towards this question - the actual gap that made the existing Admin-only enforcer blind to invited
  Admin-role holders).
- **`Operator.CanSignIn` becomes one rule, not a role-shaped exemption**: an account can sign in if *any*
  role it currently holds has `operator_roles.HoldsSeat = true` for that pairing. The Admin-permission
  exemption goes away entirely - an account disabled on its Admin-role seat is disabled, full stop, the
  same as one disabled on its Operator-role seat.
- **One capacity-check procedure, parameterized by role name and the `Site` field that limits it**
  (`"Operator" → SeatLimit`, `"Admin" → AdminLimit`), replacing both `LockSiteAndReadCapacityAsync`'s own
  Operator-role counting and `ChangeOperatorRoleHandler`'s separately hand-written Admin-role counting.
  Both existing call sites move to it; no new capacity rule is invented, the two existing ones are
  unified.
- **One reconciliation procedure, parameterized the same way, replaces `AdministratorLimitEnforcer`
  entirely.** For a given site and role: count current `HoldsSeat = true` holders of that role, and if
  over that role's own `Site` limit, flip `HoldsSeat = false` on the excess ordered by `GrantedAt`
  descending (most recently granted loses first) until back at or under the limit. Applied to the
  Operator role and the Admin role identically. `AdministratorLimitEnforcer`'s own demote-to-Operator-role
  behaviour is retired, not kept alongside the new one - the author's own decision (this item's design
  conversation) is that someone over the Admin-role limit is *disabled*, the same outcome someone over
  the Operator-role limit already gets, not moved sideways into a role that might itself now also be
  full.
- **A new recurring job in `Ago.Chat.Worker`, every one minute** (precedent: `DownloadThresholdWatchdogJob`/
  `InactivityWatchdogJob`, the existing shape for "check something on a cadence, act if a threshold is
  crossed"), doing two independent things per site:
  1. **Role-capacity reconciliation** (above) - catches a subscription downgrade the moment the next tick
     runs, not only the instant `SubscriptionRenewalApplier`'s own transaction commits. The author's own
     call: instant is not required, materially delayed is not acceptable - a fixed one-minute cadence is
     the answer, not an event-driven push for this particular fact.
  2. **Channel entitlement reconciliation** - reads `ModuleQuantityGrant.EffectiveQuantity(now)` for every
     channel-shaped module a site has ever connected (no new storage: this value already exists and is
     already computed correctly, it is simply never read by anything that acts on it today). Where it has
     dropped to zero: pause that site's own long-polling loop where one exists (`TelegramLongPollingService`/
     `MaxLongPollingService` - stopping the ambient provider-API polling, not only refusing what arrives,
     since a channel a tenant is no longer entitled to should not keep spending that provider's own rate
     budget either), and the same `EffectiveQuantity(now) > 0` check is added directly inside
     `ReceiveChannelMessageHandler`/`ReceiveChannelAttachmentHandler` as a second, redundant guard - closing
     the race between "the tick already ran" and "a message arrives in the same minute it shouldn't have."
- **Nothing is deleted, ever, for either gap.** Bytes, rows, credentials, conversation history - all
  survive. "Disabled"/"paused" are read-time, reversible facts, the identical posture `Site.SuspendedUntil`/
  `Site.DownloadBlockExempt` already take for the same reason: an entitlement lapsing is not evidence of
  wrongdoing, and treating it as such (by deleting anything) would be a wildly disproportionate response
  to a subscription simply not being renewed yet.
- **A tenant can always swap.** Re-enabling anyone's seat on either role (`ToggleOperatorSeatHandler`,
  extended to cover the Admin role's own `operator_roles.HoldsSeat` the same way) still goes through the
  same capacity check the unified procedure above already enforces - turning one back on while already at
  the limit fails exactly the way inviting a new person at the limit already fails today, so a tenant
  choosing to swap who is active must disable someone else first, in either order the console UI allows.

## Scope

1. Migration: `operator_roles` gains `HoldsSeat`/`GrantedAt`; backfill both from `Operator.HoldsSeat`
   (the Operator-role rows) and `true`/best-known-timestamp (the Admin-role rows, per above);
   `Operator.HoldsSeat` itself is removed once every reader has moved.
2. `Operator.CanSignIn` rewritten to the one-rule form; remove the Admin-permission exemption.
3. One capacity-check procedure (Application layer), replacing both existing hand-written checks; both
   `OperatorInviteRedemptionRepository` and `ChangeOperatorRoleHandler` call it.
4. One reconciliation procedure (Application layer, `IClock`-driven, no `DateTime.UtcNow`), callable both
   from the new watchdog and (optionally, if convenient) from the existing `SubscriptionRenewalApplier`
   transaction for the instant case - author's call at implementation time whether the one-minute job
   alone is sufficient or the transactional call stays as a same-effect fast path.
5. Retire `AdministratorLimitEnforcer` and its call sites.
6. New `Ago.Chat.Worker` job, one-minute cadence: role-capacity reconciliation for every site; channel
   entitlement reconciliation (pause long-polling, nothing to do for webhook-only channels beyond the
   handler guard below).
7. `EffectiveQuantity(now) > 0` guard added inside `ReceiveChannelMessageHandler`/
   `ReceiveChannelAttachmentHandler`.
8. Console: `OperatorsTeamPage.tsx`'s existing Operator-role seat toggle/badge/"over your seat limit"
   banner generalised to render per-role (the Operator role and the Admin role identically) rather than
   hardcoded to the Operator role only - an owner/admin gets the same visibility and the same manual swap
   control for the Admin role that the Operator role already has.

## Out of scope

- The owner-set temporary seat/admin override itself (a separate, not-yet-filed item, deliberately kept
  apart - this item is its prerequisite, not itself).
- Any change to *which* channels/modules exist or how a tenant purchases more of them.
- A notification (email) when an auto-disable happens - worth a future item if wanted; not decided here.
- Webhook-only channels' own "ambient cost" (VK/WhatsApp/Avito have no long-polling loop to pause) - the
  handler-level guard already stops them from doing anything once disabled; there is no separate resource
  being spent to also stop.

## Done when

- [x] `operator_roles.HoldsSeat`/`GrantedAt` exist, migrated correctly from today's data, and
      `Operator.HoldsSeat` is gone — `Stage25AddOperatorRoleSeatColumns`, add-then-backfill-then-drop,
      read in full and judged correct
- [x] `CanSignIn` is the one-rule form; an account disabled on its Admin-role seat cannot sign in, proven
      by a test — `OperatorSignInEligibilityTests`/`OperatorTests`
- [x] Inviting past `SeatLimit` or `AdminLimit` is refused by the one shared capacity procedure, proven by
      tests for both roles — `OperatorRoleSeatCapacity`, both invite/role-change call sites moved to it
- [x] A subscription downgrade that drops either limit below current headcount results in the excess
      being disabled (not demoted, not deleted) within one minute, most-recently-granted-first, proven by
      a test seeding `GrantedAt` out of order for both roles — `OperatorRoleSeatReconcilerTests`,
      `EntitlementWatchdogJobTests`
- [x] `AdministratorLimitEnforcer` and its call sites are gone; nothing references it — interface,
      implementation and its own test file all deleted, confirmed via `git status`
- [x] A channel whose `ModuleQuantityGrant` has expired stops being processed - proven by a test that
      lets a grant expire and confirms `ReceiveChannelMessageHandler` refuses what arrives after, and
      (for a long-polling channel) that the poll loop itself pauses within one minute —
      `EntitlementWatchdogJobTests`, `ChannelPollerReapTests`
- [x] Re-enabling a seat on either role still enforces that role's own capacity limit, proven by a test —
      `ToggleOperatorSeatHandlerTests`
- [x] The console shows the same over-limit banner and manual toggle for the Admin role that the Operator
      role already has, proven by a test — `OperatorsTeamPage.test.tsx`, and (found only by CI, see
      Outcome) `ux-gate`'s own `operators-team` screen render

## Outcome

Merged 2026-09-19/20: `ago-chat#342` — seat-holding moved from `Operator.HoldsSeat` to
`operator_roles.HoldsSeat`/`GrantedAt`; one `OperatorRoleSeatCapacity`/`OperatorRoleSeatReconciler` pair
governs both roles; `AdministratorLimitEnforcer` retired outright; new `EntitlementWatchdogJob`
(one-minute cadence) reconciles both role capacity and channel entitlement; `ReceiveChannelMessageHandler`/
`ReceiveChannelAttachmentHandler` gained a live entitlement guard. Full suite independently re-verified:
Domain 754, Application 1448, FakeCrm 21, Architecture 52, Concurrency 90, Integration 1433, all 0 failed
(one Docker-container-networking flake seen once under load, clean on a re-run in isolation).

**A real bug found and fixed along the way**: `OperatorRepository.AnyOnlineForSiteAsync` had narrowed "is
any staff member on duty" to Operator-role holders only, incorrectly excluding an online Admin-role-only
operator from triggering offline auto-replies - fixed to check any held seat, matching `CanSignIn`'s own
rule, and covered by a new test.

`ago-console#260` — `OperatorsTeamPage.tsx`'s seat badge/toggle/over-limit banner generalised to both
roles; `OwnerSiteDetailPage.tsx` updated for the changed wire shape. 141 files / 1531 tests, independently
re-verified.

**A real gap in verification, caught only by CI, not by the managing session or the worker**:
`npm run typecheck`/`lint`/`test -- --run` were all green, but `ago-console`'s actual CI also runs
`npm run ux-gate` (a real-browser Playwright pass) - neither the worker nor the managing session ran it
before opening the PR. It failed: `ux-gate/fixtures/data.ts` still mocked the pre-`25-170` flat
`holdsSeat`/`roleNames`/`heldSeats`/`seatLimit`/`overSeats` shapes, which `OperatorsTeamPage` no longer
parses, so the `operators-team` screen never rendered. Fixed (the fixture updated to the new
`roles: OperatorRoleSeatDto[]` shape, preserving the same over-limit scenario it always tested) and
re-verified green, `ux-gate` included, before merging. Recorded as a standing lesson: this repo's real
verification set is four commands, not three.

**A pre-deploy backup was taken** (`take-a-backup`) before this lands on the demo stand, specifically
because the migration is destructive - `Stage25AddOperatorRoleSeatColumns` drops `operators.holds_seat`
in the same migration that backfills its replacement, with no separate expand-then-contract release, so
a code rollback after this migration cannot fall back to the previous schema (`docs/runbooks/redeploy.md`'s
own stated rule). Confirmed fresh (`ago-backup-20260919T211017Z.tar.gpg`, pulled and sha256-verified).

Two Done-when-adjacent facts remain to prove live rather than by test, not blocking the merge: a real
subscription downgrade actually disabling the right people within a minute on the demo stand, and a real
channel's long-polling loop actually pausing when its entitlement lapses there.
