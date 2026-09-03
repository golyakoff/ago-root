# every tenant that existed before `22-05` is invisible to the calendar, permanently

- **Stage**: 22
- **Status**: ready
- **Found**: 2026-09-04, immediately after `22-05` was deployed and verified — by the author trying
  to open a calendar screen with their own account and finding nothing there.

## The gap

`role_assignment_projections` is fed by exactly three publishers of `RoleAssignmentsChanged`: site
registration, invite redemption, and operator removal. **None of them will ever fire for a site that
already exists.**

Measured on the live deployment the day it shipped:

```
roles in ago_chat carrying calendar:configure    2
rows in role_assignment_projections              2
sites in ago_chat                               30
```

Two of thirty, and both are sites registered *after* the deploy. Every other tenant — including every
real one — cannot reach a calendar screen and never will, because nothing will ever publish their
current role assignments.

## Why no test could catch it

Every test of this path registers a site first, so the event that populates the projection is always
part of the arrangement. **The state "a tenant that existed before the projection did" is
unrepresentable in a suite that builds its own fixtures.** It is a migration gap, not a logic one.

It is also invisible in the worst way: the console renders calendar screens as **absent, not broken**,
for a person without the permission (`19-03`'s own designed behaviour). So "your tenant predates the
projection" and "you were never granted the calendar" look identical, and neither says anything.

## What this needs, and the choice inside it

A one-off republish of current role assignments for existing sites, **or** a backfill that writes the
projection directly. They differ in a way worth arguing rather than defaulting:

- **Republishing goes through the path production uses**, and therefore proves it end to end — which
  is worth something, since `22-05` shipped without a single real broker round trip anywhere in its
  tests.
- **A direct backfill is faster and bypasses the mechanism** this stage exists to establish.

Whichever it is, it has to be **idempotent and re-runnable**: the natural way to get this wrong is to
run it twice and not know whether that was safe.

## Relationship to `22-07` and `22-17`

`22-07` is where a tenant *buys* the calendar; `22-17` is where the platform owner *grants* it. This
item is neither — it is about tenants whose account-side grants already exist and simply never
reached the calendar. A tenant that `22-07` or `22-17` switches on would work; one that already held
the permission before `22-05` still would not.

## Done when

- [ ] Every pre-existing tenant whose account-side roles carry calendar permissions has them in
      `role_assignment_projections` — verified by count against `ago_chat`, not by running the tool
      and assuming.
- [ ] Running it twice changes nothing the second time, proven by doing it.
- [ ] Whichever shape was chosen, the reason is recorded — this is the last moment where
      "republish through the real path" is cheap.
