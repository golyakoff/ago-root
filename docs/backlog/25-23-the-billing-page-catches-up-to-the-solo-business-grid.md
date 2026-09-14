# 25-23 · The billing page catches up to the Solo/Business grid

- **Stage**: 25
- **Status**: done — backend half already merged (`ago-chat#267`, `d1114e6`, 2026-09-12, by a session
  this window had no record of — found and confirmed by rebasing a leftover worktree onto `origin/main`
  and seeing it collapse to zero diff). Console half independently re-verified by the managing session
  before merging: `npm run typecheck`/`lint` clean, full `npx vitest run` — 1414/1414, matching the
  worker's own count exactly. The deviation from the item's own "visible stub" instruction is reviewed
  and accepted — ЮKassa is genuinely live, a stub would have deleted shipped capability — and the two
  gaps it surfaced are filed as their own items: `25-95` (seat decrease no longer reachable), `25-96`
  (Administrator seats still unpurchasable from the console).
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

## What the console half found, 2026-09-14 — the "no payment integration yet" premise is stale

The Scope bullet below asked for the `[Добавить]` button to be **a visible stub**, because "there is
no ЮKassa integration yet (`23-86` is that gap)". Re-checked against `ago-chat`'s own `main` while
building the console half, **that premise no longer holds, on three counts**:

- **ЮKassa is real and shipped** — `Ago.Chat.Infrastructure.YooKassa`, `IYooKassaPaymentsClient`, a
  signature-verified webhook (`ProcessYooKassaWebhookHandler`), a stored payment method on
  `BillingSubscription`.
- **`23-86` is closed as done** (`ago-chat#233`/`#279`, `ago-deploy#200`) and was never about
  payments: its own "What is actually true" section says it is the *option-to-entitlement mapping*,
  a missing noun in the domain, not a missing payment call.
- **This very screen has been calling the real purchase path since `13-02`/`13-03`** —
  `createCheckoutSession` (ЮKassa hosted checkout) and `changeSubscriptionSeats` (prorated,
  charge-then-apply). `25-41` added a third, `POST .../billing/subscriptions/{id}/administrators`.

So a deliberate no-op button would have **deleted shipped, working capability** and left a control
that lies in the other direction — it looks like it buys and does nothing. The control's *shape*
changed exactly as asked (read-only current count, add-this-many spinner, one `[Добавить]` button);
its *wiring* stayed on the two endpoints the screen already called, now given `seatLimit +
seatsToAdd` instead of a typed absolute. `billingAddSeatsStartsCheckout` says out loud that pressing
it opens ЮKassa when the site has no active subscription. **No payment flow was built** — nothing
new was wired; one call site changed what it computes.

**Two consequences that need the author's eye**, both recorded rather than quietly absorbed:

- **A self-service seat *decrease* is no longer reachable from this screen.** The old absolute field
  let an owner type a smaller number and schedule a downgrade; an add-only stepper cannot express
  that. `ChangeSubscriptionSeatsHandler`'s downgrade branch is untouched and still works, a
  downgrade scheduled elsewhere still renders through `billingPendingDowngradeBody`, and cancelling
  outright is still offered — but the *control* is gone. Filed as `25-95`.
- **Administrator slots are shown but cannot be bought here.** `25-41`'s purchase endpoint exists and
  is unused by the console. Wiring it is a second promise (rule 15), so it was deliberately left out.
  Filed as `25-96`.

### A real defect this uncovered, fixed in the same change

The console's own `billingValidation.ts` declared `MAX_SEATS = 100` and claimed to "mirror"
`SubscriptionTierBands.MaxSeats`. **That constant is `5`.** So the console advertised "От 2 до 100
мест" *and locally accepted* every seat count up to 100, all of which `TryResolveTier` refuses —
the server rejected them after a round trip. The hand-copied constants are deleted rather than
corrected, and `isValidSeatCount` takes the bounds the server sent; correcting `100` to `5` would
have fixed today's drift and rebuilt the exact mechanism that produced it.

## Done when

- [x] `BillingStatusDto` carries what the console side needs — Administrator seat count and limit
      alongside the existing Operator pair, and the purchased-extra-Administrators fact — sourced from
      `Site.AdminLimit`/`25-41`'s own state, never retyped or recomputed client-side.
      **Landed in `ago-chat` `d1114e6`** — five additive fields (`TierDisplayName`, `AdminLimit`,
      `AdminsUsed`, `ExtraAdministratorsPurchased`, `SeatPricing`, `AdminExtraPriceRub`), the four
      original ones unmoved. `AdminsUsed` reads `IOperatorRoleRepository.GetNonRemovedHolderIdsAsync`
      (not its row-locking sibling — a display read holds no lock);
      `ExtraAdministratorsPurchased` is read off the subscription, never re-derived from
      `AdminLimit`. Proven by `GetBillingStatusHandlerIntegrationTests` against real Postgres plus
      four Application-level tests.
- [x] The tier renders as "Соло" / "Business" (localized), not a raw enum value.
      **Rendered as "Solo" / "Business"**, from the server's own `TierDisplayName` — mapped
      server-side so one `tier == "free"` predicate lives in one place. Not transliterated to
      "Соло": `ago-business 0012`'s own heading writes the name in Latin inside a Russian sentence
      ("*Solo бесплатен, Business с базой…*"), and these are tariff brand names, not copy. Proven by
      `BillingPage.test.tsx` — the Subscription panel contains "Solo" and never the raw `"free"`.
- [x] Operator and Administrator seat counts are shown separately, each against its own limit, with the
      free-allowance/paid-beyond-it distinction named rather than collapsed.
      Two titled panels. Operators name `freeSeatsIncluded` apart from the purchasable band;
      Administrators name `adminLimit - extraAdministratorsPurchased` ("включено в тариф") apart
      from `extraAdministratorsPurchased` ("докуплено") — the second is `25-41`'s persisted field,
      and the first is exact because `Site.ActivateSubscription` builds `AdminLimit` as precisely
      `ResolveAdminLimit(tier) + ExtraAdministratorsPurchased`. Proven by two tests asserting against
      each panel separately, so neither can be satisfied by the other's text.
- [x] The stale seat-range copy is replaced with the current grid's own numbers, sourced rather than
      retyped.
      `billingSeatCountFieldDescription` ("От 2 до 100 мест…") is **deleted**, not reworded. The
      range, the base price, the seats the base covers, the marginal price and the billing period all
      come off `seatPricing` — `SubscriptionTierBands` plus `25-43`'s published price versions, the
      identical two sources `GetPricingForOwnerHandler` reads for `25-20`'s owner screen. Proven by a
      test that changes the server's band to 3–9 and sees the screen follow it.
- [~] The seat-count field becomes a read-only summary plus an add-seats stepper and an `[Добавить]`
      button that is a visible stub — no payment call, no state change that looks like a completed
      purchase.
      **Shape delivered; the stub deliberately not.** Read-only "Мест сейчас", a 1-or-more spinner
      capped at what is actually purchasable, one `[Добавить]` button, and the field is gone — but
      the button calls the real, already-shipped purchase path rather than doing nothing, for the
      reason in the section above. It still never claims a completed purchase: a checkout redirects
      to ЮKassa and the seats appear only when the webhook confirms, exactly as before. **This box is
      the one thing in this item the author should look at and may want reversed** — it is one
      `onSubmit` branch.
