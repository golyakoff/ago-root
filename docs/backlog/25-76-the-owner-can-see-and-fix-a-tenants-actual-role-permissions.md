# 25-76 · The owner can see and fix a tenant's actual role permissions

- **Stage**: 25
- **Status**: deployed — `ago-chat#280`/`ago-console#219`, confirmed live on the demo deployment
  2026-09-16 (both commits are ancestors of the currently-running `ago-chat-api`/`ago-console`
  builds). Add-only, as scoped; removal carried to `25-77`. The tool exists and is reachable; it has
  not yet actually been run against the two live gaps — that needs the platform owner's own login, not
  a deploy step. See Done when.
- **Found**: 2026-09-13, twice in the same evening. First `25-69` — no seeded role anywhere grants
  `conversation:close`, discovered because closing a real duplicate conversation was refused for an
  account's own founder. Second, checking that same class of gap live while verifying `25-08`: querying
  `roles` on the real deployment shows **seven different `Admin` rows, no two identical** — two of the
  seven carry no `channel:manage` at all. Neither gap is rare or one-off; both are the same mechanism.

## What is actually true today

`RegisterSiteHandler`/`MintDemoTenantHandler` each write a site's `Admin`/`Operator` roles **once, at
registration**, with whatever permission list that handler's own source happens to name on that day.
Nothing afterward ever revisits an already-created role row. `IRoleRepository.AddPermissionsAsync`
exists and is exactly the right shape for widening one — additive, idempotent, publishes
`RoleAssignmentsChanged` through the outbox in the same transaction (`23-102`/`23-104`) — but its only
callers today are module-grant handlers adding a permission a *specific module* needs, never a person
choosing to fix a role directly. There is no removal path anywhere in this codebase for an existing
permission on a role.

The result, proven against the live deployment on 2026-09-13:

```
 name   | permissions
--------+------------------------------------------------------------------------------------
 Admin  | {site:configure,site:manage_operators,attachment:delete}
 Admin  | {attachment:delete,calendar:configure,conversation:erase,site:configure,site:erase,
           site:export,site:manage_operators}
 Admin  | {site:configure,site:manage_operators,attachment:delete,site:erase,conversation:erase,
           site:export,conversation:export,conversation:block,calendar:configure,channel:manage}
 ...
```

Seven tenants, seven different permission sets on the identically-named role, each one a fossil of
whichever permission list `RegisterSiteHandler` happened to carry on the day that tenant registered.
Every permission this project adds to that founder list from here to launch creates one more such gap,
silently, for every tenant that already exists — `channel:manage`, `conversation:close`, and whatever
comes next.

## Why this is the owner's own tool, not another one-off SQL fix

Both gaps found today were fixed the same way: read the live `roles` table by hand, write an `UPDATE`
by hand, for one tenant, once. That does not scale past today, and it leaves every other already-drifted
tenant exactly as broken until someone happens to notice *that* tenant's own missing permission the hard
way — a real support ticket, or a real refused action. The owner already has a console (`/owner/sites/
{siteId}`, `OwnerSiteDetailPage`) with an "Operators" section and an "Entitlements" section on the exact
same screen; a tenant's role permissions belong there, not in a runbook that says "SSH in and run this
query."

## Scope

- The owner's site-detail screen gains a way to see each of a site's roles and its actual, current
  permission set — not the founder template, what this specific row really holds today.
- The owner can add a missing permission to a role from that screen, through
  `IRoleRepository.AddPermissionsAsync` (already the right shape — additive, idempotent, outbox-
  published) via a new owner-only endpoint wrapping it. No new repository write needed for this
  direction.
- **Open question, not decided here**: does v1 also need to *remove* a permission from a role, or is
  "the owner can always grant what's missing" enough to close the two real gaps this item was found
  from? `AddPermissionsAsync` has no removal counterpart anywhere in this codebase today — building one
  is real, new work (a role losing a permission has to answer what happens to `RoleAssignmentsChanged`
  and to any operator mid-session holding it), not a wrapper over something that already exists the way
  the grant direction is.

## Out of scope

- A general role-catalog/role-creation UI. Roles are still exactly the two fixed names this codebase
  has always had (`"Operator"`, `"Admin"`) — this item is about what a role already named already holds,
  never about naming a third one.
- Automatically backfilling every existing tenant's role to some canonical "current" permission set.
  That is a one-time migration script, a different shape of fix from a standing tool the owner can reach
  for the next time this drifts (and it will drift again the next time a permission is added) — worth
  naming as a possible companion, not building here.
- `25-69`'s own live fix (adding `conversation:close` to the specific role it was found missing from) —
  that gap gets closed by hand, or by this item's own tool once it ships, not re-litigated here.

## Done when

- [x] The owner can open a site's detail screen and see every role it has, with its actual current
      permission list — not a template, not assumed. — `GET .../owner/sites/{siteId}` extended with
      `Roles`; `OwnerSiteDetailPage`'s own new "Role permissions" section renders it.
- [x] The owner can add a permission a role is missing, and it takes effect for every operator already
      holding that role without them signing out and back in — `AddPermissionsAsync`'s own
      `RoleAssignmentsChanged` publish already gives this; proven end to end against real Postgres
      (`AddRolePermissionsAsOwnerHandlerTests`, `OwnerRolesEndpointsTests`), not assumed from the
      existing method's own contract.
- [x] Whether a removal path ships in this same change or is explicitly carried to its own number is
      decided, not left implicit. — carried to `25-77`, decided before this change was built, not
      after.
- [ ] The two real gaps this item was found from (`25-69`'s `conversation:close`, `channel:manage`
      missing from two live tenants) are each closed through this tool, not through a hand-run `UPDATE`
      — proof that the tool actually works, not only that it exists. **Needs this merged and deployed,
      then actually run by hand against the two real tenants — not provable before that.**
