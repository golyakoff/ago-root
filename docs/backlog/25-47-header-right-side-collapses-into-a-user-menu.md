# 25-47 · The header's right side collapses into a user menu

- **Stage**: 25
- **Status**: done — `ago-console#209`
- **Verified**: 2026-09-12 — `ago-console/src/shell/AppShell.tsx`'s `ShellIdentity` confirmed as the
  real header-right component (operator identity, `tenancySwitcher` prop, `onSignOut`);
  `TenancySwitcher.tsx` confirmed as the real tenant-switch component, already wired via
  `OperatorShell.tsx` (`tenancies`/`activeSiteId`/`switchTenancy`). Both dependencies (`25-46`, `25-48`)
  are done.
- **Depends on**: `25-46` (real icons for the menu's own rows), `25-48` (the Appearance page this
  menu links to — build together or stub the link and land `25-48` immediately after)
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

The header's right side shows its content directly today. The author wants it collapsed behind a
single avatar (initials, e.g. "АГ" for "Андрей Голяков"), GitHub's own user-menu as the reference.

## Scope

- Collapse the header's right side to one circular avatar showing the signed-in operator's initials.
- Clicking it opens a dropdown, GitHub-shaped:
  - **Header row inside the menu** (not a clickable item): avatar again, name and current tenant name
    stacked to its right.
  - **Tenant switcher**, alphabetical, one row per other tenant this operator belongs to, each with a
    🌐-equivalent Material Symbol. Clicking activates that tenant's context; the page reloads with the
    new tenant as the header's own active one.
  - Separator.
  - **Appearance** (`25-48`'s own page), with a palette-equivalent icon.
  - Separator.
  - **Sign out**, with the `logout` Material Symbol.
- If the operator belongs to only one tenant, the switcher section does not render at all — nothing to
  switch to.

## Where this is likely to go wrong

- **Tenant switch must actually reload with the new tenant as active**, not just change a client-side
  label — the header's own "current tenant" state comes from wherever the rest of the console already
  resolves the active tenant; reuse it, don't invent a second source of truth.
- **Only tenants this operator actually belongs to appear** — this is not a directory of every tenant
  on the platform.

## Outcome

`operatorInitials.ts` derives the avatar's letters (no avatar/initials logic existed anywhere before
this — answers `docs/design/gaps.md` pile 3 item 8 directly). The dropdown is page-local markup in
`ShellIdentity` (`AppShell.tsx`), not a new shared component — `adr/0030`'s fourth amendment is the
full reasoning for why a hand-rolled disclosure still holds at one level deep, not modal, no ARIA
`menu` protocol claimed. Tenant switch reuses the real `switchTenancy` mechanism
(`PermissionsContext`) unchanged — `TenancySwitcher.tsx`'s own `<select>` is deleted, its job fully
absorbed. Three inline Material Symbols Outlined SVG icons (`menuIcons.tsx`), path data fetched
verbatim from `google/material-design-icons` and independently re-verified byte-for-byte.

## Done when

- [x] The header's right side is a single avatar with initials; everything else lives behind it.
- [x] The dropdown matches the GitHub-shaped structure above, in order: header row, tenant switcher
      (alphabetical, only if more than one tenant), separator, Appearance, separator, Sign out.
- [x] Clicking a tenant in the switcher activates it and the header reflects the new active tenant
      after reload.
- [x] A single-tenant operator sees no switcher section at all.
