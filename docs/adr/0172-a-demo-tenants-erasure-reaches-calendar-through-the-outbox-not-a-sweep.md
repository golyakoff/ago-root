# ADR-0172: A demo tenant's erasure reaches AGO Calendar through the outbox, not a cross-database sweep

- **Status**: Accepted
- **Date**: 2026-09-14
- **Stage**: 25 (`25-82`)
- **Extends**: `adr/0093` (the two-schema boundary this decision crosses again, in a direction that
  boundary's own prior crossings - `adr/0125`, `adr/0147`, `adr/0149`/`0166`, `adr/0165` - did not yet
  need: a tenant's own *disappearance*, not a fact about a tenant that still exists). Amends neither.

## Context

`25-82`'s own count, 2026-09-14: of 74 distinct `tenant_id`s in `ago_calendar.role_assignment_projections`
(`22-16`), only 4 had a matching row in `ago_chat.sites`. The other 70 belonged to demo tenants
`Ago.Chat.Worker.DemoTenantExpiryJob` had already deleted. That job removes a demo tenant with a raw
`DELETE FROM sites` and no outbox write at all - `personal-data.md`'s own `DemoTenantExpiryJob` row
already named `outbox` on its "does not reach" list before this item closed the gap for the one
consequence that had accumulated enough to be counted.

Two shapes were on the table for closing it, both named in the item's own Scope:

1. **A scheduled sweep** comparing `ago_chat.sites` against `ago_calendar.role_assignment_projections`
   and deleting whatever the calendar holds an opinion about but the chat database no longer does.
2. **An erasure-shaped event**, published through the outbox at the moment `DemoTenantExpiryJob`
   actually removes a site row, consumed by a new `ago-calendar` consumer that drains its own copy.

A third option surfaced only by reading the actual code rather than the item's own framing: **reuse
the synchronous, HTTP-based module-erasure path `22-30` already built** -
`Ago.Chat.Application.Abstractions.IModuleRegistrationGateway.EraseTenantDataAsync`, called today only
by `Ago.Chat.Worker.SiteErasureJob` (the owner-initiated, GDPR-shaped erasure job), which asks each
module a site has *ever had enabled* (`IEnabledModuleReadStore.GetAllForSiteAsync`) to erase its own
copy of that tenant's data before the site row goes.

## Decision

**The outbox event. `DemoTenantExpiryJob` publishes `Ago.Chat.Contracts.SiteErased` (`SiteId`,
`OccurredAt`, `CorrelationId`) in the same transaction as the site `DELETE` it already performs**
(rule 4), and `ago-calendar` adds one new consumer, `Ago.Calendar.Worker.SiteErasedConsumer`, that
calls the identical `EraseTenantDataHandler`/`ITenantErasureRepository.EraseAsync` port `22-30`'s own
HTTP endpoint already calls.

The reuse-the-HTTP-path option was rejected first, on a fact only visible in the actual publishers of
`RoleAssignmentsChanged`: that event fires whenever any operator's role or permission set changes -
site registration, invite redemption, removal - **unconditionally, with no dependency on whether the
calendar module was ever enabled for that site.** `IModuleRegistrationGateway.EraseTenantDataAsync`,
by contrast, is only ever called for a module the site's own `enabled_modules` table names. A demo
tenant mints a founder operator with seeded roles at registration and never calls
`EnableModuleForSiteAsOwner` - there is no add-on to buy in a 24-hour trial - so `SiteErasureJob`'s own
module gate (`EraseModulesAsync`) would find zero enabled modules for every demo tenant and never call
the calendar at all. Wiring `DemoTenantExpiryJob` to the same gate would have reproduced the identical
gap the count just found: correct-looking code that never actually reaches the table it was meant to
drain. This is also, independently, a latent gap in `SiteErasureJob`'s own path for a **non**-demo
tenant whose operators hold calendar permissions without the module ever being formally "enabled" -
noted here because this ADR's own reasoning explains it, not fixed here: `25-82`'s own Scope is the one
accumulation it measured, and generalising the module gate is a decision for whoever picks that up.

The sweep was rejected second, once the event path's true cost was visible: **almost nothing new**.
`ago-calendar`'s own `ITenantErasureRepository.EraseAsync` already exists, already erases
`role_assignment_projections`, `contact_visibility_projections` and the `tenants` row with everything
that cascades from it, and is already exhaustively proven idempotent against a real Postgres
(`TenantErasureEndpointTests`). The outbox/broker/consumer transport between the two products already
exists (`adr/0093`, four crossings before this one). What was actually missing was one publisher on
the chat side and one fifteen-line consumer on the calendar side, both following patterns
(`RoleAssignmentsChangedConsumer`, `TenantSuspensionChangedConsumer`) already established in the same
files. A sweep, by contrast, would have needed either a new cross-database read `adr/0093`'s own "no
product reads another's tables" boundary forbids outright, or `ago-chat` periodically publishing a
full tenant-id manifest for `ago-calendar` to diff against - genuinely new machinery, replacing a gap
that a nine-line publisher and a fifteen-line consumer already closed.

## Consequences

- **Reached asynchronously, on the outbox dispatcher's own cadence - not synchronously with the
  `DELETE`.** The same eventual-consistency window every other crossing on this boundary already
  carries (`messaging.md`'s "Facts that cross products"), now five rather than four.
- **`SiteErased` is deliberately not named for the one job that publishes it today.** The identical
  fact would describe `Ago.Chat.Worker.SiteErasureJob`'s own site deletion just as accurately, and -
  per this ADR's own Context above - that job has its own latent version of the gap this item closes,
  for a site whose operators hold calendar permissions with no module ever formally enabled. Whether
  `SiteErasureJob` should publish the same event is left to whoever reads this ADR next; nothing about
  the event's shape would need to change if it did.
- **`ago-calendar`'s `SiteErasedConsumer` reuses `EraseTenantDataHandler` wholesale**, not a
  narrower delete limited to `role_assignment_projections`. For the case this item measured (a
  chat-only demo tenant) the `tenants`-row branch is a no-op, since no `Tenant` row was ever
  provisioned; if a demo tenant ever does carry one, draining it too is the identical class of fix,
  not scope creep - a hand-written delete limited to one table would have had to duplicate logic this
  port already gets right.
- **No migration in either repository.** Both databases already carry every table and index this
  decision touches - `outbox`/`inbox` (`ago-chat`, since Stage 2), `role_assignment_projections`/
  `contact_visibility_projections`/`tenants`/`inbox` (`ago-calendar`, since `22-05`/`22-30`).
- **Whether the accumulation this item found was a personal-data question or an ordinary staleness
  one is not decided by this ADR.** `docs/backlog/25-82-*.md` names it explicitly as open, for the
  author. Both framings want the identical mechanical fix this ADR describes; the ADR does not need
  the answer to be correct, and does not attempt to give one.

## Alternatives considered

- **A scheduled cross-database sweep.** Rejected above - `adr/0093`'s own boundary forbids a direct
  cross-database read, and the manifest-publishing alternative is new, recurring machinery replacing a
  gap two small, pattern-following files already close.
- **Reusing `IModuleRegistrationGateway.EraseTenantDataAsync` (the synchronous, HTTP, module-gated
  path `22-30` built).** Rejected above - gated by `enabled_modules`, which a demo tenant never has a
  row in, so this path would never actually be called for the tenants this item measured.
- **A narrower `ago-calendar` deletion limited to `role_assignment_projections` alone**, rather than
  reusing `ITenantErasureRepository.EraseAsync` wholesale. Rejected: the wider port already exists,
  already handles the "no tenant row" case as a no-op, and already carries its own idempotency proof:
  a narrower rewrite would have been strictly more new code for a strictly narrower guarantee.
