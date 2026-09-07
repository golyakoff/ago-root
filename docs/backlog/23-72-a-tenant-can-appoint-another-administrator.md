# a tenant can appoint another administrator

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing to build. `23-71` is what makes a seatless administrator meaningful.
- **Found**: 2026-09-07, by the author asking how a tenant admin adds another one. They had not missed
  it — there is no way.

## What is actually true, verified

The API can do it. `CreateOperatorInvite` carries a `RoleName`, and `POST /api/v1/operator-invites`
accepts it.

**The console cannot.** `operatorTeamApi.ts` always sends `ORDINARY_ROLE_NAME`, and its own comment
says so plainly: *`RoleName` is never offered as a choice on this screen — no role management.*

So today:

- a tenant cannot appoint a second administrator;
- a tenant cannot change anybody's role at all;
- and the only administrator a tenant will ever have is whoever registered the site.

## Why it matters more than it looks

**It is a single point of failure with a person in it.** The account's one administrator goes on
holiday, leaves the company, or loses access, and the tenant has no route back that does not go
through us. `23-67` and `23-68` are both about that same shape from other angles; this is the one that
prevents it rather than guarding or recovering it.

It is also a precondition for any tier that counts administrators: a limit of two cannot be sold while
appointing the second is impossible.

## Scope

- **An administrator can invite somebody as an administrator**, choosing the role at the moment of
  invitation — the API already takes it.
- **An administrator can change an existing colleague's role**, both directions.
- **The last-administrator guard applies** (`23-67`): the change that would leave nobody able to
  administer is refused, server-side, with a message saying why.
- **Every role change is recorded** — who, whom, from what to what, when. A role is the whole of what
  somebody can do; changing one silently is not acceptable in an account somebody pays for.

## Where this is likely to go wrong

- **Escalation.** Whoever can grant the admin role can grant it to themselves — which is fine, they
  already have it — but it means an ordinary operator must never reach this. The gate is
  `site:manage_operators`, which the Operator role does not hold; check that rather than assume it.
- **An invitation that carries a role is a stronger credential than one that does not.** `23-70` is
  making invitations into links; a link that makes the holder an administrator deserves a shorter life
  than one that makes them an operator, and the two items should agree about that rather than discover
  it separately.
- **Roles are seeded per site** (`RegisterSiteHandler`), so a role name is not a global identifier.
  Anything that names a role must resolve it within the tenant.

## Done when

- [ ] An administrator can invite a colleague as an administrator.
- [ ] An administrator can change a colleague's role, and the change is recorded.
- [ ] The change that would leave nobody able to administer is refused server-side.
- [ ] An operator cannot reach any of it.
