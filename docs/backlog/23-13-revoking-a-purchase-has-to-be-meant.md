# revoking a purchase has to be meant, and the override is recorded

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: `docs/design/decisions.md` §6, the *`--force` exists, and it is recorded* amendment
  (2026-09-04)

## Goal

`DELETE /api/v1/owner/sites/{siteId}/modules/{moduleKey}` refuses to revoke a module the **tenant
paid for** unless the caller says explicitly that they mean it — and every such override is recorded
with who, when, which tenant, and **why**, in free text.

`flows.md` 5.3: *"Must never happen: undoing something without seeing it was not yours. Revoke works
on a tenant's own purchase as readily as on a grant … and that asymmetry has to be visible at the
moment of acting."* Today `RevokeModuleForSiteAsOwnerHandler` takes a site, a module key and the
provisioning secret, and treats both cases identically.

## Why an explicit flag and not a screen

§6: the write requires the deployment-wide provisioning secret in the request body (`adr/0095`), so
the console is not where this happens yet, and *a runbook has no moment*. The refusal therefore has
to live in the endpoint. That is the same shape the codebase already uses twice: `ExpiresAt` on the
grant is `required` on a nullable member precisely so that a perpetual grant must be **stated**
rather than defaulted into (`OwnerModuleEndpoints.GrantModuleRequest`'s own remarks), and
`apply-demo.sh`'s `--force-rollback` makes a deliberate act possible while an accidental one is not.

## Why the override exists at all, and therefore why it is recorded

A tenant breaking the law has to be stoppable regardless of what they paid. That makes the override
necessary — and it makes it **the act which later has to be justified, possibly to the person it was
used against.** So: who, when, which tenant, and why.

## Context to read first

- `docs/design/decisions.md` §6 in full, including the *noted, not decided* paragraph
- `docs/design/flows.md` 5.2 and 5.3 — both "must never happen" clauses land here
- `docs/adr/0095-*` (the provisioning secret) and `docs/adr/0098-*` (recording the grant on the thing
  it creates — the shape this extends)
- `Ago.Chat.Api/Owner/OwnerModuleEndpoints.cs`, in particular `GrantModuleRequest`'s own remarks on
  `required` and on why `DELETE` takes an explicit `[FromBody]`
- `Ago.Chat.Domain/EnabledModule.cs` — `GrantedByOwner` and `ExpiresAt`, and why the flag lives on
  that row rather than in a side table
- `docs/architecture/authorization.md` — `RequirePlatformOwner`, which is the entire access-control
  story for these two routes

## Scope

- `RevokeModuleAsOwnerRequest` gains a force flag and a reason. **The reason is required whenever the
  flag is set** and is never optional-with-a-default: a blank reason is the same failure as a
  defaulted expiry.
- `RevokeModuleForSiteAsOwnerHandler` reads the row's `GrantedByOwner`. If it is `false` — the
  tenant's own purchase — the revoke is refused with its own error code unless the flag is set. A
  grant the owner made revokes exactly as it does today, with no new ceremony.
- **The caller's identity has to reach the handler**, and today it does not: neither owner handler
  takes one, because neither calls `IPermissionChecker` (and `EnableModuleForSiteAsOwnerHandler`'s
  own remarks explain why it cannot). The subject comes from `httpContext.User` under
  `RequirePlatformOwner` and is passed in the command — the same way every site-scoped endpoint
  already passes `GetOperatorId()`. Say in the code that this identity is *recorded*, never
  *authorising*: the realm role is still the whole gate.
- **A record**: an append-only row per override — who, when, site, module key, the reason. Its own
  table, not a column on `enabled_modules`, because the row it describes is about to stop existing.
  That is the one case `EnabledModule`'s own "a second table would be a second place the facts could
  drift" argument does not cover, and the item should say so rather than appear to contradict it.
- `authorization.md` and `data-model.md` carry the route's new refusal and the table.
  `personal-data.md` gains the row only if it names a person — the subject of a platform owner is an
  identifier, and the item decides and states which.
- An amendment note on `adr/0098`, or a short new ADR, recording that owner-side revocation is now
  asymmetric by design.

## Out of scope

- A console grant or revoke screen, and the `adr/0095` amendment that would make one possible. §6
  defers both deliberately.
- **Suspending a tenant.** §6's own *noted, not decided*: if the real need is to stop a law-breaking
  tenant entirely, a flag on module-revoke is a workaround — the widget keeps working, the keys stay
  valid, conversations continue. That is a different action and needs its own item.
- Recording ordinary grants. `EnabledModule.GrantedByOwner`/`ExpiresAt` already record those on the
  row they create (`adr/0098`).
- Any change to the tenant's own `DELETE /api/v1/sites/{siteId}/modules/{moduleKey}`. A tenant
  revoking their own purchase is not an asymmetry.

## Done when

- [ ] Revoking a module with `granted_by_owner = false` without the flag is refused, with an error
      that says which kind of entitlement it is.
- [ ] The same call with the flag and a reason succeeds and writes exactly one record.
- [ ] The flag without a reason is refused before the handler runs.
- [ ] Revoking an owner-granted module is unchanged and writes no override record.
- [ ] The recorded subject is the authenticated platform owner, asserted through HTTP rather than
      through the handler alone.
- [ ] A caller without the realm role gets the same refusal as today and nothing is written.
- [ ] `authorization.md` and `data-model.md` carry it; the ADR or amendment exists.

## Open questions

None.
