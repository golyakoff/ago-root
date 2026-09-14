# 25-82 · A demo tenant's calendar role projection outlives the tenant

- **Stage**: 25
- **Status**: ready
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

## Done when

- [ ] `role_assignment_projections` no longer accumulates rows for tenants `DemoTenantExpiryJob` has
      already deleted, proven by the same count this item used to find the gap - freshly taken, not
      assumed.
- [ ] `personal-data.md`'s `DemoTenantExpiryJob` row names this table on one side or the other of its
      own "does not reach" list.
