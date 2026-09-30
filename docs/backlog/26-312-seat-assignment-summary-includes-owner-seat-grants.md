# 26-312 · [ago-chat] seat-assignment-summary must include owner seat grants in role limits

- **Stage**: 26
- **Status**: done — merged as `ago-chat#402` (`4c6a71a`), deployed to the demo stand
  (`ago-deploy#336` pins the three hosts + migrator; no migration in this SHA).
- **Found**: 2026-09-30, live on the stand. Platform owner granted +1 Administrator above tariff to
  «Салон Топаз» (`owner_seat_grants` row present), but the Android «Команда» tab kept showing
  «Администраторов: 1/1» and never changed on refresh or re-login.

## Root cause

`GetSeatAssignmentSummaryHandler` (serves `GET /api/v1/sites/{siteId}/operators/seat-assignment-summary`,
used by the Android team tab via `OperatorTeamApi.fetchSeatSummary` and by the console team page)
computed each role's limit as `RoleSeatLimits.LimitFor(roleName, site)` — the site's base
`SeatLimit`/`AdminLimit` only — and never consulted `IOwnerSeatGrantStore`. So platform-owner seat
grants were invisible in the team display, even though the enforcement path
(`OperatorRoleSeatCapacity`) and the owner console read (`GetOwnerSeatSummaryHandler`) both already
add them. The number is a live read (CLAUDE.md rule 8), so re-login/refresh was never the lever — the
computation itself was short.

## Fix

`GetSeatAssignmentSummaryHandler` now adds the live owner grant per role, mirroring
`GetOwnerSeatSummaryHandler` exactly:
`limit = RoleSeatLimits.LimitFor(role, site) + grants.GetEffectiveExtraAsync(siteId, OwnerGrantRoleFor(role), now)`.
Read live, never cached. No endpoint/DTO/client change — the shared endpoint fixes Android and console
at once. Billing-purchased extras are already folded into `LimitFor(site)` (the owner read treats them
the same), so no separate billing term was added.

## Done when

- [x] `seat-assignment-summary` returns admin/operator limit including active owner seat grants,
      matching the owner seat-summary for the same site.
- [x] Android «Команда» shows «Администраторов: 1/2» for Салон Топаз after deploy (no re-login).
- [x] Unit test: a site with `AdminLimit`=1 and an owner Administrator grant of 1 reports limit 2,
      `overLimit=false` at held=1 — fails-before proven (expected 2, actual 1 on the old code).
- [x] Backend gates green: format clean, build 0 warnings, full suite 4315 passed / 0 failed
      (Domain 832, Application 1691, FakeCrm 21, Architecture 53, Concurrency 91, Integration 1627).
