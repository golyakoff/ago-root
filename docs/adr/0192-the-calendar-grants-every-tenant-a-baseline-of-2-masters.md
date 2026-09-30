# ADR-0192: the calendar grants every tenant a baseline of 2 masters; the owner grant raises a floor, not a from-zero allowance

- **Status**: Accepted
- **Date**: 2026-09-30
- **Stage**: 26 (`26-317`)
- **Amends**: ADR-0125

## Context

`adr/0125` made a tenant's worker (master) quota **zero until granted** — the calendar add-on was
modelled as sold per-master, with the platform owner (or, later, billing) setting the number, propagated
to ago-calendar by the `ModuleQuantityGranted` integration event and enforced in
`WorkerRepository`'s locked create/reactivate path.

Onboarding the first real client (`26-317`, 2026-09-30) showed the cost: a freshly-provisioned calendar
tenant has `WorkerQuota = 0` and cannot create a single master until the platform owner sets a quantity
by hand — which is exactly what happened for «Салон Топаз», and is neither discoverable nor self-service.
The author's product decision: a master is a **name that bookings are allocated to** (a resource, never
an operator/login), every tenant with the calendar module gets **2 masters by default**, and more only
through the platform-owner grant that already exists.

## Decision

The calendar defines a domain default `Tenant.DefaultWorkerQuota = 2` and enforces the **effective**
quota `max(WorkerQuota, 2)` everywhere the quota is consumed: the create/reactivate lock-and-count
(`GREATEST(worker_quota, 2)` in the locked SQL), the downgrade deactivation policy, the owner impact
preview, and the console-facing configuration read. `WorkerQuota` continues to store exactly what
ago-chat granted (audit-clean); the floor is **computed, never persisted**.

The owner-override is unchanged: `GrantModuleQuantityAsOwner` / `SetUnconditionalModuleGrantAsOwner` set
the `ModuleQuantityGrant(site,"calendar")` number, propagated by `ModuleQuantityGranted`; a grant now
names the desired **total** and takes effect only above the baseline of 2. This supersedes `0125`'s
"zero until granted" specifically for the calendar module. The "2" is a calendar-domain constant, so
ago-chat's `ModuleQuantityGrant` stays module-opaque (it never learns what it counts).

## Consequences

New tenants self-serve up to 2 masters with no owner action, closing the `26-317` onboarding gap.
**No data migration and no schema change:** the floor is computed, so a tenant already over 2 (Топаз)
keeps its stored number unchanged (`max(stored,2)`), and a tenant at 0 gains 2. 2 becomes a hard lower
bound the quantity grant cannot go below; account suspension remains a separate fail-closed path
(`adr/0166`). **Commercial note:** the first 2 masters are now bundled with having the calendar module
rather than sold per-head — an intentional product change from `0125`.

## Alternatives rejected

- **Extend ago-chat `owner_seat_grants` with a "Master" role** — rejected: that is the operator/admin
  *additive-on-a-billing-base* pattern (`RoleSeatLimits.LimitFor` + `GetEffectiveExtraAsync`); workers
  have no `Site` base-limit to add to, calendar cannot synchronously consult chat at create time
  (rule 8), and it would pollute a chat enum with a product concept while duplicating the
  `ModuleQuantityGranted` channel that already carries this fact.
- **A calendar-local owner-grant table** — rejected: no platform-owner surface exists in ago-calendar;
  it would duplicate and split the owner-override that already reaches calendar (`0125`'s division:
  chat grants, calendar holds and enforces).
- **Put the "2" in chat's grant** — rejected: breaks `ModuleQuantityGrant` module-opacity by encoding a
  calendar fact in the platform product.
