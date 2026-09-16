# 25-114 · The owner console has no way to grant a channel entitlement

- **Stage**: 25
- **Depends on**: `25-113` (the config gap that made this genuinely untestable end to end)
- **Status**: ready
- **Found**: 2026-09-16, while diagnosing `25-113`: even once a channel's entitlement mapping is
  correctly configured, the platform owner has no way to actually grant one from the console - the
  mechanism exists in the backend, the wiring to reach it from a screen does not.

## What is actually true today

`GrantModuleQuantityAsOwnerHandler` (`23-66`) is exactly the right mechanism - a generic
`(siteId, moduleKey, quantity)` grant, and `ChannelEntitlement.IsEntitledAsync` (`23-85`) already
resolves a channel kind to the `ModuleKey` `"channel"` and reads its quantity through this identical
store. No new backend write is needed.

`ago-console`'s `OwnerSiteDetailPage.tsx` already calls this handler (`grantOwnerModuleQuantity`) -
but only from a dialog opened by clicking an *existing* module row (`setQuantityModule(module)`,
where `module` comes from the page's own rendered list). That list is built entirely from
`modules.Select(module => ToModuleDto(module, quantities))` in `GetSiteForOwnerHandler` - `modules`
itself comes from `IEnabledModuleReadStore.GetAllForSiteAsync`, which reads `enabled_modules`.
`quantities` (from `IModuleQuantityGrantStore.GetAllForSiteAsync`) is used only to *enrich* a row that
already exists from the first query - never as a source of rows on its own.

`"channel"` deliberately never gets an `enabled_modules` row - `ChannelEntitlement.cs`'s own remarks
say why: "a billing-driven grant writes a `ModuleQuantityGrant` with no entry point, no credential and
no synchronous module-side registration call... pointing this mapping at [a real module] would leave
chat believing the module is granted while nothing routes to it." That is the right backend design.
The consequence nobody drew out: **a quantity grant for a pseudo-module with no `enabled_modules` row
can never appear as a row in this screen, so there is nothing to click to open the quantity dialog for
it, ever** - not "hidden until granted once", genuinely unreachable through this page's own UI.

## Scope

- The platform owner can grant (and see, and change) a site's own channel-quantity entitlement
  (`ModuleKey` `"channel"`) from `/owner/sites/{siteId}`, without it needing to already exist as an
  `enabled_modules` row.
- Reuse `grantOwnerModuleQuantity`/`GrantModuleQuantityAsOwnerHandler` exactly as they are - this is a
  console-only gap, not a backend one. No new endpoint, no new port.
- Decide, and state explicitly: does this need its own dedicated section (distinct from the modules
  list, since `"channel"` is not a module the way `"calendar"` is), or does the modules list itself
  gain a synthetic "channel" row when no real one exists? Either is defensible; a silent third option
  (extending `enabled_modules` to cover this pseudo-module) is not - that would reopen exactly the gap
  `ChannelEntitlement.cs`'s own remarks name for why `"channel"` deliberately has no entry point.

## Where this is likely to go wrong

- **Don't give `"channel"` an `enabled_modules` row to make it fit the existing list.** That is the
  literal design mistake `23-85`'s own reasoning already rejected for calendar/faq - it would make
  chat believe a module is enabled when nothing routes to it.
- **The quantity here has a different meaning than a calendar's "N masters".** For `"channel"`, any
  quantity `> 0` means "entitled" (`ChannelEntitlement.IsEntitledAsync`'s own check) - the UI copy
  should not imply the number itself matters the way it does for calendar seats, unless a future item
  gives channel quantities their own meaning (e.g., "up to N connected bot accounts").
- **This item's own reproduction needs `25-113` already deployed** - test against a site whose
  `enabled_modules` genuinely has no `"channel"` row (true of every site today) and confirm the new UI
  path, once used, is what actually flips a real tenant's `/channels/telegram` connect attempt from
  refused to accepted - the actual end-to-end walk `25-113` could not complete on its own.

## Done when

- [ ] The platform owner can grant a site's `"channel"` quantity from `/owner/sites/{siteId}` with no
      pre-existing `enabled_modules` row for it.
- [ ] The owner can see the current granted quantity (or that none exists) for `"channel"` on the same
      screen, not only immediately after granting it.
- [ ] A real end-to-end walk, once this ships and `25-113`'s config fix is live: grant a real tenant's
      Telegram entitlement through this new UI, then confirm that tenant's own `/channels/telegram`
      connect attempt (a real bot token) succeeds where it was refused before.
