# 25-77 · The owner can also remove a permission from a role

- **Stage**: 25
- **Status**: ready
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

## Scope

- `IRoleRepository` gains a removal counterpart to `AddPermissionsAsync` — same idempotence contract
  (removing an already-absent permission is a no-op, not an error), same same-transaction outbox
  publish.
- The owner-only write and console UI `25-76` already built for adding gains the mirror action for
  removing, on the identical screen.
- The live-session question above is answered and, if the answer is "no, it is not live today",
  either fixed in this change or explicitly named as a known, accepted gap with a reason.

## Out of scope

- Everything `25-76` already carried: a general role-catalog/role-creation UI, and automatically
  backfilling every existing tenant against some canonical permission set.

## Done when

- [ ] `IRoleRepository` has a removal method, additive-idempotent in the reverse direction, publishing
      `RoleAssignmentsChanged` the same way the grant side does.
- [ ] The owner can remove a permission from a role through the same console screen `25-76` built for
      adding one.
- [ ] What happens to an operator's own live session when a permission they hold is removed is
      answered and proven, not assumed.
