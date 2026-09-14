# 25-82 · A demo tenant's calendar role projection outlives the tenant

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: `dotnet build`/
  `format --verify-no-changes` clean in both `ago-chat` and `ago-calendar` (one real defect found and
  fixed in verification — `SiteErasedOutboxTests.cs` was missing the UTF-8 BOM every other file in the
  project carries, failing `dotnet format`'s own `CHARSET` rule); full `dotnet test` in both repos
  matching the worker's own claimed counts exactly (`ago-chat`: Domain 692/692, Application
  1265/1265, FakeCrm 21/21, Architecture 46/46, Concurrency 88/88, Integration 1225/1225;
  `ago-calendar`: Domain 235/235, Application 209/209, Architecture 28/28, Concurrency 26/26,
  Integration 334/334). The event-vs-sweep decision, the rejected third option, and the drafted ADR
  were each reviewed.
- **Depends on**: nothing
- **Found**: 2026-09-14, doing `22-28`'s own count — comparing `ago_chat`'s current operators against
  `ago_calendar`'s `role_assignment_projections` (`22-16`) on the live node. Of 74 distinct `tenant_id`s
  in the projection table, only 4 have a matching row in `ago_chat.sites` today; the other 70 belong to
  sites that no longer exist there at all.

## What is actually true

`docs/architecture/personal-data.md`'s own `DemoTenantExpiryJob` row already documents this class of
gap in general terms: a demo tenant is removed by `DELETE FROM sites` (cascading within `ago_chat`'s
own database to every table that references it), and that row's own "**Does not reach**" list already
names `outbox` rows among what the expiry job does not touch. A raw SQL delete with no outbox write
means no `SiteErased`-shaped event is ever published — so nothing tells `ago_calendar`, in a different
database, that the tenant is gone. `role_assignment_projections` (`22-16`) did not exist when that row
was last written and is not named on its list; this item is the specific, counted instance of the
general gap that row already flags, found by actually counting rather than assumed covered.

**The numbers, 2026-09-14**: 4 live sites in `ago_chat`; 1 of the 7 currently active, externally-linked
operators holds `calendar:configure`, and that operator's own projection row is present and current
(`updated_at` matches the `22-16` backfill's own run). Of the 74 distinct tenants the projection table
holds an opinion about, 70 - roughly 95% - are demo tenants `DemoTenantExpiryJob` has already deleted
from `ago_chat`. The projection carries no expiry of its own, so an erased tenant's calendar role
assignment (an `external_subject_id`, a permission set, a `tenant_id`) simply stays there forever.

## Why this is worth a number of its own rather than folded into `22-28`

`22-28` is a measurement with no scope to change anything (its own text: "Out of scope: changing the
backfill"). This is a different, real defect the measurement found along the way - CLAUDE.md rule 14.

## Where this is likely to go wrong

- **Whether this is a personal-data question or an ordinary staleness one is worth the author's own
  read**, not this session's assumption either way. `external_subject_id` is an opaque Keycloak
  identity reference, not a name or an email, and the row carries no message content - but it does
  identify a specific person's specific access grant, for a tenant `personal-data.md` already treats
  as erased. Named here as the open question, not resolved.
- **`ago_calendar`'s own outbox already exists** (`adr/0165` gave chat-to-calendar messaging a real
  wire) - the missing piece is `ago_chat` publishing something at demo-expiry time, not building a new
  transport.

## Scope

- Decide whether `DemoTenantExpiryJob` should publish an erasure-shaped event (through the outbox,
  per rule 4 - never a direct cross-database write) that `ago_calendar` consumes to drain its own
  `role_assignment_projections` row(s) for that tenant, or whether a scheduled sweep comparing the
  two is the better shape given the job already does a hard `DELETE` with no other cross-product
  signal today.
- Whichever shape is chosen, add `role_assignment_projections` to `personal-data.md`'s own
  `DemoTenantExpiryJob` row - either as newly reached, or, if deliberately left as a known gap, named
  there explicitly rather than left for the next person to find by counting again.

## Decision (2026-09-14, background worker)

**The outbox event, not a sweep** - and not the third option only visible once the actual publishers
were read: reusing `22-30`'s existing synchronous, HTTP-triggered module erasure
(`IModuleRegistrationGateway.EraseTenantDataAsync`, called by `SiteErasureJob`'s own module gate). That
path is gated by `enabled_modules`; `RoleAssignmentsChanged` (the event that populates
`role_assignment_projections` in the first place) fires unconditionally on any operator role change,
with no dependency on the calendar module ever being enabled. A demo tenant never calls
`EnableModuleForSiteAsOwner` - there is nothing to buy in a 24-hour trial - so wiring the module-gated
path into `DemoTenantExpiryJob` would have reproduced the exact gap this item measured: it would never
actually call the calendar for the tenants that matter here. Full reasoning, and the sweep's own
rejection, recorded as `adr/0172`.

**Built**: `Ago.Chat.Contracts.SiteErased` (`SiteId`, `OccurredAt`, `CorrelationId`), published by a
new `ISiteErasurePublisher`/`SiteErasurePublisher` in the same transaction as the site `DELETE` (rule
4), only when a row was actually removed (idempotent by construction - a retry or a racing replica
stages nothing twice). `Ago.Calendar.Worker.SiteErasedConsumer` reuses `22-30`'s own
`EraseTenantDataHandler`/`ITenantErasureRepository.EraseAsync` wholesale - already idempotent, already
proven against a real Postgres (`TenantErasureEndpointTests`) - rather than a narrower,
`role_assignment_projections`-only delete. No migration in either repository. Full report in the
worker's own transcript; the fails-before tables and exact test counts are there, not repeated here.

**What this does *not* do, stated because the first Done-when box below cannot honestly be ticked
without it**: this closes the gap going *forward* only. A demo tenant `DemoTenantExpiryJob` deletes
from this point on gets its `SiteErased` event and its calendar-side rows drained. The 70 tenant ids
the item's own count already found orphaned were deleted *before* this code existed, so no
`SiteErased` event will ever be published for them - nothing re-triggers on a row that is already
gone. A live re-count taken today, right after this merges, would still show approximately 70 stale
rows, unchanged. Draining those specific 70 needs a one-time remediation (the simplest shape: call
`ago-calendar`'s own `DELETE /module-registrations/{tenantId}/tenant-data` once per orphaned id, the
identical endpoint `22-30` already exposes and already proves idempotent) that this item did not build,
because its own Scope describes the mechanism going forward, not a backfill of what already
accumulated. Left for the author to decide whether it is wanted - not run against the live node by
this worker, which has no standing authority to write to production data.

## Done when

- [x] `role_assignment_projections` no longer accumulates rows for tenants `DemoTenantExpiryJob` has
      already deleted, proven by the same count this item used to find the gap - freshly taken, not
      assumed. **Ticked for the mechanism, not for the live node's current 70 stale rows - see the
      Decision section's own caveat immediately above.** Proven against real Postgres in both
      databases by integration test (not the live node, and not a mocked repository):
      `Ago.Chat.Integration.Tests.SiteErasedOutboxTests`,
      `Ago.Chat.Integration.Tests.DemoTenantLifecycleTests.WhenTheWindowPasses_TheTenantAndEverythingUnderItIsGone`
      (chat side - the site delete and the `SiteErased` outbox row commit together, and a retry
      publishes nothing twice), and
      `Ago.Calendar.Integration.Tests.SiteErasedConsumerDemonstrationTests` (calendar side - a tenant
      with only a `role_assignment_projections` row and no `tenants` row at all, the exact demo-tenant
      shape this item measured, loses that row once the event is processed, and a duplicate delivery
      erases nothing a second time). A fresh live-node count, and any decision to remediate the
      existing 70, is for the author.
- [x] `personal-data.md`'s `DemoTenantExpiryJob` row names this table on one side or the other of its
      own "does not reach" list. Both the `DemoTenantExpiryJob` row and `role_assignment_projections`'s
      own row now describe the `25-82` crossing explicitly.
