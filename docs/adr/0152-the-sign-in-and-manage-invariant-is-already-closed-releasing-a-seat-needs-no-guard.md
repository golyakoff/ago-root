# ADR-0152: The sign-in-and-manage invariant is already closed by `23-26` and `23-71` — releasing a seat needs no guard of its own

- **Status**: Accepted — the author accepted it 2026-09-08.
- **Date**: 2026-09-07
- **Stage**: 23 (`23-67`)
- **Specifies**: `backlog/23-67-no-action-may-leave-a-tenant-with-nobody-who-can-sign-in.md`

## Context

`23-67` was found live: the account's sole operator pressed «вернуть место» against their own row and
was permanently locked out — a seat was the only door, and they held none afterward. The item restates
the guard the incident calls for as a property of the result, not of any one action: **no action may
leave a tenant with nobody able to sign in and manage operators**, and names three routes to that
result explicitly — releasing a seat, removing an operator, and stripping a role.

The item is written to be built "in terms of `23-71`, rather than ahead of it" — `23-71` (`01b0ff1`)
separates *may sign in* from *may be routed a conversation*: `Operator.CanSignIn` became
`HoldsSeat || holdsManageOperatorsPermission`, and `holdsManageOperatorsPermission` is resolved by
`PermissionChecker.HasPermissionAsync` purely from a role assignment (`OperatorRoles` / `Roles.Permissions`)
that no seat-toggle ever touches. This ADR is the record of following that instruction through to what
it actually implies for each of the item's three routes, checked against the code rather than assumed
from the item's own prose.

## Decision

**No new runtime guard is added.** The three routes resolve as follows:

1. **Removing the last operator who can sign in and manage operators.** Already fully closed, before
   `23-67` was even filed: `23-26` (`be4e65f`, 2026-09-05) added exactly this invariant to
   `RemoveOperatorHandler` — a transactional, `FOR UPDATE`-locked count of non-removed
   `site:manage_operators` holders (`IPermissionChecker.CountNonRemovedHoldersAsync`), refusing when a
   removal would take the count to zero, self-removal included. Since `23-71`, "holds
   `site:manage_operators` and is not removed" and "can sign in and manage operators" are the same set
   — holding that permission alone satisfies `CanSignIn` regardless of seat — so `23-26`'s guard already
   *is* `23-67`'s invariant for this route. `RemoveOperatorConcurrencyTests` already proves the race
   closed on real Postgres. What `23-67` adds here is one test
   (`OperatorSignInEligibilityTests.CanSignInAsync_TheSurvivingManagerAfterARefusedSelfRemoval_CanStillSignIn`)
   closing a gap nothing before it asserted: that the operator `23-26`'s count leaves behind can actually
   sign in, not merely that the count is nonzero.

2. **Releasing the last seat that can manage operators.** Checked directly against
   `ToggleOperatorSeatHandler`, which writes `Operator.HoldsSeat` alone and reads no manager count: for
   the one operator this invariant is about — a non-removed `site:manage_operators` holder —
   `CanSignIn` is `true` before the toggle and stays `true` after it, for every input this handler
   accepts, because the permission half of `HoldsSeat || holdsManageOperatorsPermission` is untouched
   either way. A count-based guard copied from `RemoveOperatorHandler` would read a fact this handler
   cannot move and could therefore never refuse — dead code proven dead, not assumed so: reverting
   `Operator.CanSignIn` to `HoldsSeat` alone (undoing `23-71`) and rebuilding makes
   `OperatorSignInEligibilityTests.CanSignInAsync_TheSoleManager_SurvivesReleasingTheirOwnLastSeat` fail
   immediately, which is the demonstration that `23-71` — not a guard this item would add — is what
   closes this route. `ToggleOperatorSeatHandler` carries a doc comment recording this so a future
   reader does not wonder why `RemoveOperatorHandler` has a last-manager check and this handler does not.

3. **Removing the last role that grants it.** There is no such action in this product yet. Role
   assignment (`OperatorRoles`) is written exactly twice — site registration and invite redemption
   (`RegisterSiteHandler`, `OperatorInviteRedemptionRepository`) — and never afterward; `Roles.Permissions`
   is seeded once per site and has no editor. `23-67`'s own Done-when names this route for the reason its
   own text gives ("whatever is added later"), not because it is reachable today. Nothing is built for
   it now. Whoever builds operator-role editing must apply this ADR's invariant to it then — the same
   `CountNonRemovedHoldersAsync`-shaped check `23-26` already uses, asked of the role change's own
   effect on the count.

## Consequences

**The two rules the author proposed are consistent, and the item's own reading of that is correct** —
"cannot remove the last one" and "cannot remove yourself" overlap only at the last one, and there both
say refuse. What the item's own text also already states, and this ADR confirms against the code: `23-71`
is not merely a related fix landed nearby, it is the fact that makes route 2 already-safe. Building a
guard for route 2 anyway — the literal reading of the item's own Done-when bullet 1 — would mean adding
a check that cannot fire under the current permission model, at the cost of a query and a transaction on
every seat toggle, and reviewer time spent on a branch that cannot be exercised. This ADR chooses
proving it unreachable, once, over shipping it.

**The self-action exception the item asks for exists automatically**, not as a rule anyone had to write:
`23-26`'s guard was never "you may not remove yourself", so a tenant with two managers doing any of the
guarded actions to themselves already succeeds, and `ToggleOperatorSeatHandler` never gated on
self-action to begin with.

**What is not yet true**: if the permission model ever changes so that `site:manage_operators` can be
lost by some means other than removal or a (currently nonexistent) role edit — losing a seat becoming
load-bearing for a permission again, for instance — this decision's premise breaks, silently, at exactly
the call site this ADR argues needs no check. `OperatorSignInEligibilityTests` exists to catch that: it
asserts the current mechanism, not a promise about the future, and a change to `Operator.CanSignIn` or to
what `HasPermissionAsync` resolves from is exactly what should make it fail.

## Alternatives considered

**Add the count-based guard to `ToggleOperatorSeatHandler` anyway, as defense in depth.** Rejected: it is
not defense of anything reachable. The count `CountNonRemovedHoldersAsync` returns is unaffected by
`Operator.HoldsSeat`, so the guard would read the same value before and after every call this handler
can ever receive — a check with one branch no test can drive true, which is a worse position than no
check plus a test proving why. If the premise above ever breaks, a guard copied in today would still
read the wrong signal (a seat, not the permission) and provide no actual protection against the new
failure mode; the correct response to that break is to re-derive the check against whatever changed, not
to have shipped one in advance against a model that did not yet exist.

**Treat `23-67` as fully closed by `23-26` and `23-71` alone, add no new code at all.** Rejected: it
would leave the "count of holders" -> "that holder can sign in" gap unasserted (nothing before this item
checked it end to end) and would leave `ToggleOperatorSeatHandler`'s absence of a guard looking like an
oversight to the next reader rather than a checked conclusion. The two new tests and the doc comment are
the cost of making "already closed" a checked claim instead of a plausible one.
