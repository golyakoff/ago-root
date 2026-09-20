# 25-181 · The owner cannot grant a tenant extra seats by hand

- **Stage**: 25
- **Status**: done — `ago-chat#348` (`f4867a6`), `ago-console#266` (`076f3ae`). Independently
  re-verified before merging: full diff review across both repos, `dotnet format`/`build` clean (0
  warnings), `dotnet test` re-run directly — Domain.Tests 770/770, Application.Tests 1468/1468,
  FakeCrm.Tests 21/21, Architecture.Tests 52/52, Concurrency.Tests 90/90, Integration.Tests
  1486/1486; `ago-console` typecheck/lint clean, 1560/1560 tests, ux-gate 67/9. **A real gap was
  caught and fixed before merging**: the first pass wired the grant into the summary display and the
  demotion-avoidance path, but not into `OperatorRoleSeatCapacity` — the actual write-time gate every
  invite/promote/restore goes through — so the summary would have shown a raised limit an owner could
  not actually use. Sent back and fixed: the fix's own blast radius (12 call sites constructing
  `OperatorRoleSeatCapacity`, 2 of them found only by running the full suite, not by building) is
  documented in the merged PR. The headline promise is now proven end-to-end (an Admin invite refused
  at the billing-only limit succeeds once the owner grants +1 seat through the real handler, with a
  negative control and an expiry proof at the same enforcement point), not only at the display layer.
  Two real discrepancies found and correctly adapted to while building: `GetSelfAsync` premise
  aside, `IAdministratorLimitEnforcer` (the consequence the backlog cited) had already been retired by
  `25-170` before this session started, replaced by `OperatorRoleSeatReconciler`/
  `EntitlementWatchdogJob` - this item wired into the real, current mechanism instead.
- **Depends on**: nothing (independent of `25-25`/`25-95`/`25-96`, which built the *billing-driven* path
  this item adds a manual, owner-driven sibling to - not a replacement)
- **Found**: 2026-09-20, the author looking at a real tenant's owner screen
  (`https://office.reserve-me.ru/owner/sites/01a06262-d4f0-7fb6-94e0-9ff702db8a43`) and finding the
  "Операторы" section both mislabelled and missing the one capability an owner actually needs here.

## What is actually true today

`Site.SeatLimit` (Operator seats) and `Site.AdminLimit` (Administrator seats, `25-25`) are each set
**exclusively** through `Site.ActivateSubscription`/billing - `SeatChangeApplier` writes `SeatLimit`
directly to whatever the tenant just purchased; `AdministratorSlotChangeApplier` adds
`BillingSubscription.ExtraAdministratorsPurchased` on top of `SubscriptionTierBands.ResolveAdminLimit
(tier)`'s own baseline. **The two are not modeled the same way today** - Operator seats have no
"baseline + extra" split at all, Administrator seats do - worth naming explicitly for whoever builds
this, not assumed symmetric.

**There is no path for the platform owner to add seats by hand**, independent of a real purchase.
`OwnerOperatorsEndpoints`/`RestoreOperatorSeatAsOwnerHandler` only restore a *specific, already-existing*
operator's own seat (with a `Force` override that can knowingly push a site over its existing limit) -
that is a different thing from raising the limit itself, and leaves no record of *why* the tenant is
over.

**The exact real screen problem, quoted from the live page**: the section heading reads **"Операторы"**,
but the table beneath it lists every person who can sign in regardless of role (`OwnerSiteOperator`,
holding `Operator`, `Admin`, or both) - so "Оператор" the column header and "Operators" the section
title both collide with **`Operator`, the specific role**, right above a table where a row can say
`Operator, Admin` in its own Roles column. The author's own words: *"Вместо таблицы с конфузящими
пересечениями Оператор как любой человек, который заходит, и Operator как роль."*

## The real precedent to follow, not invent

`ModuleQuantityGrant.SetUnconditionalGrant(bool, string setBy, string reason, DateTimeOffset now,
DateTimeOffset? expiresAt = null)` (`23-86`/`25-115`) is the exact shape already in this codebase for
"the platform owner grants something extra, by hand, with who/why recorded and an optional expiry":
`reason` is required and non-blank whenever the grant is set; `expiresAt` is nullable, `null` meaning
"бессрочно" (indefinite, the author's own word for it there too); `EffectiveQuantity(now)` checks the
expiry against a caller-supplied clock, never `DateTimeOffset.UtcNow` inside Domain (CLAUDE.md rules 2/11).
**Follow this shape for the new seat grant rather than inventing a second one** - the author's own request
this time ("для однообразия - давай добавим") is exactly the instinct that produced that type's own
`reason` field in the first place.

## Goal - the reworked screen, as the author specified it

Replace the current "Операторы" section (`OwnerSiteDetailPage.tsx`, heading + note + table) with:

1. **Heading renamed to "Пользователи"** ("Users") - the table itself is unchanged in spirit (still every
   person who can sign in, still the `Оператор`/`Роли`/`Место` columns and the existing seat-restore
   action), only the section's own name stops colliding with the `Operator` role.
2. **A summary line above the table**, current usage against each limit:
   ```
   Администраторов: 1/1
   Операторов: 1/2
   ```
   (held count / current limit, per role - `GetSeatAssignmentSummaryHandler`'s own per-role shape,
   `25-18`'s history, is the most likely existing source to read this from rather than a new query -
   check it first.)
3. **A new capability, "Добавить сверх тарифа"** ("Add beyond the tariff"):
   - **Сколько** ("How many"): a `1`-`5` select.
   - **Кого** ("Who"): `Операторов` / `Администраторов`.
   - A checkbox, **"Истекает в дату"** ("Expires on"), revealing a date picker when checked - unchecked
     means indefinite, the identical `null`-`expiresAt` convention `ModuleQuantityGrant`'s own precedent
     already uses.
   - **A reason field** - the author's own explicit ask, for consistency with the precedent above: add
     it, required and non-blank, the same validation `SetUnconditionalGrant` already enforces.
4. The existing users table renders below this, unchanged.

## Where this likely lives, to save the next session's own discovery pass

- **Domain**: however the grant is modeled, it must be a *named, auditable, expirable* addition -
  `who` (the owner's own Keycloak `sub`, a raw string per `ModuleQuantityGrant.UnconditionalGrantSetBy`'s
  own "the platform owner has no row in this site's own operator roster" reasoning), `reason`, `grantedAt`,
  `expiresAt` (nullable), the quantity, and which role it applies to. Whether this becomes a new type
  alongside `ModuleQuantityGrant`, or a role-scoped extension of the existing `Site.SeatLimit`/`AdminLimit`
  computation, is a real design choice - read `SubscriptionTierBands.ResolveAdminLimit` and
  `AdministratorSlotChangeApplier` first, since Administrator seats already have an "additive extra"
  slot (`ExtraAdministratorsPurchased`) this could parallel; Operator seats do not, and would need one
  built rather than reused.
- **Expiry enforcement**: needs a live, caller-supplied-clock check the same shape
  `ModuleQuantityGrant.EffectiveQuantity(now)` already uses - an expired owner-grant silently stops
  counting toward the limit, it does not need a background job to "revoke" anything, the identical
  "computed fresh, never persisted as a stale fact" posture that type's own remarks state.
- **What happens when an owner-granted extra expires and the tenant is now over-limit**: `Site.
  ReduceAdminLimit`'s own remarks (cited above) already establish this codebase's own answer for the
  admin-limit-shrinks case - excess Administrators are demoted automatically via
  `IAdministratorLimitEnforcer`, never left silently over-limit. Whatever this item builds should reuse
  that consequence rather than inventing a second policy for the identical shape of problem.
- **API/console**: a new owner-only endpoint (`OwnerOperatorsEndpoints` or a sibling), and the
  `OwnerSiteDetailPage.tsx` rework described in Goal.

## Out of scope

- Any change to the *billing-driven* seat/admin-limit paths (`25-95`/`25-96`'s own e-commerce
  quantity-stepper self-service) - this item adds a second, owner-only, non-purchase path alongside it,
  never replaces it.
- Automatically notifying a tenant when an owner grant is added or about to expire - a real, separate
  feature, not decided here.
- Bulk-granting across multiple tenants at once - one tenant, one grant, from this screen.

## Done when

- [x] The section heading reads "Пользователи", not "Операторы" - the role/person naming collision the
      author named is gone from this screen.
- [x] A summary line shows current held/limit for both Operator and Administrator seats, matching
      whatever the console's own existing per-role summary source already computes.
- [x] The owner can grant 1-5 extra seats of either role, optionally with an expiry date, with a required
      non-blank reason - modeled on `ModuleQuantityGrant.SetUnconditionalGrant`'s own validated shape.
- [x] The granted extra seats count toward that role's own limit immediately, and stop counting the
      moment the expiry passes (checked live, not by a background job) - proven by a test that grants,
      confirms the raised limit, advances a fake clock past the expiry, and confirms the limit drops back.
      — proven at both the domain level and end-to-end against the real capacity gate
      (`OwnerSeatGrantCapacityTests`), not only at the display layer.
- [x] If a granted extra expiring drops a site below its live Administrator count, excess Administrators
      are demoted automatically, reusing the existing `IAdministratorLimitEnforcer` consequence rather
      than a new one. — `IAdministratorLimitEnforcer` was already retired by `25-170`; reuses the real,
      current `OperatorRoleSeatReconciler`/`EntitlementWatchdogJob` mechanism instead.
- [x] The existing users table (people, roles, seat-restore action) renders unchanged below the new
      summary/grant controls.
