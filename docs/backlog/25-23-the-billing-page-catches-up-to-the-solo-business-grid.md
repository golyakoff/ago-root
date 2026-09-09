# 25-23 · The billing page catches up to the Solo/Business grid

- **Stage**: 25
- **Status**: ready
- **Depends on**: `ago-business` decisions `0007`, `0011`, `0012` are the grid this page has to match
- **Found**: 2026-09-09, the author reading their own billing page

## What is actually true

`BillingPage.tsx` predates the tariff grid `ago-business 0012` settled:

- **The tier is shown raw** (`{status.tier}`, line 242) — whatever the server's enum member name is,
  unmapped and unlocalized. The free tier is named **Solo** in the actual grid (`0012`'s own heading:
  *"Solo бесплатен, Business с базой и доплатой за места"*), not "Free".
- **"Занято мест" / "Лимит мест: 2"** (`billingSeatsUsedLabel`/`billingSeatLimitLabel`) name neither
  which *kind* of seat nor distinguish a free allowance from a paid one. Since `0011`
  ("администраторы считаются отдельно от мест"), Operator and Administrator seats are two different
  counts against two different limits, and `0012` gives Solo its own included allowance separate from
  what can be bought beyond it — this page has no concept for either distinction.
- **`billingSeatCountFieldDescription`** ("От 2 до 100 мест. Точный ценовой диапазон подтверждается
  сервером.") is stale copy from before the grid existed in its current form.
- **The seat-count control is an editable field the tenant types a number into and submits directly**,
  with no purchase step — there is no ЮKassa integration yet (`23-86` is that gap, separately), so
  today's control implies a capability the backend does not actually have.

## Scope

- **Tier name**: map the tier enum to its real name — Solo for the free tier, Business for the paid
  one — rather than rendering the raw enum value.
- **Seat counts, split by role**: show Operator seats and Administrator seats as two separate
  used/limit pairs, matching `0011`'s own separation. Within each, distinguish the free allowance
  `0012` includes from limits on what can additionally be bought — name both rather than collapsing
  them into one "Лимит мест" figure.
- **Update the stale range copy** to whatever the current grid actually says, sourced from the same
  place the seat-limit numbers themselves come from (not retyped from `ago-business` by hand — the
  same "one source, not a hand copy" reasoning `25-20`'s price-list screen uses).
- **The seat-count control becomes a read-only summary line plus an add-seats stepper**: *"Добавить
  операторов: [1]"* with a spinner (1 or more) and an **[Добавить]** button, in the shape of an
  e-commerce quantity-plus-add-to-cart control — the author's own reference point. **The button is a
  stub for now** — it does not call ЮKassa or any payment flow; that integration is `23-86`'s own
  scope, not this item's. Clicking it today should do nothing that looks like a completed purchase.

## Where this is likely to go wrong

- **Do not build the ЮKassa call.** This item's whole point is the UI catching up to the grid; wiring a
  real purchase is explicitly `23-86`'s item, already scoped and larger. A stub button that visibly
  does nothing is the correct shape here, not a half-wired payment call.
- **Do not guess the current price range copy.** Read it from `ago-business 0012` (or whatever the
  backend's own configuration already encodes) and say where the number came from — CLAUDE.md's
  "measure or stay silent" applies to a price exactly as it does to a benchmark.

## Done when

- [ ] The tier renders as "Соло" / "Business" (localized), not a raw enum value.
- [ ] Operator and Administrator seat counts are shown separately, each against its own limit, with the
      free-allowance/paid-beyond-it distinction named rather than collapsed.
- [ ] The stale seat-range copy is replaced with the current grid's own numbers, sourced rather than
      retyped.
- [ ] The seat-count field becomes a read-only summary plus an add-seats stepper and an `[Добавить]`
      button that is a visible stub — no payment call, no state change that looks like a completed
      purchase.
