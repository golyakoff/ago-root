# 25-125 · A revoked module's row still offers Revoke and Set quantity

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: originally 2026-09-08 ("the first real revoke, minutes after the first real grant"), on
  a leftover branch (`docs/23-103-revoked-shown-as-expired`) recovered 2026-09-17 while triaging
  unmerged branches. Half of what that branch found was fixed properly, as its own commit message
  predicted, by `25-11` (`ago-console#177`) - the other half was never carried forward, and is still
  live today, confirmed by reading the current code rather than trusting the old report.

## What is actually true today

`23-103` (backend) replaced a site's per-module `IsActive: bool` with a real `Status` -
`Active`/`Expired`/`Revoked` - plus `RevokedAt`, specifically so a deliberate revoke could be told
apart from a grant's own end date quietly arriving. `25-11` fixed the console's own **label** to match:
`OwnerSiteDetailPage.tsx` now renders `module.status` directly, never a stale recomputed boolean.

**The other half of the original report was never addressed.** `buildModuleColumns`'s own `actions`
column (`OwnerSiteDetailPage.tsx`, ~line 2193) renders `Button`s for "Set quantity" and "Revoke"
unconditionally, for every row, regardless of `module.status` - confirmed by reading the function
directly, not assumed from the old report. A revoked module's row still offers both:

- **Revoke**, on an already-revoked module, either reports a meaningless success or errors on a state
  the screen itself just presented as actionable.
- **Set quantity**, on a revoked module, writes a grant nobody can use - the module is off; a quantity
  set on it has no effect a tenant would ever see.

`25-11`'s own "What was done" section never claims to touch this - it is scoped to the status label and
the table's `rowKey`, and its own Done-when boxes say only that. This is a genuine remainder, not a
regression in what `25-11` shipped.

## Scope

- `buildModuleColumns`'s `actions` column: gate both buttons (or at least "Revoke") on
  `module.status !== "Revoked"` - a revoked row should not offer to revoke it again. Decide, and say
  which, whether "Set quantity" on a revoked row should be hidden outright or left available with a
  different meaning (re-granting) - the backend's own `SetUnconditionalModuleGrantAsOwner`/
  `GrantAsync` semantics for a revoked row need checking before choosing, not assumed from the console
  side alone.
- New tests: a revoked row does not render an actionable Revoke button (or renders one that cannot
  reach a meaningless-success state); the existing Active/Expired rows are unaffected.

## Where this is likely to go wrong

- **Do not just hide both buttons for every non-Active status.** An `Expired` module is a real, past
  grant a tenant might reasonably re-grant via "Set quantity" - conflating it with `Revoked` (a
  deliberate act) would remove a legitimate action, not just a wrong one.
- **Check what the backend actually does today for a revoke-of-a-revoked or a quantity-set-on-revoked
  call** before deciding the console's own gating - hiding a button that the backend already refuses
  safely is cosmetic; hiding one the backend would silently misapply is the real fix.

## Done when

- [ ] A revoked module's row no longer offers to revoke it again.
- [ ] "Set quantity" on a revoked row either does something meaningful (a real re-grant) or is hidden -
      whichever was decided above, stated in the code.
- [ ] Active and Expired rows keep their existing actions, unchanged.
