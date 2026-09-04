# the enabled-modules read is scoped to the caller's own site

- **Stage**: 23
- **Status**: done — merged 2026-09-04, `ago-chat#172` (`ac9d878`)
- **Depends on**: nothing

## Goal

`GET /api/v1/sites/{siteId}/modules` answers only for the site the caller is an operator of. Before
this, it answered for any site whose id a caller could type.

This file is written after the fact, deliberately. The detail below was withheld from every public
repository while the hole was open — `CLAUDE.md`'s "everything is public" rule cuts both ways, and a
route with no scope check is the one thing that must not be described until it has one. It is
published now because the fix is merged.

## What was wrong

`ModuleEndpoints` mapped its group with `.RequireAuthorization("RequireOperatorIdentity")` and took
`siteId` from the route. That policy proves the caller is an operator **somewhere**, not an operator
of the site they named, and nothing downstream re-derived it: the `GET` handler reached
`IEnabledModuleReadStore` straight from the endpoint, with no use case in between. So any
authenticated operator of any tenant could read another tenant's enabled modules — each module key,
its entry-point URL, and, since `22-17`, whether the platform owner granted it and when that grant
lapses.

Three facts make this worth a file rather than a line in a changelog:

- **The four sibling verbs on the same group were never exposed.** `PUT`, `DELETE`,
  `/{moduleKey}/rotate` and `/{moduleKey}/verify` each dispatch to a handler that calls
  `IPermissionChecker`. Only the read skipped the handler layer, so the group *looked* uniformly
  gated and was not.
- **`TenantScopeTests` could not see it.** That rule walks `*Handler` classes; this path never
  reached one. A guard that inspects handlers is blind to a read that has no handler — which is the
  general lesson, not a fact about this route.
- **`tenant-isolation.md`'s "nineteen route groups, all permission-gated" was untrue** while this
  stood. It was found by checking `flows.md`'s stories against that document, not by a test.

## What shipped

The read now dispatches to `ListEnabledModulesForSiteHandler`, gated on `Permission.SiteConfigure` —
the same permission its four siblings require, because a module's entry point is configuration rather
than conversation data. The endpoint no longer touches a read store, which is the shape every other
read on this codebase's `/sites/{siteId}/...` routes already uses.

Files: `Ago.Chat.Api/Modules/ModuleEndpoints.cs`,
`Ago.Chat.Application/UseCases/ListEnabledModulesForSite/*`, `Ago.Chat.Module/ChatModule.cs`, plus
`ListEnabledModulesForSiteHandlerTests`, `ModuleEndpointsTests` and one addition to
`OwnerModuleEndpointsTests`.

## Done when

- [x] An operator of site B is refused the module list of site A.
- [x] An operator of site A holding `site:configure` still gets it.
- [x] The endpoint resolves no read store.
- [x] `tenant-isolation.md`'s claim about the module route group is true.

## What to carry forward

**A rule that walks handlers cannot see a path that has no handler.** The cheap generalisation is not
"add this route to a list" but "an endpoint that reads a store directly is outside every guard this
codebase owns". Whether that becomes its own arch rule is a question this item does not settle.

## Open questions

None.
