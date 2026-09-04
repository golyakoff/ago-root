# the owner can find one tenant and see what it holds

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-13` is not a dependency, but this read is what verifies its override
  afterwards, so landing it first makes `23-15`'s procedure writable.
- **Decision**: `docs/design/decisions.md` §6, which keeps `/owner` read-only for now

## Goal

The platform owner, handling a support request about one named shop, can find that shop and see its
actual state: which modules it holds, which of those the owner granted rather than the tenant enabled
for itself, and when each grant ends — including when it never does.

Two halves of one support moment, which is why they are one item. `GET /api/v1/owner/sites` takes
`(Before, Limit)` and nothing else — a cursor page in site-id order, which the console's own caption
says plainly is "not ranked by size or activity" — so finding a named tenant means loading pages
until it appears. And once found, the eight aggregate columns say nothing about entitlements, so a
grant made through `22-17`'s API is invisible from the moment it is made (`ui-inventory.md` §8.1,
§13.7).

`flows.md` 5.1: *"so that I can find the one I am being asked about."* 5.3: *"Must be able to see the
tenant's actual state and act on it."* Neither clause has an implementation.

## Why one item and not two

Neither half completes the support flow alone. A search that lands on a row showing eight numbers
still leaves the owner reading SQL; an entitlement column on a list nobody can search through is
reachable only by paging. One promise, two places (`CLAUDE.md` rule 15).

## What must not break

`ListSitesForOwner` / `PlatformOverviewReadStore.ListSitesAsync` is **the one deliberately
cross-tenant read in the codebase** (`tenant-isolation.md`), and `PlatformOwnerAsTenantTests` asserts
the result contains a tenant the caller has no row in. `flows.md` 5.1's own constraint is the one
this item is most able to break: *"Must be able to trust that the list is complete"* — a filter that
silently narrows reads exactly like a platform with fewer tenants. **Any predicate added here is
explicit in the response, never implicit in the query.**

## Context to read first

- `docs/design/decisions.md` §6; `docs/design/flows.md` 5.1, 5.2, 5.3
- `docs/design/ui-inventory.md` §8.1 — eight columns, cursor paging, two tooltip-only facts, no
  drill-down, deliberately hardcoded English
- `docs/adr/0098-*` — an owner grant is recorded on the entitlement it creates
- `docs/architecture/tenant-isolation.md` — the `GET /api/v1/owner/sites` exemption and how it is
  worded
- `Ago.Chat.Domain/EnabledModule.cs` (`GrantedByOwner`, `ExpiresAt`, and the remark that expiry is
  checked live in the read-store query rather than by a sweep),
  `Ago.Chat.Application/Abstractions/IEnabledModuleReadStore.cs`
- `Ago.Chat.Application/UseCases/ListEnabledModulesForSite/*` — `23-01`'s site-scoped read, which
  this one is the cross-tenant sibling of; the two must not be confused for one another

## Scope

- A name/id predicate on `ListSitesForOwner`, applied in `PlatformOverviewReadStore` and **reflected
  back in the response**, so the console can say *"3 of 41 sites match"* rather than showing three
  rows that look like the whole platform.
- A per-site detail read — `GET /api/v1/owner/sites/{siteId}` — returning the eight existing facts
  plus the site's enabled modules with, per module, `GrantedByOwner` and `ExpiresAt`, or an explicit
  *no end date*.
- Both gated exactly as `GET /api/v1/owner/sites` is: the Keycloak realm role, decided by the server
  per request, never a claim the console reads.
- `ago-console` `/owner`: a search field and a per-site drill-down. §8.1 records that there is no row
  link and no detail route; this adds the first one, in the same deliberately hardcoded English the
  screen already uses and which `ux-gate` already skips by name.
- **The expiry warning, in words.** `flows.md` 5.2: `ExpiresAt` binds the granting side only — chat
  stops offering the module the instant it lapses, and **the module is never told**. A screen
  presenting expiry as a clean end date would be lying to its own author, so the screen says what
  expiry does and does not do.
- `tenant-isolation.md`'s owner section gains the new route and states that it is exempt for the same
  recorded reason the list is.

## Out of scope

- **Granting or revoking from the console.** §6: runbook for now (`23-15`), because both writes
  require the deployment-wide provisioning secret in the request body (`adr/0095`) and a console form
  would put a secret into a browser. §6 records the later shape — chat holding the secret in its own
  configuration — as an openly-made amendment to `adr/0095`, not as this item's work.
- The revoke asymmetry itself — `23-13`. This screen is where its consequence becomes *visible*, and
  the two items are otherwise independent.
- Translating `/owner`. §8.1 records the hardcoded English as deliberate and reasoned.
- Any aggregate the list does not already compute.

## Done when

- [ ] Searching by part of a site's name returns it, and the response states how many of how many.
- [ ] An empty search returns the unfiltered list, unchanged, and `PlatformOwnerAsTenantTests` passes
      untouched.
- [ ] The detail read shows a module the owner granted, with its expiry.
- [ ] A module the *tenant* enabled is distinguishable from one the owner granted.
- [ ] A grant with no expiry renders as an explicit *no end date*, never as a blank cell.
- [ ] An expired grant is shown as expired, matching what the live read-store query already decides
      rather than re-deriving it in the console.
- [ ] A non-owner gets the same refusal the list gives, and no site data is loaded.
- [ ] `tenant-isolation.md` and `authorization.md` carry the route.

## Open questions

None.
