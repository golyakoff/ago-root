# 26-289 — YooKassa Android SDK: do we use it, and how, for in-app billing

- **Kind**: research / recommendation (no code in this item)
- **Date**: 2026-09-29
- **Stage**: 13 (billing) × 26 (Android app)
- **Author intent (2026-09-29)**: "we will use the YooKassa Android SDK in the app."

This document settles *whether* and *how* the Android app takes payment. It is a decision brief, not an
implementation. The slice plan at the end names the items to file if we build it.

## Where we are today (the fact the decision hangs on)

The **web-redirect checkout already works end to end** and is verified on the test shop:
`CreateCheckoutSessionHandler` → `IYooKassaPaymentsClient.CreatePaymentAsync` (a payment with
`confirmation.type = redirect`, `save_payment_method = true`) → ЮKassa's hosted page → test card →
console-configured HTTP notification → `ProcessYooKassaWebhookHandler` re-queries the payment by id and
grants on the authoritative `status = succeeded` / `paid = true` (`adr/0190`). The recurring-charge and
seat-change paths reuse the saved `payment_method_id` (`ChargeStoredPaymentMethodAsync`).

Server-side ЮKassa credentials (**ShopId + SecretKey**) live in the `ago-billing-yookassa` Kubernetes
Secret, read by `Ago.Chat.Api`/`Worker`/`Webhooks` as `Billing__YooKassa__ShopId` / `__SecretKey`
(`ago-deploy/k8s/base/api.yaml`, `worker.yaml`, `webhooks.yaml`; `26-287`). There is no webhook signing
secret any more (`adr/0190` removed `WebhookKey`).

On the **Android** side there is *nothing yet*: «Тариф и оплата» (`ADMINISTRATION_BILLING_ROW_ID` in
`app/src/main/kotlin/ago/chat/android/shell/MoreScreen.kt`) still opens a `PlaceholderDestinationScreen`.
So the choice is not "SDK vs. an existing app web-redirect" — it is **what to build first for the app**:
an in-app SDK flow, or an app screen that hands off to the already-working hosted page.

## 1. What the YooKassa Android SDK actually provides

The SDK (`ru.yoomoney.sdk.kassa.payments:yookassa-android-sdk`, current **8.4.0**, released 2026-01-26;
`minSdk 21` / Android 5.0, the docs page states Android 7+) ships a **ready-made in-app payment UI** —
the payment form and everything around it — so the app never renders card fields itself.

- **Payment methods**: bank card, **SBP** (Система быстрых платежей), **SberPay**, YooMoney wallet, and
  Google Pay. (Google Pay is irrelevant to us — see §4 — and card/SBP/SberPay are the methods a Russian
  buyer actually uses.)
- **Two integration shapes**:
  - **(a) Tokenization — the one we'd use.** The app calls `Checkout.createTokenizeIntent()` with
    `PaymentParameters` (`clientApplicationKey`, `shopId`, `amount`, `title`, `subtitle`). The user picks
    a method and enters data **inside the SDK's UI**; the SDK exchanges it for a **one-time payment token**
    and returns a `TokenizationResult` carrying `paymentToken` + `paymentMethodType`. The token is
    **single-use and expires in 1 hour**. Your backend then creates the real payment via
    `POST /payments` with the token in the **`payment_token`** parameter — the SDK never charges anything
    itself.
  - **(b) SDK-driven confirmation for 3-D Secure / SberPay.** If `POST /payments` comes back `pending`
    with a `confirmation` object (`type: redirect`, `confirmation_url`), the app passes that
    `confirmation_url` (and the `paymentMethodType`) to `Checkout.createConfirmationIntent()` and the SDK
    runs the 3DS/SberPay step in-app. `RESULT_OK` means the flow finished — **not** that the payment
    succeeded; success is confirmed only by the API (webhook or re-query).
- **Card tokenization / PCI**: card data is collected and tokenized inside the SDK, so card bytes never
  touch our app code or our backend — the same "bytes never pass through us" property our attachment
  storage already has, applied to card data.

The crucial architectural fact: **even with the SDK, the merchant backend still creates the payment and
still confirms it by webhook or re-query.** YooKassa's own docs say so explicitly: after `POST /payments`
you "wait for a webhook notification from YooKassa, or periodically send requests to obtain payment
information." That is *exactly* the path we already built.

## 2. How it maps onto OUR architecture

The SDK's token flow slots into what exists with **one new backend endpoint** and no change to the
confirmation/grant machinery:

```
App (SDK)                         Ago.Chat.Api                         ЮKassa
  createTokenizeIntent()
  → user pays in SDK UI
  → paymentToken  ───────────────►  POST /billing/checkout-sessions/token
                                     (new: CreateTokenPaymentHandler)
                                     → IYooKassaPaymentsClient
                                        .CreatePaymentWithTokenAsync(token, amount, …)
                                        → POST /payments {payment_token}  ──────►
                                     ← {id, status, confirmation_url?}     ◄──────
                                     → save BillingSubscription(Pending, paymentId)
  ◄── confirmation_url (if pending) ─┘
  createConfirmationIntent(url)
  → 3DS/SberPay in SDK
                                                          payment.succeeded webhook
                                     POST /billing/webhooks/yookassa  ◄────────────
                                     → ProcessYooKassaWebhookHandler
                                        re-query GetPaymentAsync(id) → grant  (adr/0190, UNCHANGED)
```

**What is genuinely new:**

1. **One Application port method** on the existing `IYooKassaPaymentsClient`:
   `CreatePaymentWithTokenAsync(CreatePaymentWithTokenRequest, ct)` where the request carries the
   `paymentToken`, the computed `amount`, the description, and an idempotence key — the direct sibling of
   the existing `CreatePaymentRequest`, differing only in that ЮKassa's `POST /payments` body carries
   `payment_token` instead of a `confirmation: { type: redirect, return_url }`. Implemented only in
   `Ago.Chat.Infrastructure.YooKassa.YooKassaPaymentsApiClient`, using the **same ShopId + SecretKey Basic
   auth** the create/charge/re-query calls already use.
2. **One new API endpoint** — `POST /api/v1/sites/{siteId}/billing/checkout-sessions/token` — a near-clone
   of `CreateCheckoutSessionHandler`: same `Permission.SiteConfigure` gate, same
   `SubscriptionTierBands` seat validation, same fresh `IPriceCatalogRepository` price read (CLAUDE.md
   rule 8), same `BillingSubscription.Create(Pending)` write. It differs in two lines: it takes a
   `paymentToken` from the request and calls `CreatePaymentWithTokenAsync` instead of
   `CreatePaymentAsync`, and it returns the payment's `confirmation_url` **only when** ЮKassa answers
   `pending` (so the app knows whether a 3DS step is needed). The response DTO becomes
   `{ status, confirmationUrl? }` rather than the redirect-only `{ confirmationUrl }`.
3. **The app surface**: the SDK dependency, a billing screen that computes the amount (or reads it from a
   quote endpoint), runs `createTokenizeIntent`, posts the token, and — if a `confirmationUrl` comes back —
   runs `createConfirmationIntent`; then it polls `GET .../billing/status` (which already exists) until the
   webhook-driven grant lands.

**What does NOT change — and this is the whole point:** `ProcessYooKassaWebhookHandler`, the re-query
guarantee, the IP allowlist, the idempotency ledger, `BillingWebhookApplier`, the outbox grant, the
recurring-charge job, the console web-redirect flow. The SDK adds a *second front door to payment
creation*; the confirmation-and-grant back half is identical because ЮKassa confirms token payments the
same way it confirms redirect payments. That is why the earlier decision to build the redirect first, and
defer the SDK, cost us nothing structurally — the SDK is additive.

**Note — a token payment could reuse the existing endpoint instead of a new one.** We *could* branch inside
`CreateCheckoutSessionHandler` on "token present → token payment, else redirect." Rejected: it would make
one handler carry two payment shapes and two response shapes (redirect-only vs. status+optional-url), and
its integration tests already assert the redirect contract. A sibling handler keeps each to one promise
(CLAUDE.md rule 15) and shares everything real through the port and `SubscriptionTierBands`, which is where
the logic that must not diverge actually lives.

## 3. The mobile SDK key ("Ключ для мобильного SDK")

The console's "Подключить SDK" surfaces a **`clientApplicationKey`** — YooKassa's own name for the *key for
client applications*, issued in the merchant profile under **Интеграция → Ключи API** once the mobile SDK
is enabled for the shop. It is a **distinct credential from the API Secret Key**:

| | API Secret Key | Mobile SDK key (`clientApplicationKey`) |
|---|---|---|
| Used by | our **backend** (`Ago.Chat.Api`), Basic auth on `POST /payments`, `GET /payments/{id}` | the **app**, passed in `PaymentParameters` to the SDK |
| Ships in | Kubernetes Secret `ago-billing-yookassa` (server-only) | the **APK** — it is a client-side value by design |
| Can it charge? | yes — it authenticates real payment creation | no — it only lets the SDK **tokenize**; the token still has to be redeemed by the Secret-Key-authenticated backend call |
| Test vs live | test/live shop pair | its own test/live value, matching the shop |

So the SDK key is **meant** to be embedded in a distributed client, precisely because it cannot move money
on its own — the one-time token it produces is worthless until our backend redeems it with the Secret Key
inside `POST /payments`. This is the standard client-key/secret-key split, and it means:

- **The SDK key must NOT go in `ago-billing-yookassa`** (that Secret is server-side ShopId+SecretKey). It
  is app configuration, not a server secret.
- It should be a **build-time config value** in `ago-android` (a `BuildConfig` field fed from Gradle
  properties / the release-build CI, test value for debug, live value for release) — the same shape the
  app already uses for other environment-specific constants. It is not "a secret to protect" in the
  `secrets.md` sense (it protects nothing on its own), but for hygiene it should still come from the build
  environment rather than a hard-coded literal, and it belongs recorded in `secrets.md` §F-adjacent as a
  *client key that ships in the app* so a reader is not surprised to find it in the APK.
- **Test mode**: the SDK supports a test mode for integration checkout; use the test shop's SDK key +
  test cards, and only the release build carries the live SDK key.

## 4. Distribution / policy — settled

**AGO ships via RuStore + direct APK, not Google Play** (see the RuStore/FCM push memory and the RuStore
signing binding in `secrets.md` §C). Google Play's Payments policy — the rule that in-app purchases of
digital goods must go through Google Play Billing, which is the usual blocker for third-party payment SDKs —
**does not apply to us**, because we are not on Google Play. RuStore imposes no equivalent
Play-Billing-only mandate; third-party payment SDKs (YooKassa among them) are the normal way Russian apps
take money on RuStore. **The usual blocker for a third-party payment SDK does not exist here.**

**The one caveat, stated so a future reader hits it deliberately:** if AGO Chat is ever published to Google
Play, this must be revisited. Even there the ground shifted in 2026 (the Epic settlement now permits
external/alternative billing in some markets, with a fee), and a B2B SaaS operator subscription is a
weaker fit for "in-app digital goods" than a consumer game currency — but none of that is a decision to
pre-make now. Today: **not gated. Build the SDK if the UX justifies it.**

## 5. Recommendation

**Build the in-app SDK tokenization flow for the Android launch — it is the right call, and it is cheap
because the hard half already exists.**

The reasoning, weighed honestly:

- **For the SDK (native UX).** Paying is the single most trust-sensitive moment in a B2B purchase. A
  browser hand-off from a native app to a hosted page — leaving the app, an external Custom Tab, coming
  back and hoping the return deep-link fires — is exactly where a paying customer hesitates. The SDK keeps
  card entry, SBP and SberPay **inside the app**, with the platform's own payment sheet. For an app whose
  whole thesis is "full console parity, do everything without the console" (the Android-parity memory),
  routing the *payment* out to a web page is the one place that thesis visibly breaks.
- **The cost is small and bounded**, because confirmation + grant are untouched. The net new work is one
  port method, one endpoint (a near-clone), the SDK dependency, and the client-key wiring. There is no new
  webhook, no new grant path, no new idempotency story — `adr/0190` already covers the token payment
  identically.
- **Against the SDK (real, but not decisive).** A new third-party dependency to track and update; the SDK
  pulls transitive UI dependencies (bounded, but not zero APK weight); per-method testing (card + SBP +
  SberPay + 3DS) is more surface than "open a URL." These are maintenance costs, not blockers.
- **The web-redirect stays as the fallback**, and costs nothing extra to keep: it is what the console uses,
  and it is the natural degradation if the SDK ever refuses a method. So "build the SDK" is not "bet
  everything on the SDK" — it is "make the SDK the app's primary path, keep the redirect as the safety
  net."

Given the SDK key gate is already visible in the console, the author has already stated the intent, the
distribution policy does not block it, and the expensive half is done — **the trade-off favours the SDK
clearly, not marginally.** The only reason to *not* do it for launch would be raw calendar time; if the
launch date (clients ~2-3 weeks, commercial-intent memory) is at risk, ship the app billing screen as a
**web-redirect hand-off first** (a few hours: a screen + a Custom Tab to the existing hosted checkout +
the existing status poll) and land the SDK as a fast follow — the redirect screen is throwaway-cheap and
de-risks the date without blocking the SDK.

## 6. Slice plan (items to file)

If the recommendation is accepted, file these. One promise each (CLAUDE.md rule 15); the backend lands
first because the app slice depends on the endpoint contract, and per the one-worker-per-cross-repo-task
memory the backend endpoint + its Infrastructure adapter belong to **one** worker.

- **26-291 — `ago-chat`: token-payment endpoint behind the payments-client port.**
  Add `IYooKassaPaymentsClient.CreatePaymentWithTokenAsync` (`payment_token` body, same ShopId/SecretKey
  Basic auth) + `YooKassaPaymentsApiClient` impl; add `CreateTokenPaymentHandler` +
  `POST /api/v1/sites/{siteId}/billing/checkout-sessions/token` returning `{ status, confirmationUrl? }`;
  reuse `SubscriptionTierBands`, the fresh price read, and the `BillingSubscription(Pending)` write.
  **Done-when**: an integration test posts a (test-mode) token, a `BillingSubscription` row is created
  `Pending`, and the existing webhook path grants on re-query — no change to `ProcessYooKassaWebhookHandler`.
  *Not a migration* (`billing_subscriptions` already has every column this needs).
- **26-292 — `ago-android`: in-app SDK tokenization on the billing screen.**
  Add the `yookassa-android-sdk` dependency; replace the «Тариф и оплата» placeholder with a real screen
  that runs `createTokenizeIntent`, posts the token to 26-291's endpoint, runs `createConfirmationIntent`
  when a `confirmationUrl` returns, then polls `GET .../billing/status` to the grant. Strings as resources,
  both languages (Android-strings memory). **Done-when**: a test-mode card purchase in the app grants the
  tier, verified on the test shop.
- **26-293 — `ago-android` + `ago-deploy`/docs: mobile SDK key wiring + test/live.**
  Feed `clientApplicationKey` as a `BuildConfig` field from the build environment (test value for debug,
  live for release CI); record it in `secrets.md` as a client key that ships in the app (distinct from the
  server `ago-billing-yookassa` Secret). **Done-when**: debug builds tokenize against the test shop and
  release builds against live, with no key literal in source. *(Could fold into 26-292; kept separate
  because it touches build/CI + docs, a different promise from the screen itself.)*

(If the interim redirect-first fallback is taken instead, that is a separate small item — an app screen +
Custom Tab to the existing hosted checkout + status poll — and the SDK items above follow it unchanged.)

## Teaching-mode: the Clean-Architecture placement

- **The token→payment call is a port method, not a new abstraction.** `CreatePaymentWithTokenAsync` goes on
  the existing `IYooKassaPaymentsClient` in `Application/Abstractions`, implemented only in
  `Infrastructure.YooKassa`. The dependency rule forbids Application knowing ЮKassa's JSON or that
  `payment_token` is even a field — the alternative, letting the handler build the `POST /payments` body
  itself, would drag provider vocabulary into Application and break the same
  `NoProviderVocabulary_AppearsAboveInfrastructure` rule the channel ports are held to. The endpoint
  mirrors `CreateCheckoutSession` precisely because both are the *same use case* (create a pending payment,
  save the subscription) reaching the *same port* two ways.
- **The SDK key is client config, not server config.** It never enters `Ago.Chat.*` at all — no options
  class, no Secret, no `ValidateOnStart`. It lives in the app's build configuration because the app is the
  only thing that authenticates with it. The contrast with the server ShopId/SecretKey (a real
  server-side credential in `ago-billing-yookassa`) is the teaching point: *who holds and presents the
  credential* decides where it lives, exactly as `adr/0071`'s credential-shape reasoning already argued for
  the server side.

## Sources

- YooKassa Android SDK — GitHub README: <https://github.com/yoomoney/yookassa-android-sdk> and
  <https://github.com/yoomoney/yookassa-android-sdk/blob/master/README.md>
- Mobile SDKs: processing payments (token flow):
  <https://yookassa.ru/developers/payment-acceptance/integration-scenarios/mobile-sdks/payments-with-tokens>
- Using Android SDK (clientApplicationKey, test mode):
  <https://yookassa.ru/developers/payment-acceptance/integration-scenarios/mobile-sdks/android-sdk>
- Create-payment API (`payment_token`): <https://yookassa.ru/developers/api#create_payment>
- Maven artifact / version 8.4.0: <https://mvnrepository.com/artifact/ru.yoomoney.sdk.kassa.payments/yookassa-android-sdk>
  and <https://central.sonatype.com/artifact/ru.yoomoney.sdk.kassa.payments/yookassa-android-sdk>
- Google Play 2026 payments policy / Epic settlement (the caveat only, does not apply to RuStore+APK):
  <https://support.google.com/googleplay/android-developer/answer/10281818> ,
  <https://www.coda.co/blog/epic-v-google-policy-update-2026/>
- Internal: `docs/adr/0190-*`, `docs/adr/0071-*`, `docs/architecture/secrets.md`,
  `ago-chat` `CreateCheckoutSessionHandler` / `IYooKassaPaymentsClient` / `BillingEndpoints`,
  `ago-deploy/k8s/base/api.yaml` (`ago-billing-yookassa`), `ago-android` `MoreScreen.kt` (billing placeholder).
