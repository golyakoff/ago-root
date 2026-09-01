# A third-party integrator can actually use Calendar's public booking API

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-10-public-booking-widget-requires-a-verified-phone.md` (done) — the phone-
  verification guarantee this item's own caller needs. `20-01`/`20-03` — the endpoint itself, already
  built and already correctly gated; this item does not touch its guarantees.

## Why this exists

`20-10` built a real, tested phone-verification gate for `Ago.Calendar.Api`'s public
`POST /calendars/{id}/events/{id}/book` endpoint, on the assumption that `ago-widget` was the caller.
That assumption was checked and found wrong, in `20-10`'s own file: `20-07` (done 2026-08-29) deleted
`ago-widget`'s entire direct HTTP client to Calendar — every booking, on every channel, now runs through
the conversation, as chat messages. Nothing in `ago-widget` calls, or will ever call, Calendar's public
API directly.

So the endpoint's real caller, decided by the author when this gap was found (2026-09-01), is a
**tenant's own custom-built page** — a shop that wants a booking form on its own site, integrated
directly against `Ago.Calendar.Api`, with no AGO Chat widget in the loop at all. `adr/0027` already
frames Calendar as independently bookable, not merely independently deployable; this item is what makes
that framing actually usable by someone who is not this codebase's own author.

## What already exists, checked before scoping the rest

- The endpoint itself, its phone-verification gate (`20-10`), its origin/CORS policy
  (`TenantOriginCorsPolicyProvider`, per-tenant allowed origins the same shape `ago-chat`'s own per-site
  CORS uses), and its rate limiting are all real and already tested. This item adds no new guarantee to
  the API surface itself.
- **No public API documentation exists for this endpoint at all** — not a README, not an OpenAPI spec,
  not a worked example. A third party today would have to read `BookingEndpoints.cs`,
  `PhoneVerificationEndpoints.cs` and their own request/response contracts directly from the source to
  integrate — which this codebase's own conventions never ask a customer to do (`api-design.md` covers
  the *shape* the API takes, not how an external caller discovers it).
- `20-10`'s own `FakePhoneVerificationSender` makes the whole flow — initiate, confirm, book — genuinely
  exercisable today without a real SMS gateway, which is exactly what a worked reference example needs
  to be runnable rather than aspirational.

## Scope

- A real, runnable reference: the exact request/response sequence a third-party integrator makes —
  register/discover the tenant's `publicKey` and allowed origins (however that already works, read the
  real provisioning flow rather than inventing a new one), list open slots, initiate phone verification,
  confirm it, book with the resulting proof token. Written so a developer who has never seen this
  codebase can follow it end to end against a real local cluster.
- `docs/conventions/api-design.md` gains whatever is missing to make this endpoint's own contract
  legible from outside this codebase — decide at implementation whether that is an OpenAPI/Swagger
  surface, a hand-written contract doc, or both; this codebase has no existing precedent for either, so
  state which was chosen and why.
- Origin/CORS behaviour verified from an actual third-party-shaped test: a request from an origin that
  is *not* the tenant's own configured `allowed_origins`, proving the rejection a real integrator would
  actually hit — if such a test does not already exist for this endpoint specifically (`20-06`'s own
  Done-when mentions a similar layer-2 check; confirm it covers this exact endpoint before writing a
  duplicate).
- Whatever polish the reference-walkthrough exposes as missing for a caller outside this codebase — a
  confusing error shape, an undocumented required header, a CORS preflight gotcha `20-06`'s own file
  already names once for a different endpoint. Named and fixed as found, not guessed at in advance.

## Out of scope

- Any new guarantee on the endpoint itself — `20-10`'s own gate, rate limits, and origin policy are
  correct and untouched.
- A real SMS/voice vendor account — `FakePhoneVerificationSender` stays the only sender; this item does
  not change that (`20-10`'s own file names the vendor question as the author's own decision, not
  blocked on this item).
- A tenant-facing self-service page inside `ago-calendar-console` for *generating* API credentials or
  managing third-party access — if that turns out to be needed, it is a different, larger item with its
  own authorization questions, not a documentation task.
- `ago-widget` — this item is explicitly not about the chat-embedded flow, which is `20-07`'s own,
  already-shipped, unrelated mechanism.

## Done when

- [ ] A developer with no prior knowledge of this codebase can follow the reference walkthrough and
      complete a real booking against a local cluster, using only what the walkthrough tells them —
      proven by actually having someone (or a fresh session with no other context) follow it cold.
- [ ] The endpoint's own request/response contract is discoverable without reading `.cs` files —
      whatever form was chosen in Scope, published somewhere a third party would actually find it.
- [ ] A request from an origin outside the tenant's own `allowed_origins` is rejected, proven by a test
      that specifically exercises `POST /calendars/{id}/events/{id}/book` and the phone-verification
      endpoints from a foreign origin — not inferred from a different endpoint's own coverage.
- [ ] Any real integration friction the walkthrough surfaced is named in this file's own Outcome section,
      whether or not it was fixed in the same change.

## Open questions

- Whether the reference walkthrough belongs in `ago-root`'s own `docs/` (this repository, alongside
  every other convention doc) or as a runnable example checked into `ago-calendar` itself (closer to the
  code it demonstrates, but a second place documentation can go stale against). Decide at
  implementation; either is defensible, but state which and why.
