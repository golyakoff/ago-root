# 26-301 — Android «Тариф и оплата» v2 screen design (approved model + native YooKassa SDK)

**Status:** design (this document is the deliverable; no code in this item)
**Author trigger (2026-09-29):** the author approved the console billing **v2** model (the interactive
mockup: current plan / immediate top-up / next-period composition / save-card two-states) and wants the
**same model on Android**. The app's «Тариф и оплата» is a `PlaceholderDestinationScreen` today
(`26-289` §"Where we are today"), so this is greenfield. Payment must be **native via the YooKassa
Android SDK** (`Checkout.createTokenizeIntent` / `createConfirmationIntent`), not a web-redirect
hand-off (`26-289` §5 recommendation).

This designs the Compose screen, the end-to-end native SDK payment flow, what it consumes from the v2
backend contract, and the slices to file. It follows the Android-parity memory ("the app must let
tenant-admins do everything the console does") — the same three questions the console answers, on a
phone.

---

## 0. Premises checked against source (2026-09-29)

- **The billing surface is a placeholder.** `MoreScreen.kt`'s Администрирование → «Тариф и оплата»
  (`ADMINISTRATION_BILLING_ROW_ID`) still opens `PlaceholderDestinationScreen`; there is **no** billing
  domain port (`core/domain/.../billing` does not exist), **no** Ktor billing adapter, **no** ViewModel.
  Confirmed by grep: the only `billing`/`subscription`/`tier` hits in `:core:domain`/`:app` are
  incidental (conversation ordering, thread text). Greenfield, exactly as the brief states.
- **The app's design tokens ARE the mockup's tokens.** `ui/theme/Color.kt` defines
  `AgoBrandDark = 0xFF6052FF`, `AgoPaperDark = 0xFF13121C`, `AgoSurfaceDark = 0xFF22202F`,
  `AgoInkSoftDark = 0xFFB0B0BF`, `AgoLiveDark`, `AgoDanger*`, `AgoLavender*` — byte-identical to the
  mockup's `--ago-*` custom properties (both derive from `tokens.css`). So the model maps 1:1 to the
  app's existing design system; nothing new in the palette is required.
- **The SDK integration shape is settled** by `26-289`: tokenization (integration shape (a)) →
  `paymentToken` → backend `POST …/billing/checkout-sessions/token` (`26-291`) → optional
  `createConfirmationIntent(confirmationUrl)` for 3DS/SberPay → poll `GET …/billing/status` to the
  grant. Confirmation + grant are unchanged (`adr/0190`).
- **The `clientApplicationKey` is client build config, not a server secret** (`26-289` §3): a
  `BuildConfig` field fed by a Gradle property, test value for debug and live for release — the exact
  shape `app/build.gradle.kts` already uses for `AGO_API_BASE_URL` and the four `AGO_FCM_*` fields.
- **The activity-result plumbing already exists.** `MainActivity` registers three
  `registerForActivityResult(StartActivityForResult())` launchers (AppAuth sign-in, sign-out, battery)
  and drives them from ViewModel `SharedFlow<Intent>` collectors under `repeatOnLifecycle` — the exact
  pattern the SDK's `Intent` needs.

### The one false premise, adapted

**`26-299` is not yet filed as a doc.** The brief calls it "the v2 backend contract being built (in
flight)" and lists its fields (per-kind channel list, `hasStoredPaymentMethod`, `nextChargeRub`, a
`SetNextPeriodComposition` command, a proration-preview endpoint). No `docs/backlog/26-299-*.md`
exists, and grep finds `26-299`/`SetNextPeriodComposition`/`nextChargeRub` nowhere in `docs/`. What
**does** exist is `26-290` (the console three-card redesign), whose slices 2–4 add exactly these fields
to `BillingStatusDto` (`channels` block, `channelAddOnPriceRub`, `nextChargeRub`, the preview endpoint,
pay-early), and `26-289` (the token endpoint `26-291`). The v2 mockup is the evolution of `26-290`'s
three cards into an interactive composition model.

**Adaptation:** this document specifies the contract the Android screen *requires* (§3) as the union of
26-290's added fields, 26-289's token endpoint, and the mockup's composition semantics, and treats
"26-299" as the umbrella name for that backend v2 contract wherever the brief used it. The Android
slices (§5) are written to **consume** that contract and are gated on it landing; where a field's exact
name is the backend's to choose, §3 says what the screen needs it to mean, not that a specific JSON key
already exists. If 26-299 is filed with different names, only the DTO in `:core:network` changes — the
ViewModel and Compose consume the domain types this doc defines, on the correct side of the dependency
rule.

### Relationship to the already-filed `26-289` slices

`26-289` §6 filed three numbers: **26-291** (`ago-chat` token endpoint), **26-292** (`ago-android`
basic in-app SDK screen), **26-293** (`ago-android`+docs SDK-key wiring). This v2 design is richer than
26-292's "replace the placeholder with a real screen" scope. Reconciliation (§5): **26-291 and 26-293
stand unchanged** and are reused; **26-292's screen scope is superseded by this v2 design** and should
be closed as won't-do with the reason "replaced by the 26-301 v2 screen slices" (rule 14), its work
re-filed as the screen slices below. This keeps one promise per ticket (rule 15) — 26-292 promised a
*basic* screen against a *basic* contract; the v2 model is a different, larger promise.

---

## 1. Compose layout — the desktop two-column mockup reflowed to one phone column

The mockup is a desktop `max-width: 68rem` page: Card C (Текущий тариф) full-width on top, then a
`.grid-2` of Card A (Докупить сейчас) | Card B (Следующий период) side by side. On a phone there is one
column, so the three sections **stack vertically** in a `LazyColumn` (the same scroll container
`MoreScreen`, `ChannelConnectScreen` bodies, and every settings screen already use), inside the standard
`Surface(color = background)` → `Scaffold(topBar = TopAppBar{ title=«Тариф и оплата», nav = Back })` →
`Box(padding)` shell (`ChannelConnectScreen`'s exact frame — a drill-in, back arrow, no
`AccountAvatarAction`).

**Stacking order** (top to bottom), each an `ElevatedCard`/`OutlinedCard` (`MaterialTheme.colorScheme`
maps to the same `--ago-surface`/`--ago-line` tokens):

1. **Текущий тариф (Card C).** Read-at-a-glance. The mockup's `.facts` definition grid (label + value
   pairs) becomes a `Column` of label/value `Row`s, not a multi-column `dl` — a phone is too narrow for
   the `repeat(auto-fill, minmax(9rem))` grid. Header row: title + a status `Badge` (Активна / Бесплатный).
   Fields: Тариф, Операторы («N из M · до K включено»), Администраторы (same shape), Каналы («Сайт» +
   enabled kinds), Текущее списание (`recurring`/мес, or «Бесплатно»), Оплачено до (date in the viewer's
   zone), Способ оплаты («Карта ·· 4242» / «не сохраняется · ЮKassa» / «не привязана»). Scheduled
   changes (cancel-requested / pending-downgrade) fold in as small inline notes, not separate cards
   (26-290 §1).

2. **Докупить сейчас (Card A).** The immediate, prorated, per-kind top-up section. Order preserved from
   the mockup:
   - **Save-card `subcard`** — a `Row` with a `Checkbox` («Сохранять способ оплаты для автосписаний») +
     a hint line whose text switches on the two states (on: instant charge from stored card; off: each
     payment through ЮKassa, no autorenew). This is the SDK `savePaymentMethod` toggle (§2).
   - **Buy rows** — Операторы (quantity stepper, capped at headroom to `MAX_SEATS`=5, or a disabled
     "достигнут максимум" row), Администраторы (quantity stepper), then a **Каналы** group label and one
     row per offered paid kind (**Telegram, MAX** only — the author's final decision in the mockup JS;
     Сайт is the included built-in, shown as «✓ включён в тариф»; a connected kind shows «✓ Подключён»
     disabled). Each buyable row's action button reads «Докупить за ₽X» / «Подключить за ₽X», with a
     « · ЮKassa» suffix when save-card is off, X being the prorated amount.
   - **Proration note** — «Оплата пропорционально остатку периода: осталось N из 30 дней (текущий
     неполный день оплачивается полностью)». The floor rule (`USED_DAYS` = complete days elapsed) is a
     **backend figure**, never recomputed on the client (§3, teaching-mode).
   - On Соло: the whole section collapses to the mockup's info-note («разовая докупка доступна на Бизнес;
     расширьте состав в блоке ниже»); save-card and buy rows hidden.

   On a phone, a quantity buy row is too wide for `[label | stepper | wide button]` in one line, so it
   becomes **two lines**: line 1 = name + unit-price sublabel + a compact stepper (`-` `N` `+`), line 2
   = the full-width «Докупить за ₽X» button. Channel rows are single-line (name + price + a trailing
   «Подключить» button that wraps to its own line when narrow).

3. **Следующий период (Card B).** The interactive composition → live total.
   - **Composition controls** — Операторы (stepper 2–5), Администраторы (stepper 1–5), a **Какие каналы
     продлевать** group with a `Switch` per offered kind (Telegram/MAX; Сайт «✓ включён»). Every change
     recomputes the total.
   - **Соло→Бизнес transition line** — the mockup's `.transition` panel, shown only when the current
     tier is Соло and the chosen composition exceeds Соло's included limits (drives the «Переход на
     тариф Бизнес — 490 ₽/мес» explainer).
   - **Breakdown** — база + доп. операторы + доп. администраторы + каналы, each a label/amount row.
   - **Total** — «Сумма следующего списания» + the value, and a delta vs. the current recurring
     («+₽X / −₽X к текущему») when on Бизнес.
   - **Notes** — the "changes take effect next period, no charge now, no refund on decrease" note;
     the autorenew-off warning when save-card is off on Бизнес.
   - **«Не продлевать»** — a `divider` + a danger `OutlinedButton` opening a confirm `AlertDialog`
     (the mockup's `alert()` placeholder → a real dialog, `ChannelConnectScreen`'s disconnect-confirm
     shape). Hidden on Соло.

   Because Card B is a live editor with its own "apply" semantics, its composition changes are **not**
   saved keystroke-by-keystroke. A trailing **«Сохранить состав»** button (not in the desktop mockup,
   which auto-applied) commits the whole composition via one `SetNextPeriodComposition` call (§3) — the
   phone equivalent of the desktop's implicit apply, and it makes the write explicit and idempotent.

**What is a bottom sheet vs. inline:** everything above is **inline** in the scroll column — the screen
is a form, not a hub, and bottom sheets would hide the live total the user is composing against. The
only modal surfaces are (a) the «Не продлевать» confirm `AlertDialog`, and (b) the **YooKassa SDK's own
full-screen payment UI**, which is not our composable at all — it is the SDK Activity launched by the
Intent (§2). We deliberately do **not** build a custom payment bottom sheet; the SDK owns that surface,
which is the whole point of the native-SDK decision.

---

## 2. The native SDK payment flow, end to end

The trigger is any «Докупить за ₽X» / «Подключить за ₽X» button in Card A. One flow serves all buyable
kinds; the only per-kind difference is which `PurchaseIntent` (dimension + quantity/kind) is sent to the
backend after tokenization.

```
BillingScreen (Compose)        BillingViewModel            MainActivity + launcher        YooKassa SDK            Ago.Chat.Api
   tap «Докупить за ₽X»
   → onBuy(intent) ───────────► startPurchase(intent)
                                 emit TokenizeRequest      collect →
                                 (PaymentParameters:       Checkout.createTokenizeIntent(ctx, params)
                                   clientApplicationKey,   ─────────────────────────────► SDK payment UI
                                   shopId, amount,                                          user picks card/SBP/SberPay
                                   savePaymentMethod=…)                                     enters data IN THE SDK
                                                           launcher result ◄──────────────  TokenizationResult
                                 onTokenized(result) ◄──── Checkout.createTokenizationResult(data)
                                 POST /billing/checkout-sessions/token ───────────────────────────────────────►
                                   { paymentToken, dimension, quantity|channelKind, savePaymentMethod }         26-291
                                 ◄─────────────────────────────────────────────────── { status, confirmationUrl? }
                        status==pending && confirmationUrl != null:
                                 emit ConfirmRequest       collect →
                                 (confirmationUrl,         Checkout.createConfirmationIntent(ctx, url, method)
                                  paymentMethodType)       ─────────────────────────────► SDK 3DS/SberPay UI
                                                           launcher result ◄──────────────  RESULT_OK (finished, NOT success)
                                 onConfirmed() ◄─────────
                        poll GET /billing/status every ~2s (bounded) ───────────────────────────────────────►
                                 until the grant shows (tier/seat/channel change lands)  ◄── webhook-driven grant (adr/0190)
                                 → refresh all three cards
```

**Piece-by-piece placement:**

- **`BillingViewModel` computes nothing about price.** The `amount` in `PaymentParameters` is the
  **backend-supplied prorated figure** (§3 preview), not a client multiplication — the same
  no-client-side-pricing discipline 26-290 §7 argues for the console, and CLAUDE.md rule 8 ("never
  cache/derive what a write decision depends on"). The ViewModel holds the current prorated amount per
  buyable row (from the preview read) and passes it straight into `PaymentParameters`.
- **The SDK Intent is launched from `MainActivity`, not the ViewModel.** A ViewModel must not hold an
  `Activity` or start an Activity-for-result (it outlives configuration changes; it has no `Activity`).
  So `BillingViewModel` exposes a `SharedFlow<PaymentLaunch>` (tokenize/confirm requests), `MainActivity`
  registers a `paymentLauncher = registerForActivityResult(StartActivityForResult())`, collects the flow
  under `repeatOnLifecycle(STARTED)`, launches the Intent, and feeds `result.data` back to
  `viewModel.onTokenized(...)` / `viewModel.onConfirmed(...)`. This is the **exact** shape
  `authorizationLauncher` + `viewModel.authorizationRequests` + `viewModel.onAuthorizationResult` already
  has for AppAuth (`MainActivity` lines 160–200). The billing screen is a drill-in inside the shell, so
  either MainActivity owns the launcher and the ViewModel is shared, or — cleaner — the launcher is
  created in the billing `Route` composable via `rememberLauncherForActivityResult`, keeping the SDK
  wiring local to the feature. **Recommendation:** `rememberLauncherForActivityResult` in the billing
  `Route`, because the SDK Intent is feature-local (unlike sign-in, which gates the whole app) and this
  avoids threading a billing concern through `MainActivity`. Note this as the layering decision the impl
  brief must make explicitly (§6).
- **`createTokenizationResult(data)` / a null result** — a null `result.data` (user dismissed the SDK
  sheet) is **not a failure**, rendered as a return to the idle screen, exactly as the AppAuth launcher
  treats a dismissed Custom Tab (`MainActivity` line 163 comment).
- **`RESULT_OK` from `createConfirmationIntent` means finished, not paid** (`26-289` §1). Success is
  confirmed only by the status poll landing the grant — never by the confirmation result. The ViewModel
  must not flip the UI to "purchased" on `RESULT_OK`; it starts the poll.
- **The poll** reuses the console's honest posture (`usePollUntilCheckoutSettled`, 26-290 §4): while the
  purchase is `Pending`, poll `GET …/billing/status` on a bounded interval (~2s, capped ~60s) until the
  new grant appears, then refresh. A timeout shows «оплата обрабатывается — обновите позже», never a
  false "done".
- **The save-card checkbox → `savePaymentMethod`.** Checked → `PaymentParameters(savePaymentMethod =
  SavePaymentMethod.ON)`; the backend `POST …/token` also carries `savePaymentMethod: true` so the
  server stores `payment_method_id` for future auto-charges (the mockup's "instant top-up from stored
  card" state). Unchecked → `OFF`, each purchase is a fresh SDK tokenization, no stored method (the
  mockup's «каждая покупка — отдельная оплата в ЮKassa» state).

**Method coverage:** the SDK's `PaymentParameters.paymentMethodTypes` gates which methods appear
(bank card, SBP, SberPay — Google Pay excluded, `26-289` §4). The confirmation step's
`paymentMethodType` (from `TokenizationResult`) tells `createConfirmationIntent` which flavour of
in-app confirmation to run.

---

## 3. What the screen consumes from the v2 backend contract (26-299 + 26-291)

The screen is a pure renderer of backend figures. It requires the following, each behind a domain port
in `:core:domain/.../billing` implemented by a Ktor adapter in `:core:network` (the ChannelConnectionApi
split). Names below are what the screen needs the field to *mean*; the backend owns the exact JSON key.

**A. Status read — `GET /api/v1/sites/{siteId}/billing/status` → `BillingStatusDto`** (extends 26-290
slices 1–2 + the mockup's needs):

| Consumed by the screen | Field it needs | Already on the wire? |
|---|---|---|
| Card C tier name + status badge | `tierDisplayName`, `latestSubscription.status` | yes (26-290 §1) |
| Card C operators / admins («N из M · до K включено») | `seatsUsed`/`seatLimit`/`seatPricing.freeSeatsIncluded`; `adminsUsed`/`adminLimit`/`extraAdministratorsPurchased` | yes (26-290 §1) |
| Card C + Card A/B channel rows (per-kind) | **`channels`: per-kind list** (kind + connected + `currentPeriodEnd`) — the mockup needs to know *which* kinds are connected, not just a count | **NEW** (26-290 slice 2 adds `channels` count/kinds) |
| Card C «Способ оплаты», Card A save-card default, Card B autorenew warning | **`hasStoredPaymentMethod`** (bool) + a masked card label if present | **NEW** (mockup's `card` / save-card two-states) |
| Card C «Текущее списание» | recurring total (derivable from seat+admin+channel prices) or an explicit `currentRecurringRub` | derivable; explicit preferred |
| Card B «Сумма следующего списания» | **`nextChargeRub`** (recurring, overage-excluded) | **NEW** (26-290 slice 2) |
| Card A prices + prorate note | `seatPricing.baseSeatPriceRub`/`pricePerExtraSeatRub`, `adminExtraPriceRub`, **`channelAddOnPriceRub`**, `currentPeriodEnd`, and the period floor figures (**complete days elapsed / period days**) | partly; `channelAddOnPriceRub` NEW (26-290 slice 2) |
| Card A/B caps | `MAX_SEATS`, base seats (3), base admins (2) — the bands | on the wire as `seatPricing` bands |

**B. Prorated purchase preview — `GET …/billing/purchase-preview?dimension=&quantity=`** (26-290 slice
3): returns `{ proratedAmountRub, includedUntil }` for a given buyable. The screen shows this figure on
each «Докупить за ₽X» button and passes it as the SDK `amount`. **This is the one figure the client must
never compute itself** — the seat formula is banded Domain logic and the admin delta needs the stored
old price version (26-290 §7). Each stepper change re-requests the preview.

**C. Token payment — `POST …/billing/checkout-sessions/token`** (26-291): body
`{ paymentToken, dimension, quantity | channelKind, savePaymentMethod }`, returns
`{ status, confirmationUrl? }`. The immediate top-up path (§2).

**D. Next-period composition set — `SetNextPeriodComposition`** (26-299): the Card B «Сохранить состав»
write — `POST …/billing/next-period` with `{ operators, administrators, channels[] }`, returning the
recomputed `nextChargeRub`. Maps to 26-290's scheduled-downgrade/seat-change handlers unified into one
"set the whole next-period composition" command. The mockup composes the *whole* target state and the
backend diffs it against the current — cleaner than N separate add/remove calls.

**E. Cancel / «Не продлевать»** — `POST …/billing/cancel` (cancel-at-period-end), already implied by
26-290's cancel control; the screen sets `cancelRequested` and Card C shows the inline "cancels on
<date>" note.

**Pay-early** (26-290 slice 4) is **out of scope for this screen's first cut** — the mockup has no
pay-early control; it appears on the console's Card 3 as its own slice and can reach Android later as an
additive button. Noted so the impl doesn't try to build it.

---

## 4. Teaching-mode — Compose-state, ports, and where the SDK lives

- **A billing port in `:core:domain`, a Ktor adapter in `:core:network` — the dependency rule, again.**
  `BillingApi` (status, preview, token-payment, set-next-period, cancel) is declared in
  `:core:domain/.../billing` and implemented as `KtorBillingApi(client, apiBaseUrl, activeSite)` in
  `:core:network`, provided in `AppModule` exactly like `provideChannelConnectionApi`. The alternative —
  a ViewModel holding `HttpClient` — makes it untestable without a network and drags ЮKassa/HTTP
  vocabulary above the adapter, the violation `ChannelConnectionApi`'s own doc comment names. The
  **SDK's** types (`PaymentParameters`, `TokenizationResult`) are a different matter: they are an Android
  UI dependency, so they live in `:app` (the ViewModel/Route), **not** in `:core:domain` — the port
  carries only our own `paymentToken: String` and result types, never a `TokenizationResult`, so the
  domain layer stays ignorant of the SDK exactly as it is ignorant of Ktor.
- **The SDK key is client config, injected as a value, not a secret.** `clientApplicationKey` and
  `shopId` reach the ViewModel/Route as a small `YooKassaConfig` provided in `AppModule` from
  `BuildConfig.AGO_YOOKASSA_CLIENT_APPLICATION_KEY` / `AGO_YOOKASSA_SHOP_ID` — the identical shape
  `OidcConfig` is built from `BuildConfig` in `provideOidcConfig`. It never enters `:core:domain` (it is
  neither a domain concept nor a server credential) and never enters `Ago.Chat.*` at all (`26-289` §3).
- **Compose state: one `StateFlow<BillingUiState>`, sealed by load state, the ChannelConnectViewModel
  shape.** `Loading` / `Failed(reason)` / `Loaded(status, cardA, cardB, purchase)`, mutated through
  `MutableStateFlow.update`, network calls on `@IoDispatcher` via `withContext`. Card B's live
  composition is `remember`ed editor state derived from the loaded status, recomputing the displayed
  total locally **for display only** (fast feedback) while the authoritative `nextChargeRub` comes from
  the backend on save — the same "optimistic display, server is truth" split the poll enforces for
  purchases. A write in flight is a no-op guard read off the current state (ChannelConnectViewModel's
  "second tap finds the guard already true").
- **The Intent launcher belongs in the UI layer** (`Route` via `rememberLauncherForActivityResult`, or
  `MainActivity`), never the ViewModel — an Activity-result contract needs an `Activity`/`Context` the
  ViewModel must not hold. The ViewModel emits *requests* (a `SharedFlow<PaymentLaunch>`), the UI turns
  them into launched Intents and feeds results back — the AppAuth pattern, reused.

---

## 5. Slice plan (rule 15 — one promise that lands green)

The backend v2 contract (26-299) and the token endpoint (26-291) land first — the app slices consume
them and are gated on them. Reconcile with the already-filed 26-289 numbers as noted in §0.

**Slice A — SDK dependency + key wiring + the tokenize→token-payment plumbing.**
*Promise: the app can take a single native SDK payment for one buyable dimension against the test shop,
and it grants.*
- Add `ru.yoomoney.sdk.kassa.payments:yookassa-android-sdk` to `gradle/libs.versions.toml` +
  `app/build.gradle.kts` (Maven Central — already in `settings.gradle.kts` repositories, no new repo
  needed, unlike RuStore's nexus).
- Add `AGO_YOOKASSA_CLIENT_APPLICATION_KEY` + `AGO_YOOKASSA_SHOP_ID` `buildConfigField`s (test default
  for debug, live via Gradle property for release CI) and a `YooKassaConfig` provided in `AppModule` —
  **this is 26-293's work; reuse 26-293, do not re-file it.** Record the client key in
  `ago-chat`/`ago-root` `secrets.md` as a client key that ships in the APK (26-289 §3).
- Declare `BillingApi` in `:core:domain` + `KtorBillingApi` in `:core:network` with the **status +
  preview + token-payment** methods; provide it in `AppModule`.
- The `BillingViewModel` tokenize→token→confirm→poll state machine + the `Route` launcher wiring, driven
  from a minimal harness (not the full screen yet).
- **Done-when:** a test-mode card purchase for one dimension, launched from a minimal screen, posts the
  token to 26-291, and the status poll shows the grant — verified on the test shop. compileDebug**AndroidTest**Kotlin
  green; any new strings in `values/` + `values-en/` (Android-strings memory).
- *Depends on:* 26-291 (endpoint) merged; the preview + status fields it reads (26-299). *This is the
  re-scoped, larger replacement for 26-292's payment half.*

**Slice B — the full v2 «Тариф и оплата» screen on the contract.**
*Promise: the three-section v2 screen renders current plan, immediate per-kind top-up, and next-period
composition with a live total, and every buy/compose/cancel action works end to end.*
- The `BillingScreen` composable: Card C (current plan), Card A (докупить — save-card two-states, seat/
  admin steppers, per-kind Telegram/MAX channel rows, prorated buttons wired to Slice A's payment
  machine), Card B (next-period composition, live total + delta, Соло→Бизнес transition, «Сохранить
  состав» → `SetNextPeriodComposition`, «Не продлевать» confirm dialog).
- Extend `BillingApi`/`KtorBillingApi` with `setNextPeriodComposition` + `cancel`.
- Replace the `MoreScreen` `ADMINISTRATION_BILLING_ROW_ID` placeholder branch with `BillingRoute`,
  gated on `site:configure` the way the channel rows are.
- **Done-when:** on the test shop, a top-up (with and without save-card), a next-period composition
  change, and a cancel each land and re-render; `compileDebugAndroidTestKotlin` green; a
  ViewModel/render test covers the three sections + the poll; all strings as resources in both languages.
- *Depends on:* Slice A + the full 26-299 contract (per-kind channels, `hasStoredPaymentMethod`,
  `nextChargeRub`, preview, `SetNextPeriodComposition`).

**Numbers to file** (ago-root queue — the manager assigns the numbers; per the one-worker-per-cross-repo
memory, Slice A's SDK+key+plumbing is one `ago-android`(+docs) worker, Slice B one `ago-android` worker):
- `ago-android: YooKassa SDK dep + key wiring + native token-payment plumbing` (Slice A; folds 26-293)
- `ago-android: v2 «Тариф и оплата» screen on the billing contract` (Slice B)
- and: close **26-292** as won't-do — "superseded by the 26-301 v2 screen slices" (§0).

**Splitting note (rule 15):** A and B are two promises — A is "a native payment works and grants" (no
full UI), B is "the v2 screen works" (no new payment mechanics). A lands green with a minimal harness;
B is not left red waiting for anything once A and 26-299 are in. This is a real seam, not "first breaks,
second fixes."

---

## 6. Open questions for the author

1. **26-299 scope confirmation.** This design assumes the v2 backend contract (per-kind `channels`,
   `hasStoredPaymentMethod`, `nextChargeRub`, `SetNextPeriodComposition`, purchase-preview) is being
   built as the brief states. Is 26-299 filed/agreed with these fields, or should its shape be settled
   first? The Android slices are gated on it either way.
2. **`SetNextPeriodComposition` vs. per-dimension writes.** The mockup composes a whole target next-period
   state and would send it as one command. 26-290's console slices instead reuse per-dimension handlers
   (seats / administrators / channels / cancel). Should the backend expose **one** composition-set
   command (this design's D) so the app and console converge, or should Android call the same
   per-dimension endpoints the console uses? A single command matches the mockup's mental model and is
   idempotent; confirm which the backend will offer.
3. **Launcher placement.** §2 recommends `rememberLauncherForActivityResult` in the billing `Route`
   (feature-local SDK wiring) over adding a launcher to `MainActivity`. Any preference? (Both work; this
   only affects where the ~10 lines live.)
4. **26-292 disposition.** Confirm 26-292 (the earlier "basic in-app SDK screen") is closed as won't-do
   / superseded by these v2 slices, rather than kept as an interim.
5. **`shopId` on the client.** The SDK's `PaymentParameters` needs `shopId` alongside `clientApplicationKey`.
   Is the shopId acceptable as a public `BuildConfig` field in the APK (it identifies the merchant but
   cannot charge, same class as the client key), or is there a reason to keep it server-only and have the
   app read it from an endpoint first?

---

## 7. Sources

- The approved v2 mockup (design source of truth for model + copy): the interactive
  `billing-v2-mockup.html` (three sections; `CFG` pricing model — Бизнес база 490 covers 3 ops + 2
  admins + Сайт, +200/op, +1000/admin, +100/paid channel kind, Telegram+MAX only; floor proration on
  complete days elapsed; save-card two-states; Соло→Бизнес transition).
- `docs/backlog/26-289-yookassa-android-sdk.md` — the SDK decision (tokenization flow,
  `clientApplicationKey` vs. server SecretKey, RuStore/no-Google-Play gate, the 26-291/292/293 slices).
- `docs/backlog/26-290-console-billing-redesign.md` — the console three-case model and the
  `BillingStatusDto` additions (channels, channelAddOnPriceRub, nextChargeRub), the preview endpoint,
  pay-early — the backend fields this screen consumes; §6 there already reserves the Android screen as
  its own item.
- `ago-android` (primary checkout, fetched + ff'd 2026-09-29): `shell/MoreScreen.kt` (billing
  placeholder), `channels/ChannelConnectionApi`/`KtorChannelConnectionApi`/`ChannelConnectViewModel`/
  `ChannelConnectScreen` (the port/adapter/VM/screen pattern reused), `core/network/AgoHttpClient.kt`,
  `di/AppModule.kt` (`provideChannelConnectionApi`, `provideOidcConfig` from `BuildConfig`),
  `app/build.gradle.kts` (`buildConfigField` incl. the FCM test/live pattern), `settings.gradle.kts`
  (Maven Central), `MainActivity.kt` (`registerForActivityResult` + `SharedFlow<Intent>` collectors),
  `ui/theme/Color.kt` (tokens identical to the mockup), `res/values` (ru) + `res/values-en` (en).
- MEMORY: Android full console parity; Android strings must be resources; compileDebugAndroidTestKotlin
  gate on Composable signature change; push transport (RuStore + FCM); curated avatar categories (n/a).
