# ЮKassa subscription checkout, webhook receiver, and idempotent tier activation

- **Stage**: 13
- **Status**: ready
- **Depends on**: `13-01-operator-invitations-and-seat-entitlement.md` (the `sites.tier`/`seat_limit`
  columns this item is the first real writer of, once a payment actually succeeds)

## Goal

A site's owner can start a real subscription: they choose a seat count, get redirected to ЮKassa's own
hosted checkout (card data never reaches `Ago.Chat.Api`, already decided in `roadmap.md`'s own text), pay
with a real card, and — once ЮKassa's webhook confirms the payment, never the redirect alone, per
`roadmap.md`'s explicit wording — the site's `tier`/`seat_limit` update to match what was purchased, and
ЮKassa's own `payment_method_id` is stored so a future recurring charge (`13-03`, not this item) can be
made against it without asking for card details again. This item builds the *first successful payment*
path only: checkout-session creation, webhook receipt and verification, and idempotent activation. It
does not build what happens on a *second* (renewal) charge succeeding, failing, or being cancelled — see
`13-03`.

## Context to read first

`docs/adr/0024-webhook-signature-and-secret-lifecycle.md` in full — the direct style precedent named for
this item: HMAC-SHA256 over a canonical string, verify-don't-trust-the-payload, is the same primitive this
codebase already built once outbound (`6-03`/`6-05`). Read its Decision section closely for what to *keep*
(the canonical-string-plus-signature shape, the "shown once" ethos for generated secrets) and what to
correctly *not* copy for this item's different situation — see Scope's ADR bullet below for the concrete
difference (a reversible per-tenant ciphertext column vs. a fixed application config value). `docs/architecture/messaging.md`'s
"Delivery guarantees and idempotency" section — "every consumer records `message_id` in the `inbox` table
inside the same transaction as its work... handlers must be safe to run twice regardless of the inbox" is
the exact discipline this item's webhook handler needs, realized as a plain HTTP-triggered database
transaction rather than a broker consumer (see Scope — this item never touches RabbitMQ; ЮKassa calls
`Ago.Chat.Api` directly over HTTP, there is no broker hop for an inbound third-party webhook). `docs/backlog/6-05-webhook-dispatcher.md`'s
idempotency ledger — `(message_id, endpoint_id)` as the natural key for *outbound* delivery, where many
endpoints exist per event. This item's inbound case has exactly one "endpoint" (ЮKassa itself calls us),
so the natural key is different — see Scope. `docs/architecture/caching.md` — confirms this item's own
webhook-driven write is never behind a cache; it is itself the write ЮKassa's own delivery guarantees
already make durable (idempotency ledger plus at-least-once retry from ЮKassa's side), not something this
item needs to additionally protect with caching semantics. `docs/architecture/repositories.md`'s "no
secrets, ever" section, and `adr/0022`'s existing `infra-credentials`/`docker/.env` mechanism (already used
for `Auth:SigningKey`, `Webhooks:SecretEncryptionKey`) — the pattern this item's new ЮKassa credentials
follow, not a new mechanism.

## Scope

- **An ADR** (`adr/0025`, mirroring `adr/0024`'s structure and rigor for the *inbound* mirror image):
  - **Signature scheme**: ЮKassa's own `Webhook-Signature` header, HMAC-SHA256 over
    `{HTTP method}|{URL}|{request body}` joined by `|`, keyed by a `webhook_key` obtained from the
    merchant dashboard's notification settings. State plainly this is fixed by ЮKassa's own API — unlike
    `adr/0024`, which chose a scheme from real alternatives, this item has exactly one scheme to implement
    correctly, verified against real ЮKassa test-mode notifications (see Done when), not designed from
    scratch.
  - **Credential shape, and why it is *not* `adr/0024`'s ciphertext-column shape**: this item needs two
    ЮKassa values — a Shop ID + Secret Key (used by `Ago.Chat.Api` to *call* ЮKassa's API and create a
    checkout session) and a Webhook Key (used to *verify* inbound notifications). Both are **our own
    fixed application credentials**, not a value stored per-tenant that a dispatcher must later reproduce
    for many different receivers — `adr/0024`'s reversible-AES-encryption decision was driven specifically
    by "the dispatcher must reproduce this exact secret for many different tenants' endpoints," which does
    not apply here at all. These two values are ordinary application configuration
    (`Billing:YooKassa:ShopId`/`SecretKey`/`WebhookKey`), read directly from `infra-credentials`/
    `docker/.env` the same way `Auth:Keycloak:Authority` already is — never written to Postgres, no cipher
    needed, no new column. State this contrast explicitly in the ADR so a reader of both ADRs sees the
    reasoning, not just the outcome, and does not conclude "HMAC verification always means a ciphertext
    column" from `adr/0024` alone.
  - `.Validate().ValidateOnStart()` on the binding options class, matching `adr/0024`'s
    `Webhooks:SecretEncryptionKey` precedent: a missing/malformed credential fails host startup, never the
    first real checkout attempt.
- **Pricing mechanism, deliberately minimal, no invented number anywhere**: one configured monthly
  price-per-seat (`Billing:PricePerSeatRub` — placeholder key name only; **this item ships no default
  value in code**, `.ValidateOnStart()` requires it be supplied by whoever deploys, the same "fails to
  start rather than silently using a wrong number" discipline as the credential above, deliberately
  stricter than this codebase's usual "hardcode a sane unmeasured default" precedent for a non-monetary
  parameter — `CLAUDE.md`'s "do not invent numbers... presented as decided when they are not" applies with
  more force to a figure that charges a real card than to a rate-limit bucket size). Total charge =
  `seats_requested × PricePerSeatRub`. State explicitly: this item does **not** implement per-band
  discount pricing (a cheaper effective rate at Growth volumes) — nothing in the business context given to
  whoever planned this stage names one, and a flat linear rate is the simplest mechanism consistent with
  "priced by operator-seat count." If ago-business's real pricing turns out to have volume tiers, that is
  a config-shape change for whoever discovers it, not scope this item anticipates speculatively.
  Named, not silently assumed: the given tier bands overlap at the boundary as literally stated
  ("Starter (2-10 seats), Growth (10-100 seats)") — this item reads that as Starter = 2-9, Growth = 10-100
  (non-overlapping), the natural non-overlapping reading of a loosely-worded band list, not a genuine
  product-policy question of the kind this stage blocks liberally on elsewhere. State this reading plainly
  in the code's own band-lookup logic so the author can correct it if the intended boundary differs.
- **Application/HTTP**: `POST /api/v1/sites/{siteId}/billing/checkout-sessions` (gated by
  `RequireOperatorIdentity` + `Permission.SiteConfigure` — a billing/tier change is a site-configuration
  action, the same permission `5-08` already granted `"Admin"` for exactly this kind of decision), input:
  desired seat count. Validates the count against the band table, computes the charge, calls ЮKassa's
  Payments API to create a payment with `confirmation.type = redirect` and `save_payment_method = true`
  (the flag that lets ЮKassa later charge this card again without the customer present, per the given
  "recurring/autopay" fact), records a `pending` local row (see next bullet), and returns ЮKassa's
  `confirmation_url` for the client to redirect to.
- **New table** (`Stage13AddBillingSubscriptions`, or fold into `sites` if implementation finds that
  simpler — state which once written and why): tracks at minimum `site_id`, `yookassa_payment_id`,
  `requested_seats`, `status` (`pending|succeeded|failed`), `payment_method_id?` (populated once ЮKassa's
  webhook confirms success), `created_at`. This is the **pending intermediate state** `10-02`/`12-02`'s
  planning already anticipated as necessary given webhook delivery is not instant — a checkout-session
  creation and a webhook confirmation are two different moments, and `sites.tier`/`seat_limit` must not
  change until the second one actually happens.
- **Webhook receiver**: `POST /api/v1/billing/webhooks/yookassa` in `Ago.Chat.Api` (not `Ago.Chat.Webhooks`
  — state explicitly why: `adr/0013`'s three-host split exists to isolate *our own slow outbound calls to
  tenants* from the rest of the system; this is the opposite shape, an *inbound* call where ЮKassa is the
  one with latency to manage on their side, and our only obligation is to ack fast and never block, which
  an ordinary `Ago.Chat.Api` endpoint already does for every other inbound request). In one database
  transaction:
  1. Verify the `Webhook-Signature` header against the raw body; reject (`401`, no retry-worthy signal to
     ЮKassa beyond "this failed") on mismatch.
  2. **Idempotency ledger, keyed by `(yookassa_payment_id, event_type)`** — the natural key for this
     inbound case, adapted from `6-05`'s `(message_id, endpoint_id)` shape as the note anticipating this
     item already flagged: there is exactly one "sender" (ЮKassa itself), so the second half of the
     composite key is which *event* fired for a given payment (`payment.succeeded`,
     `payment.waiting_for_capture`, `payment.canceled` can all arrive for the same `payment_id`), not which
     endpoint received it. A duplicate `(payment_id, event_type)` pair is detected, skipped, and still
     acked `200` — messaging.md's "handlers must be safe to run twice regardless of the inbox" applied
     here as a plain transactional check, not a broker consumer.
  3. On a new `payment.succeeded` event: mark the local pending row `succeeded`, store
     `payment_method_id`, and — inside the **same** transaction — update `sites.tier`/`seat_limit` to the
     purchased band/count. One transaction, matching every other "a partial failure must not leave a
     half-applied state" reasoning already used elsewhere in this backlog (`10-02`).
  4. Respond `200` once the transaction commits — ЮKassa retries on anything else, matching the fact given
     for this item.
  - State explicitly what this item does with `payment.canceled`/a failed initial payment: the local
    pending row is marked `failed`; `sites.tier`/`seat_limit` are left untouched (they were never changed
    from free in the first place, since the pending row — not the site — held the in-flight state). No
    further lifecycle behaviour (retry prompts, notifying the site) is built here — that is UI/UX scope
    for `13-04`, or lifecycle scope for `13-03`, not this item.
  - If `SiteSettingsChanged` (`caching.md`'s documented invalidation event) already has a real producer by
    this point in the roadmap (state explicitly, once implementation checks — Stage 11's widget-config
    work may have been its first), this item's tier update publishes it too, so any node caching this
    site's config picks up the change; if it still has no producer, state that plainly rather than
    building a producer speculatively for an event this item does not otherwise need.
- **Real integration testing against ЮKassa's actual test mode** (a separate test Shop ID/keys via the
  merchant dashboard, per the fact already confirmed for this stage) — not a mocked `HttpClient`, matching
  this project's own "never mock the database/broker" discipline extended to a third-party API for the
  first time in this codebase. State in the test project's own setup how the test Shop ID/keys are sourced
  (environment variable, never committed — `repositories.md`).

## Out of scope

- Everything named in `13-03`: the recurring re-charge job that uses the stored `payment_method_id` for a
  second and subsequent billing cycle, and every policy question around a failed renewal, cancellation, or
  mid-cycle upgrade/downgrade. This item's own Done-when stops at "first payment succeeds, tier updates" —
  exactly what `roadmap.md`'s Stage 13 done-when literally asks for ("a real card can subscribe... to a
  paid tier"), not the ongoing subscription lifecycle.
- Downgrading a tier, or any UI for it — `13-04`, and transitively blocked behind `13-03`'s policy
  questions there (see that item).
- Per-band discount pricing — named above as a deliberate simplification, not silently dropped.
- Closing the multi-identity/multi-site loophole `13-01` already named as an accepted gap — unaffected by
  this item; a `payment_method_id` is stored per paying site here, which is the raw material a future item
  could use to detect reuse across sites, but nothing in this item's own scope does that correlation.
- A refund flow — nothing in `roadmap.md`'s Stage 13 done-when names one, and it raises its own policy
  questions (partial-period refund on cancellation?) that overlap `13-03`'s blocked territory; real,
  separate future work if ever wanted.

## Done when

- [ ] `adr/0025` written and accepted: signature scheme (fixed by ЮKassa, verified against real test-mode
      notifications), and the credential-shape reasoning contrasted explicitly with `adr/0024`.
- [ ] `Ago.Chat.Integration.Tests`, against ЮKassa's real test mode: a checkout session is created for a
      real seat count, a real test card completes payment on ЮKassa's hosted page (or the equivalent
      test-mode success flow ЮKassa's docs describe for automated testing — state exactly which mechanism
      was used once implemented), the real webhook notification arrives, is verified, and
      `sites.tier`/`seat_limit` reflect the purchase — verified by querying the row directly, not asserting
      the `200`.
- [ ] A webhook with an invalid/missing signature is rejected `401` and never touches `sites` — proven with
      a real malformed request, not asserted from the verification code alone.
- [ ] A redelivered webhook notification (the same `payment_id`/`event_type` sent twice — forced directly
      against the endpoint, since ЮKassa's own test mode may not trivially redeliver on demand) does not
      double-apply the tier change — proven by asserting `sites.tier`/`seat_limit` after two deliveries
      equal the state after one.
- [ ] A `payment.canceled` test-mode event leaves `sites.tier`/`seat_limit` unchanged from free.
- [ ] `docs/architecture/data-model.md` gains the new billing-pending table (or the `sites` columns it
      populates, whichever shape implementation chooses) and a short note on the `(payment_id, event_type)`
      idempotency key.
- [ ] `docs/architecture/messaging.md` or `docs/architecture/resilience.md` gains a short note that this is
      the first *inbound*, HTTP-triggered (not broker-consumed) idempotency ledger in the codebase, stating
      explicitly why it does not need the broker.

## Open questions

None — the mechanism follows directly from ЮKassa's documented webhook contract, `adr/0024`'s established
style for this class of signature verification, and `messaging.md`'s existing idempotency discipline
adapted to an HTTP-triggered case. The pricing-formula and tier-band-boundary simplifications above are
stated as explicit, correctable readings of ambiguous or incomplete given data — not genuine unresolved
product-policy questions of the kind `13-03`/`13-05` block on — because a flat per-seat rate and a
non-overlapping band reading are the simplest constructions consistent with everything actually given, and
nothing about them is a real business decision requiring the author's judgment the way a grace-period or
dunning policy does.
