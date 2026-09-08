# Restoring a locked-out operator's seat

`23-68`, 2026-09-08. This is the procedure for putting a tenant back in when nobody on their own side
can sign in and manage operators any more, and checking that it worked.

**Found by needing it.** A tenant locked itself out during a live demonstration and the only way back
was an `UPDATE` against the live database, typed by hand. `23-67` closes the route that incident took;
this page is what replaces "somebody with database access edits a row" for the account that is already
in that state.

## The ordinary route is the console — this page is the fallback

**`23-68`: `/owner`'s tenant detail screen restores an operator's seat**, in the same "Operators"
section as the entitlements table `23-65`'s own screen already carries. It calls the identical route
this page describes, with the identical rules, and it is where a platform owner should do this in the
ordinary case.

**This page still exists for the day the console is unavailable.** The route below works exactly the
same way from a terminal as it does from the screen. If you can reach `/owner`, use it — reserve this
procedure for when you cannot.

## What you need before you start

- The `siteId` of the tenant and the `operatorId` of the operator who cannot sign in. Get both from
  `/owner` in the console — the tenant detail screen's own "Operators" table names every operator this
  site currently has, and which of them holds no seat.
- Your own platform-owner bearer token. There is nothing else to hold — the route takes no
  deployment-wide secret, the identical `adr/0150` amendment `module-grant-and-revoke.md` already
  describes for the module grant/revoke pair.

## Restoring

```
POST /api/v1/owner/sites/{siteId}/operators/{operatorId}/restore-seat
```

An empty body is a complete, valid call — `force`/`reason` are both optional and both default to "not
forcing", so the ordinary case (the tenant is not already at its own paid seat limit) needs nothing
beyond the URL and your own bearer token:

```
curl -X POST -H "Authorization: Bearer $TOKEN" \
  https://<api-host>/api/v1/owner/sites/<siteId>/operators/<operatorId>/restore-seat
```

Restoring an operator who already holds a seat is a harmless no-op — the response says so
(`alreadyHeldSeat: true`) rather than returning an error, so you do not have to prove the seat is
actually released before calling this.

**Restoring a removed operator is refused, not silently accepted.** If `/owner`'s own roster does not
list the operator at all, they were removed (`Operator.RemovedAt`), and there is no "un-remove" in this
codebase. A `409 Operator.AlreadyRemoved` here means exactly that — this call cannot bring back an
operator who was removed, only one whose seat was released. There is no remedy this route provides for
a removed operator; re-inviting them is a separate action outside this item's own scope.

### The seat-limit decision

**Restoring a seat is capacity-checked against the tenant's own current seat limit, the same check the
tenant's own self-service seat toggle already makes.** The ordinary case — the operator's own seat was
released and nothing else about the tenant's seat count changed — stays within the limit and needs
nothing more than the call above.

**If restoring this seat would push the tenant over its own paid seat limit, the call is refused with a
`409 Operator.SeatRestoreExceedsLimitRequiresForce`** — unless you set `force: true` **and** a
`reason` that is not blank:

```
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  https://<api-host>/api/v1/owner/sites/<siteId>/operators/<operatorId>/restore-seat \
  -d '{"force": true, "reason": "Tenant locked itself out during a live demo; overriding the seat limit to restore access while the downgrade is sorted out."}'
```

That asymmetry is a deliberate decision, not a safety rail to route around: restoring access for a
tenant that cannot reach their own console is exactly the incident this item exists to close, and
refusing it outright because of an unrelated seat-count mismatch would leave that tenant locked out for
a second, independent reason. Overriding is available; it is never silent.

Before you set `force`:

1. Confirm on `/owner` that the refusal really is the seat limit, not something else — the response
   names the limit.
2. Decide whether restoring this operator now, over the tenant's own paid count, is the right call
   (the usual case: a downgrade lowered the limit while operators still held seats, `decisions/0006`'s
   own acceptance of that state — restoring access is more urgent than reconciling the count).
3. **Write the reason you would be willing to show that tenant.** It is stored verbatim in
   `operator_seat_restore_overrides` and it is free text on purpose, the identical `adr/0118` reasoning
   `module-grant-and-revoke.md` already states for its own override: a justification that cannot name
   what happened is not one.

"Cleanup", "test" and "asked to" are not reasons. "Tenant's sole operator released their own seat
during a demo and could not sign back in; restoring immediately, seat-limit reconciliation is a
separate follow-up" is.

## What this does not fix — read this before telling a tenant it is done

**Restoring a seat restores the ability to sign in. It does not restore a role.** `Operator.CanSignIn`
is `HoldsSeat || holdsManageOperatorsPermission` — setting `HoldsSeat` to `true` makes that expression
true regardless of what role, if any, the operator holds. The incident this item was filed from left
the operator's role intact and only released their seat, so restoring the seat was the whole fix.

**An operator who stripped their own last role is a different failure this procedure does not reach.**
They can sign in again once restored here, but hold no permission to do anything once inside — and
nothing in this procedure, or in the console screen that calls it, grants a role back. `/owner`'s own
Operators table shows each operator's current role names for exactly this reason: an empty list next to
the operator you just restored means the seat was never the whole problem. There is no runbook step for
this case yet; it is a named gap, not a silent one.

## Verifying

**Verify against the read, not against the write's own response.** The response tells you the call
succeeded (and whether it was a no-op, or an override); it does not tell you the operator can actually
reach the console.

```
GET /api/v1/owner/sites/{siteId}
```

That is `23-14`'s per-tenant detail read, the same thing the `/owner` console screen shows. Confirm two
things: the operator now shows `holdsSeat: true`, and their role list is what you expect it to be — not
empty, unless the "what this does not fix" case above is exactly what you are dealing with.

**The read that actually proves sign-in works is the operator signing in.** If you can, ask the tenant
to try — a `holdsSeat: true` row is strong evidence, not a substitute for the operator actually getting
back in.

## The standing limit

Nothing in this codebase can grant the realm role that lets this call through. That means this
procedure cannot be delegated by writing code — only by a realm operation (`realm-operations.md`),
performed by a person, deliberately. This is the identical limit `module-grant-and-revoke.md` states
for its own two routes.

Keep it that way. Every restore this route performs is recorded — who, when, which tenant, which
operator — in `access_records`, readable back by the tenant on their own account (`24-12`). A recovery
action that leaves no trace is indistinguishable from an unauthorised one; this is what keeps that from
being true here.

## Related

- `docs/runbooks/module-grant-and-revoke.md` — the identical shape of procedure, for a different write;
  the precedent this page follows for "the console is the ordinary route, this page is the fallback"
  and for the `force`/reason override asymmetry
- `docs/backlog/23-67-*` — closes the route the incident behind this item took; this page recovers from
  an account already in that state, and does not replace that fix
- `docs/backlog/23-71-*` — the sign-in rule (`HoldsSeat || holdsManageOperatorsPermission`) this
  procedure relies on and does not itself change
- `docs/adr/0118-*` — the revoke/override asymmetry this page's own `force`/`reason` reuses
- `docs/architecture/tenant-isolation.md` — why this write needs no `IPermissionChecker` call of its
  own (`RequirePlatformOwner` on the route is the entire access-control story)
- `docs/runbooks/realm-operations.md` — granting the platform-owner realm role in the first place
