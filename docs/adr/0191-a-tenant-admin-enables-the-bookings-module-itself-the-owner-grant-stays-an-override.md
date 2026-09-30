# ADR-0191: a tenant admin enables the bookings module itself; the owner grant stays an override

- **Status**: Accepted
- **Date**: 2026-09-30
- **Stage**: 26 (`26-316`)

## Context

Onboarding the first real client (2026-09-30) surfaced `26-316`: the calendar module did not turn on
for the tenant on its own. It was enabled by hand, acting **as the platform owner**. A normal tenant
admin, signing up on their own, would have no calendar and no way to get one — the only enable path a
session had ever used was the platform-owner grant (`SetUnconditionalModuleGrantAsOwner` /
`EnableModuleForSiteAsOwner`, gated by `RequirePlatformOwner`).

`adr/0151` is why the tenant-facing path did not exist. It removed `19-03`'s tenant self-service module
enable and stated the policy plainly: *"a tenant never turns a capability on for themselves — the
platform does, or the system does on a payment."* That rested on two things: a **mechanical** problem
(the route required the deployment-wide provisioning secret in a browser request body) and a
**commercial** one (a module in the price list is an entitlement, and a capability that turns itself on
for free is revenue).

The mechanical half is gone. `adr/0150` moved the provisioning secret and `adr/0154` moved the entry
point out of the request body into `Ago.Chat.Api` configuration, and `EnableModuleForSiteAsOwnerHandler`
already mints the per-site credential server-side. Nothing secret needs to reach a browser any more.

The author settled the commercial half for the calendar, 2026-09-30, choosing option (в) of `26-316`:
**self-serve.** A tenant admin turns the bookings module on and off from an admin settings section
(«Модуль «Записи»»), no platform-owner action. Onboarding friction — a paying prospect who cannot start
without a manual owner step — outweighed the revenue gate for this module at launch.

## Decision

**A tenant admin enables and disables the bookings/calendar module for their own site**, through
`PUT`/`DELETE /api/v1/sites/{siteId}/modules/{moduleKey}` (`EnableModuleForSiteHandler` /
`DisableModuleForSiteHandler`), gated by `Permission.SiteConfigure` on the caller's own site — the same
"this identity may act for the tenant as a whole" proxy every other `/account/*` settings screen uses,
never `RequirePlatformOwner`.

This **revises `adr/0151`'s "a tenant never turns a capability on for themselves" for the enablement
mechanism.** It does not merge the two layers `adr/0151` drew: enablement is still not the same as
having paid. What changes is *who may perform the enablement act* — for a self-serve module, the tenant.

**The platform-owner grant stays as an override**, not the normal route: it is still the way to grant a
trial or repair a failed provisioning, it is marked `GrantedByOwner`, and a tenant's own disable
**refuses** to turn off an owner grant (`Module.DisableOwnerGrantRefused`, a 409). The tenant governs
what they turned on; the platform still governs what it granted.

**Disable is non-destructive.** It deactivates the module-side registration and tombstones Chat's row
(`22-30` / `adr/0155`); it never erases the tenant's calendars or bookings. A re-enable restores access.

## Why this line and not another

**Because the barrier `adr/0151` named was mechanical, and it is gone.** `adr/0151`'s own text leads
with the secret-in-the-browser problem; `adr/0150`/`adr/0154` removed it. What remained was a policy
choice about the price list, and that choice is the author's to make per module. Making it for the
calendar does not reopen the secret hole: the tenant sends no secret, holds no cross-tenant key, and the
handler resolves everything sensitive from configuration.

**Enablement and billing stay separate, so this does not decide pricing.** This ADR is about the
*mechanism and who may use it*, not about whether the module is free. `adr/0151`'s own named gap —
"nothing grants an entitlement on payment today" — still stands, and `adr/0159` (an option is its own
subscription) is where a paid gate would live. A future plan gate (`26-316`'s option б) can wrap this
toggle without changing its shape: the toggle would simply refuse when the plan does not include it. The
decision here is deliberately the smaller one it takes to unblock onboarding.

## Consequences

**Positive.** A newly onboarded tenant reaches a working calendar with no platform-owner action — the
`26-316` bug is closed. The owner grant remains for trials and repair. The mechanism is generic: no
`"calendar"` literal enters `Ago.Chat.*` (the architecture guard still holds); the console, which may
know the module, supplies the key and the booking trigger word.

**Negative, and named.**

- **The calendar can now be turned on without being paid for.** That is the accepted trade for launch,
  not an oversight. If the calendar becomes plan-gated, the gate wraps this toggle (see above); until
  then, self-serve enablement is free for this module.
- **This is a per-module reversal, not a blanket one.** `adr/0151` still governs channels, AI and FAQ —
  none gains a self-serve toggle here. Re-deciding each is a separate act, not implied by this one.
- **Enabling seeds the module's role permissions** (`adr/0151`/`23-102`), so an admin who enables the
  calendar immediately holds `calendar:configure`. Disabling leaves those permissions in place
  (harmless without the module, and a clean re-enable), matching the owner revoke path.
