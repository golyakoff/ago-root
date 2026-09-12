# 25-23 · The billing page catches up to the Solo/Business grid

- **Stage**: 25
- **Status**: ready
- **Depends on**: `ago-business` decisions `0007`, `0011`, `0012` are the grid this page has to match;
  `25-41` — **added 2026-09-10, found while re-checking this item before dispatch**: the tenant billing
  status wire (`GetBillingStatusHandler`/`BillingStatusDto`, `Ago.Chat.Contracts`) has no Administrator
  seat count, no free-vs-paid-beyond-it split, and no purchased-extra-Administrators field at all —
  `25-41`'s own `BillingSubscription.ExtraAdministratorsPurchased` is the fact this page needs to show
  that split honestly, and it does not exist on `main` yet. Do not start this item's backend half before
  `25-41` merges.
- **Found**: 2026-09-09, the author reading their own billing page
- **Verified**: 2026-09-12 — `25-41` is merged (`ago-chat#257`); `BillingSubscription.
  ExtraAdministratorsPurchased` is real (`Ago.Chat.Domain/BillingSubscription.cs:121`). Confirmed
  `BillingStatusDto`'s current wire shape exactly as the item describes — `Ago.Chat.Application/
  UseCases/GetBillingStatus/GetBillingStatus.cs:21`: `record BillingStatusDto(string Tier, int
  SeatLimit, int SeatsUsed, BillingSubscriptionSummaryDto? LatestSubscription)` — no Administrator
  fields at all. The blocker this item names is cleared; its premise still holds.

## What is actually true

**This item was filed as a console-only fix and it is not one — confirmed by reading the actual
backend, 2026-09-10.** `Ago.Chat.Application.UseCases.GetBillingStatus.GetBillingStatusHandler` (the
handler `BillingPage.tsx` actually calls) returns exactly `{ Tier, SeatLimit, SeatsUsed,
LatestSubscription }` — `Tier` is the raw enum string, `SeatsUsed` is one undifferentiated count of
every operator holding a seat (`IOperatorRepository.CountHeldSeatsAsync`), and there is no
Administrator count, no free-allowance-vs-purchased split, and no seat-range/price text anywhere on
this DTO. Every distinction this item asks the console to *show* has to exist on the wire first — this
is a two-repository item, `ago-chat` before `ago-console`, not a console-only one.

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

- **The backend half, first** (`ago-chat`, blocked on `25-41` landing): extend `BillingStatusDto` with
  what the console side actually needs — the Administrator seat count and limit (from `Site.AdminLimit`,
  already real since `25-25`) alongside the existing Operator `SeatsUsed`/`SeatLimit`, and
  `BillingSubscription.ExtraAdministratorsPurchased` (`25-41`) so the free-vs-paid-beyond-it split has
  a real number to show. Whether the tier display *name* is mapped server-side or client-side is an
  open, cheap call — either is fine, but decide and say which. Whatever answers the stale seat-range
  copy (`ago-business 0012`'s own figures, or `25-43`'s price catalog if that is the more honest
  source for a price range specifically) also goes on this DTO rather than staying a hand-typed
  console string — the same "sourced, not retyped" rule `25-20`'s price-list screen already follows.
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

- **Don't start the backend half before `25-41` merges.** Both touch `Site.cs`/`BillingSubscription.cs`
  in the same repository; building against `25-41`'s own still-unmerged worktree state would mean
  rebasing onto a moving target, and the whole reason this item needs `25-41` at all is a field
  (`ExtraAdministratorsPurchased`) that does not exist until it lands.
- **Do not build the ЮKassa call.** This item's whole point is the UI catching up to the grid; wiring a
  real purchase is explicitly `23-86`'s item, already scoped and larger. A stub button that visibly
  does nothing is the correct shape here, not a half-wired payment call.
- **Do not guess the current price range copy.** Read it from `ago-business 0012` (or whatever the
  backend's own configuration already encodes) and say where the number came from — CLAUDE.md's
  "measure or stay silent" applies to a price exactly as it does to a benchmark.

## Done when

- [ ] `BillingStatusDto` carries what the console side needs — Administrator seat count and limit
      alongside the existing Operator pair, and the purchased-extra-Administrators fact — sourced from
      `Site.AdminLimit`/`25-41`'s own state, never retyped or recomputed client-side.
- [ ] The tier renders as "Соло" / "Business" (localized), not a raw enum value.
- [ ] Operator and Administrator seat counts are shown separately, each against its own limit, with the
      free-allowance/paid-beyond-it distinction named rather than collapsed.
- [ ] The stale seat-range copy is replaced with the current grid's own numbers, sourced rather than
      retyped.
- [ ] The seat-count field becomes a read-only summary plus an add-seats stepper and an `[Добавить]`
      button that is a visible stub — no payment call, no state change that looks like a completed
      purchase.
