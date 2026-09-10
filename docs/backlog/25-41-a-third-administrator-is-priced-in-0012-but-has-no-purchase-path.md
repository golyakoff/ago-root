# 25-41 · A third Administrator is priced in `0012`, but has no purchase path

- **Stage**: 25
- **Status**: done — `ago-chat#257`
- **Depends on**: `25-25` (built the hard `AdminLimit` ceiling this item raises), `25-29`
  (found this while correcting the seat-pricing formula against the same decision), and `25-43`
  (landed 2026-09-10 — the price this item charges is a registered catalog key, not a call into
  `ComputeSeatPriceRub`; see the corrected Scope bullet below)
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
- **`ComputeSeatPriceRub` does not apply here and this bullet used to say otherwise** — that formula
  is the seat *band* (base-plus-marginal by count), and an Administrator is priced flat (+500₽/mo
  each, `0012`), never banded. What does carry over from `25-29`/`25-43` is the *mechanism*, not that
  formula: register a new key (e.g. `admin-extra`) in `PricedResourceKeys`, publish its version at
  500₽ (`25-43`'s own catalog — a real Rouble figure is `ago-business`'s call, never hardcoded here),
  and charge through the identical checkout/renewal path everything else in `25-43` already reads
  from — `IPriceCatalogRepository.FindCurrentAsync`, never a new parallel billing mechanism.
- **Proration and lapse — decided by the author, 2026-09-10: automatic downgrade, not `23-88`'s own
  precedent.** Unlike a worker over quota (`23-88`: stays exactly as it is, merely can't take new
  work), an operator whose paid Administrator slot lapses is **automatically demoted back to
  Operator** the moment the ceiling drops below their count — a deliberately stricter rule than
  `23-88`'s "downgrade destroys nothing," because unlike a worker's own history a role grant has no
  meaningful "frozen, can't take more" state to sit in. **Not yet decided, and needs settling before
  this ships**: which Administrator(s) get demoted first when more than one sits above the new
  ceiling. The precedent already in this codebase for "which of several excess things is affected
  first" is `adr/0125`'s own `WorkerQuotaPolicy` — most-recently-granted first — and the same rule
  applied here (most-recently-promoted-to-Administrator first) would need an ordering field on the
  role assignment if one does not already exist; confirm the shape before building rather than
  guessing at a tie-break.

## Done when

- [x] A tenant can pay to raise their own Administrator ceiling above two, and the charge matches
      `0012`'s own +500₽/mo per additional Administrator.
- [x] `ChangeOperatorRoleHandler` allows a promotion past two Administrators only when paid for,
      proven by a test that shows both the refusal (unpaid) and the success (paid) against the
      identical guard.
- [x] The one migration this item needs lands cleanly, with no other concurrent `ago-chat` migration
      in the same wave.
- [x] When a paid Administrator slot lapses (downgrade, tier change, or the charge itself lapsing),
      the operator(s) above the new ceiling are automatically demoted to Operator — most-recently-
      promoted first when more than one is affected — proven by a test.

## Outcome

Shipped 2026-09-10, `ago-chat#257`, independently re-verified before merging.

- **Purchase path**: `PurchaseAdministratorSlotHandler`
  (`Ago.Chat.Application.UseCases.PurchaseAdministratorSlot`), the identical prorated
  charge-then-apply shape `ChangeSubscriptionSeatsHandler` uses for seats, restated for a flat price
  (`SubscriptionTierBands.AdminExtraPriceKey`, a new `admin-extra` catalog key at 500₽, `25-43`'s own
  mechanism reused, never a second one). `POST /api/v1/sites/{siteId}/billing/subscriptions/{id}/administrators`.
- **New persisted state**: `BillingSubscription.ExtraAdministratorsPurchased` and
  `AdminExtraPriceVersion` (int columns, default `0`), alongside `RequestedSeats` as scoped.
- **The guard**: `ChangeOperatorRoleHandler` needed no code change — it already read the dynamic
  `Site.AdminLimit` rather than the fixed `BusinessAdminsIncluded` constant. The fix is entirely in how
  `AdminLimit` is computed: `Site.ActivateSubscription` now adds `extraAdministrators` to
  `SubscriptionTierBands.ResolveAdminLimit(tier)`.
- **The tie-break, the one open design decision this item left unresolved.** `role_change_records`
  (`23-72`) turned out to carry a real ordering field — `changed_at`, keyed by
  `changed_operator_id`/`new_role_name = "Admin"` — but only for promotions actually made through
  `ChangeOperatorRoleHandler`. Two paths put an operator into `"Admin"` without it: the account's own
  founder (seeded both roles at registration) and an invite redeemed directly into `"Admin"`. Rather
  than inventing a synthetic timestamp for those two (their `operators.created_at` answers "when did
  they join", not "when did they become Administrator", and conflating the two would misrank a
  long-tenured Operator promoted yesterday against a founder who has been Admin since day one), the
  chosen rule ranks every Administrator with a real promotion record ahead of every one without one,
  most-recent-first within that group; an Administrator never actually promoted is demoted only after
  every promoted Administrator already has been. Remaining ties fall back to `OperatorId` ordering.
  Implemented in `AdministratorLimitEnforcer` (`Ago.Chat.Infrastructure.Postgres`), whose own doc
  comment carries the full reasoning.
- **Demotion on lapse**: wired into the same two `Site.ActivateSubscription` call sites in
  `SubscriptionRenewalApplier` that already detect a seat-limit drop (`ApplyLapseAsync`'s base-row
  branch unconditionally, `ApplyRenewalSuccessAsync`'s deferred-downgrade branch only when
  `AdminLimit` actually fell) — no parallel lapse-detection path was built.
- **Migration** `20260910051518_Stage25AdministratorPurchasePath` — the two new `billing_subscriptions`
  columns, plus widening `role_change_records.changed_by_operator_id` to nullable (an automatic
  demotion is not "changed by" any operator). Applied and inspected against real local Postgres.
- **Found but not fixed, left exactly as found**: wiring the new `Billing.AdministratorCountNotAnIncrease`
  error code surfaced that five pre-existing `Billing.*` codes (`SeatCountUnchanged`, `InvalidSeatCount`,
  `SubscriptionNotFound`, `SubscriptionNotActive`, `PaymentProviderRefused`) fall through to HTTP 500 in
  `ErrorExtensions.cs` — a gap this item did not cause. Left untouched per this codebase's own documented
  convention (`ErrorExtensions.cs`'s own comment, citing `25-25`/`23-72`) of not scope-creep-fixing every
  adjacent gap found while landing an unrelated item.
- **`docs/architecture/authorization.md`** updated in the same change (uncommitted, with this file) —
  its own `23-72` section had said promotion "is never refused for capacity" and that an administrator
  "is a role, not a purchase," both now false as of `25-25` and this item respectively.
