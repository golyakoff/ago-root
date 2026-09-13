# 25-77 · The owner can also remove a permission from a role

- **Stage**: 25
- **Status**: code landed — `ago-chat#281`/`ago-console#220`. Not yet run against the real deployment
  (same caveat as `25-76`).
- **Depends on**: `25-76` (the owner's add-a-permission tool) — this item is its own explicitly-named
  open question, carried to a number of its own rather than answered by assumption.
- **Found**: 2026-09-13, scoping `25-76`. That item's own text: *"does v1 also need to remove a
  permission from a role, or is 'the owner can always grant what's missing' enough to close the two
  real gaps this item was found from? `AddPermissionsAsync` has no removal counterpart anywhere in
  this codebase today — building one is real, new work, not a wrapper over something that already
  exists the way the grant direction is."* `25-76` deliberately shipped add-only; this is the other
  half, not forgotten.

## What is actually true today

`IRoleRepository.AddPermissionsAsync` (`23-102`) is additive-only, idempotent, and publishes
`RoleAssignmentsChanged` through the outbox to every operator currently holding the role. Nothing in
this codebase removes a permission from an already-created role. `25-76` wraps the add direction in an
owner-only console tool; this item is what it deliberately left out.

## Why this is not simply "the same method in reverse"

A grant only ever widens what an operator can already do — safe to apply mid-session, safe to retry,
safe to get slightly wrong (an extra permission sits unused if nobody needed it). A removal narrows it,
live, for whoever is holding that role right now — including, possibly, an operator with an open
console tab mid-action. The questions a symmetrical `RemovePermissionsAsync` has to answer that the
grant side never had to:

- **What happens to an operator's own open session** when a permission they were just using is pulled
  out from under them? The existing `RoleAssignmentsChanged` propagation (`22-05`/`adr/0093`) tells
  every consumer the role's permissions changed — does the console's own `PermissionsContext` already
  react to that live, or does it only refresh on next login? If it is not live today, a removal that
  silently fails to take effect until the next sign-in is a worse trap than no removal tool at all.
- **Can the last permission that makes a role meaningfully "Admin" be removed**, leaving an Admin role
  indistinguishable from Operator in practice? Not a blocker to building this, but worth a stated
  answer rather than an accidental one.
- **Does removal need the same reason/provenance discipline** `23-86`'s own unconditional-grant flag
  and `adr/0118`'s forced-revoke already establish for every other owner-only override that takes
  something away? The instinct says yes — a removal is exactly the kind of consequential act that
  pattern exists for — but state it rather than assume it by precedent alone.

## Answered, 2026-09-13

Both product questions settled in dialogue with the author, directly, no split needed:

**1. No magic roles.** The owner may remove any permission from any role, `Admin` included, up to and
including the ones that make an `Admin` role recognisably `Admin` (`site:configure`,
`site:manage_operators`). No permission is carved out as unremovable. The author's own framing: the
owner is trusted to know what they are doing, and a role is not a protected shape this tool second-
guesses on their behalf. `IRoleRepository`'s removal counterpart therefore needs no allow/deny list of
its own — every permission `Permission.cs` names is equally removable.

**2. A reason is required, every time.** Matching the precedent this item's own text already named
rather than assumed: `23-86`'s unconditional-grant flag and `adr/0118`'s forced-revoke both require a
non-blank reason for the identical shape of act — taking something away from a tenant that it already
had. Removing a permission is not treated as a lighter-weight act than either.

The third question (`PermissionsContext`'s own live-session behaviour) was resolved by reading the code
rather than by dialogue, before this session even reached the author: no live subscription exists today
— permissions load once, from `GET /api/v1/operators/me`, and only change on the next full page load
(the same tenancy-switch reload path `PermissionsProvider` already uses for an analogous reason).
Removal's own effect on an already-open session is therefore identical to every other permission change
this console already makes, add included — not a new gap this item introduces. Named in the Scope's own
third bullet below as "explicitly named, not fixed here" rather than left as an open question.

## Scope

- `IRoleRepository` gains a removal counterpart to `AddPermissionsAsync` — same idempotence contract
  (removing an already-absent permission is a no-op, not an error), same same-transaction outbox
  publish, no permission excluded from what it may remove.
- A required, non-blank reason on every removal call — the identical shape `adr/0118`'s own
  forced-revoke and `23-86`'s own unconditional-grant flag already require.
- The owner-only write and console UI `25-76` already built for adding gains the mirror action for
  removing, on the identical screen.
- The live-session question is **explicitly not fixed here** — answered above as "identical to every
  other permission change this console already makes," a known, accepted, pre-existing gap this item
  does not newly introduce or need to close.

## Out of scope

- Everything `25-76` already carried: a general role-catalog/role-creation UI, and automatically
  backfilling every existing tenant against some canonical permission set.

## Done when

- [x] `IRoleRepository` has a removal method, additive-idempotent in the reverse direction, publishing
      `RoleAssignmentsChanged` the same way the grant side does, requiring a non-blank reason, refusing
      no permission. — `RemovePermissionsAsync`: an atomic set-difference `UPDATE` (Postgres's own row
      lock serializes concurrent adds/removes on the same role), `coalesce(..., array[]::text[])` so
      removing every permission leaves `[]`, never `NULL`. The reason rides in the same EF transaction
      as the role update and the outbox publish — a real improvement over `ModuleRevokeOverrideRepository`'s
      own precedent, which writes its override row on a second connection after the fact.
- [x] The owner can remove a permission from a role through the same console screen `25-76` built for
      adding one. — a Remove action per currently-held permission, with a required reason prompt.
- [x] What happens to an operator's own live session when a permission they hold is removed is
      answered — **answered, 2026-09-13**: no live subscription exists today, identical to every other
      permission change this console already makes. Independently confirmed by reading
      `PermissionsProvider.tsx` directly while building this change (its one `useEffect` depends only on
      `[accessToken]`, fetched once per sign-in, no polling, no hub listener) — not left as an untested
      note.
