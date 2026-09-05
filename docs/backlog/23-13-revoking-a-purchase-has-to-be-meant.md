# revoking a purchase has to be meant, and the override is recorded

- **Stage**: 23
- **Status**: done (2026-09-06). A force flag with a required reason, an asymmetric refusal, and `module_revoke_overrides` for every override exercised.
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

- [x] Revoking a module with `granted_by_owner = false` without the flag is refused, with an error
      that says which kind of entitlement it is.
- [x] The same call with the flag and a reason succeeds and writes exactly one record.
- [x] The flag without a reason is refused before the handler runs.
- [x] Revoking an owner-granted module is unchanged and writes no override record.
- [x] The recorded subject is the authenticated platform owner, asserted through HTTP rather than
      through the handler alone.
- [x] A caller without the realm role gets the same refusal as today and nothing is written.
- [x] `authorization.md` and `data-model.md` carry it; the ADR or amendment exists.

## Open questions

None.

## Outcome

**The asymmetry is the whole item, and it is the thing an implementation would most easily flatten.**
Revoking what the platform owner granted must not get harder; revoking what a tenant **paid for** must.
An implementation that added ceremony to both would have passed a careless review and missed the point
entirely — which is why the regression test on the unchanged path matters as much as the new refusal.

**The reason is free text, and that diverges from a sibling deliberately.** `erasure_records` stores an
exception *type name* and never a message, precisely so a message cannot leak an object key into a
receipt. Here the opposite holds: the whole purpose of the row is that an exceptional act taken against
a paying tenant is **justified**, and a justification that cannot name what happened is not one. So
free text, with `personal-data.md` carrying the same caveat `conversation_notes` already does.

**Two things `adr/0118` records that a reader would otherwise waste time on.**

`module_grant_audit` **is not a table.** Both this item's own text and the brief that dispatched it
referred to it as though it were; the migration of that name added two columns to `enabled_modules`.
The ADR says so plainly, so the next reader finds a paragraph instead of hunting for a half-built
table.

And it **declines the `required`-nullable trick** that `ExpiresAt` uses to force a caller to state a
value explicitly. Omitting `Force` is never ambiguous — absence means *not forcing* — and that trick
belongs where a default would lie, not everywhere it once helped.

**Fourth instance of one mechanism in three days.** No foreign key on `site_id`, for the same reason
`adr/0111`, `0112` and `0113` each gave for their own tables and a fourth that is specific here: the
tenant whose purchase was overridden and who then closes their account is exactly the one most likely
to ask, later, who did this and why. A cascade would erase the answer along with the account.

**A process note worth keeping.** The implementing worker wrote its `ago-root` changes into the
**primary checkout** rather than a worktree, caught itself, and said so in its report. The wording it
misread was mine: the brief said *you are not editing `ago-root`* next to *never touch `roadmap.md` or
`adr/README.md`*, and the second reads as a gloss on the first — while this item's own Scope requires
an `authorization.md` change. The contradiction was in the instruction, not in the worker.
