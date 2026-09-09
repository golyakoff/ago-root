# 25-41 · A third Administrator is priced in `0012`, but has no purchase path

- **Stage**: 25
- **Status**: ready
- **Depends on**: `25-25` (built the hard `AdminLimit` ceiling this item raises) and `25-29`
  (found this while correcting the seat-pricing formula against the same decision)
- **Found**: 2026-09-09, carried out of `25-29` at landing rather than left inside it (rule 14/15 —
  a chargeable purchase path is a different promise than a corrected pricing formula)

## What is actually true

`ago-business` decision `0012`'s own "## Business" section prices a third Administrator explicitly:
**+500₽/mo for each Administrator beyond two.** `25-29`'s own investigation found and corrected a
prior doc-comment (`SubscriptionTierBands.ResolveAdminLimit`) that had mis-cited this as unpriced
"custom" — it is a real, priced fact in the decision.

But `25-25`'s own `Site.AdminLimit` is a **hard block**, not a chargeable overage:
`ChangeOperatorRoleHandler` refuses a promotion past two Administrators outright
(`ConversationErrors.OperatorAdminLimitReached`). No site can hold a third Administrator today, paid
or not — there is nothing for a +500₽ charge to attach to.

## Scope

- **A purchase path that raises the ceiling**, mirroring `ChangeSubscriptionSeatsHandler`'s own shape
  for raising `Site.SeatLimit` — a tenant pays, the ceiling moves.
- **New persisted state**: how many extra Administrators were bought, most naturally a new column on
  `BillingSubscription` alongside `RequestedSeats` (`25-29`'s own read of where this belongs).
- **`ChangeOperatorRoleHandler`'s own guard changes** from a hard block to "allowed if paid for" —
  reading the new count rather than the fixed `BusinessAdminsIncluded` constant alone.
- **This item's own migration** — `25-29`'s worktree was explicitly told not to add one (the wave's
  slot was already claimed elsewhere) and stopped at the schema boundary rather than building this.

## Where this is likely to go wrong

- **Don't relax the hard block generally.** The ceiling still refuses by default; only a real,
  recorded purchase should move it for one specific site.
- **Charge it through the identical checkout/renewal path `25-29`'s own `ComputeSeatPriceRub` already
  established**, not a second, parallel billing mechanism for one more resource.
- **Proration and lapse.** If a paid-for extra Administrator slot is later downgraded away (fewer
  seats, tier change, or the charge itself lapses), decide what happens to a tenant already holding
  a third Administrator — the same "a downgrade destroys nothing" precedent `23-88`/`adr/0031` already
  establish, not a new invention.

## Done when

- [ ] A tenant can pay to raise their own Administrator ceiling above two, and the charge matches
      `0012`'s own +500₽/mo per additional Administrator.
- [ ] `ChangeOperatorRoleHandler` allows a promotion past two Administrators only when paid for,
      proven by a test that shows both the refusal (unpaid) and the success (paid) against the
      identical guard.
- [ ] The one migration this item needs lands cleanly, with no other concurrent `ago-chat` migration
      in the same wave.
