# 25-11 · The owner console's module status was never updated for 23-103

- **Status**: done — landed (`ago-console#177`) and redeployed to `ago-demo`
- **Date found**: 2026-09-09, live on `ago-demo` — the author saw both of a tenant's calendar grants
  read "Expired" with "No end date", and got a `409` trying to grant a third
- **Depends on**: none

## What happened

`23-103` (before tonight) replaced `OwnerSiteModuleDto`'s `IsActive: bool` with `Status: string`
("Active"/"Expired"/"Revoked") plus a new `Id` and `RevokedAt`, specifically because a boolean cannot
distinguish a deliberate revoke from a grant's own expiry quietly arriving. `ago-console` was never
updated to match: `OwnerSiteModule.isActive` kept declaring a field the server stopped sending, so it
read `undefined` at runtime, and `formatModuleStatus(undefined)` fell through its `? "Active" :
"Expired"` to **always "Expired"**, for every module, active or not.

**Nothing caught it.** TypeScript checks the declared type against itself, not against what the
server actually sends — a stale field name compiles cleanly and fails only at runtime. No test in
this codebase constructs an `OwnerSiteModule` from an undeclared field, so every test's own fixture
supplied `isActive` directly and passed.

**The tenant in question genuinely had two `calendar` rows** — one revoked 2026-09-08 06:33, one
granted 2026-09-08 08:30 and still active with no end date. Both real. Both rendered "Expired". The
author, reasonably reading "Expired" as "not working", tried to grant a third and was correctly
refused with `409` by the handler that checks for an existing active row — the backend was right the
whole time; only the display was lying.

A second, related gap in the same code: the modules table's React `rowKey` was `module.moduleKey`,
not unique once two rows share a module key (`adr/0155`'s own reason `OwnerSiteModuleDto.Id` exists
at all) — exactly this tenant's situation. Not confirmed to have caused a visible symptom here, but a
latent risk the same fix closes.

## What was done

- `OwnerSiteModule` (`ago-console/src/api/ownerApi.ts`): added `id`, `revokedAt`, `status`; removed
  the stale `isActive`.
- `formatModuleStatus` (`ownerSites.ts`): now a passthrough of the server's own string, not a boolean
  ternary. New `moduleStatusTone`: Active → success, Revoked → danger (a deliberate act), Expired →
  neutral (a quiet lapse) — the same distinction `23-103`'s own backend doc comment draws.
- `OwnerSiteDetailPage.tsx`: the Status column renders `module.status` directly; the table's `rowKey`
  is now `module.id`.
- New tests: a revoked grant reads "Revoked", never "Expired"; two rows sharing a module key render
  as two distinct rows.

Verified locally: `typecheck`/`lint`/`build` clean, full suite 105/1085 green, `ux-gate` 63/63.
Fails-before re-proved: reverted the Status render to the old always-"Expired" shape, watched the new
tests fail for the right reason, restored, re-ran green. Live redeploy and confirmation against the
real tenant is this item's own last Done-when box.

## Done when

- [x] The console renders the server's own `Status` (`Active`/`Expired`/`Revoked`), never a
      recomputed or stale boolean.
- [x] Two grants sharing a module key render as two distinguishable rows, keyed by `id`.
- [x] Redeployed to `ago-demo` (`6593638`), smoke 46/46. Visual confirmation against the real
      tenant is the author's own to make - the fix is live, waiting on a page refresh.
