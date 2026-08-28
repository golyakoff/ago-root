# Operator invitations and seat-count entitlement enforcement

- **Stage**: 13
- **Status**: done — merged `ago-chat#109`/`ago-root#235` (2026-08-28)
- **Depends on**: `10-02-site-and-operator-registration.md` (the `Site`/`Operator`/`Role`/`operator_roles`
  shape this item extends, and the exact gap this item fills — see Goal), `12-02-cross-tenant-operations-read-api.md`
  (its `tier` field — literal `"free"` today, deliberately shaped so a real column could replace it without
  a breaking response change — is the placeholder this item turns into a real column)

## Goal

Two things land together, deliberately, because the second is meaningless without the first: (1) a real
way for an existing operator to add a second, third, ... operator to their own site — `10-02`'s own
Out of scope named this exact gap ("Inviting additional operators to an already-registered site... a
real invite flow is new scope no roadmap stage names yet. Flagged here for whoever plans it next, not
built speculatively as a side effect of this item") and nothing since has built it; and (2) `sites`
gaining a real `tier`/`seat_limit`, enforced at the one point in the codebase that can ever change how
many operators a site has. `roadmap.md`'s Stage 13 wording — "seat count at minimum... wired into
whatever currently creates operators" — reads as if such a wiring point already exists. It does not:
`10-02` creates exactly one operator, atomically, as part of site creation, and nothing else in the
shipped system can ever add a second. A seat-count check with no second call site to enforce it against
would be unfalsifiable — untestable except by asserting the SQL looks right, which this project's own
testing discipline (`testing-guide`, and every "verified live, not asserted" bar in the backlog read
while planning this) rejects. So this item builds the minimal invite mechanism first, and the
entitlement check is enforced at its one real write path — operator invite redemption — not bolted onto
`10-02`'s registration flow, which already has its own hard cap of exactly one operator by construction
and needs no change.

After this item: an operator holding `Permission.SiteManageOperators` (`5-08`'s `"Admin"` role — this is
its first real write-path caller; `authorization.md` already noted "no handler anywhere uses it beyond
the admin console's read-only view") generates a single-use invite for their site, naming which of the
site's two built-in roles (`"Operator"` or `"Admin"`) the invitee receives. A person completing
Keycloak's registration or login flow (`10-01`) and holding a `RequireKeycloakIdentity`-eligible token
with no existing `operators` row anywhere can redeem that invite once, becoming a real operator of that
site — but only if the site's live operator count is still under its `seat_limit` at the moment of
redemption, checked inside the same transaction that creates the row, from Postgres, never from a cache
(`CLAUDE.md` rule 8, `architecture/caching.md`).

## Context to read first

`docs/backlog/10-02-site-and-operator-registration.md` in full — the exact `Site`/two-`Role`/`Operator`/
two-`operator_roles` shape and the one-transaction reasoning this item's redemption handler reuses
structurally, and its own Out of scope section naming the invite gap this item closes. `docs/backlog/10-01-self-registration-identity-flow.md`
— the `RequireKeycloakIdentity` policy this item's redemption endpoint reuses verbatim (the invitee has
no operator row yet, by definition, so `RequireOperatorIdentity` cannot gate this route), and its own
"no email-sending/deliverability setup... beyond enabling Keycloak's built-in Verify Email" deferral —
the precedent this item follows for *not* building an email-delivery system either (see Scope).
`docs/architecture/data-model.md`'s `operators`/`active_chats` shadow-property section — read closely for
the *contrast* this item draws, not the pattern it copies: `active_chats` uses a denormalized counter
with an atomic `UPDATE ... WHERE ... < capacity` because assignment is a high-frequency, contended path
where a per-row lock would itself become the bottleneck. Operator invitation is the opposite — rare,
low-contention, at most a handful of calls ever per site — so this item locks the `sites` row directly
(`SELECT ... FOR UPDATE`) and counts real `operators` rows inside that lock, rather than adding a second
denormalized counter that would need to be kept in sync with no symmetric decrement path existing yet
(see Scope). `docs/architecture/caching.md` in full — "never cache what a write decision depends on" is
this item's central constraint; the seat-count check is a compare-and-set read, structurally identical
in kind to the capacity check `caching.md` already names as the canonical example. `docs/adr/0016-rbac-authorization-model.md`
and `docs/architecture/authorization.md`'s "Admin/supervisor role" section — `Permission.SiteManageOperators`
already exists and is already granted to `"Admin"`; this item is its first real caller, not a new
permission. `docs/adr/0024-webhook-signature-and-secret-lifecycle.md`'s Decision section, specifically the
hash-vs-reversible-encryption reasoning — read for the *inverse* case this item needs: an invite code is a
bearer credential this system only ever needs to *verify* on redemption, never reproduce afterward (unlike
a webhook secret, which the dispatcher must decrypt back to plaintext to sign a request) — so a one-way
hash is the right primitive here, the same reasoning `adr/0024` used to *reject* hashing for its own very
different case, applied correctly to this one instead.

## Scope

- **Migration** (`Stage13AddSiteTierAndSeatLimit`): `sites.tier` (`text`, not null, default `'free'`) and
  `sites.seat_limit` (`integer`, not null, default `1`). Both additive and reversible. This item does
  **not** decide how `tier`/`seat_limit` get set to anything other than the free-tier default — that is
  `13-02`'s job, once a real payment exists to drive it. State plainly here: nothing in this item's own
  scope changes a site's tier away from `'free'`, so this migration ships with every existing and newly
  registered site simply carrying the free-tier default until `13-02` lands.
- **New table** (`Stage13AddOperatorInvites`): `operator_invites` — `id` (uuid v7), `site_id`, `role_id`
  (FK to that site's own `roles` row — `"Operator"` or `"Admin"`, matching `adr/0016`'s tenant-local role
  scoping), `code_hash` (the raw invite code is generated with the same `RandomNumberGenerator`-based
  approach `adr/0024`'s `IWebhookSecretGenerator` already established for a different bearer value in this
  codebase, shown exactly once in the generation endpoint's response and never again — reuse that ADR's
  entropy/generation reasoning, not its storage reasoning, per the Context note above: this value is
  hashed, not reversibly encrypted, because redemption only ever needs to *compare*, never reproduce),
  `created_by_operator_id`, `created_at`, `expires_at` (a real expiry — state the chosen window once
  implemented, a configurable default per this codebase's existing "hardcode a sane default, no per-site
  override yet" precedent, `caching.md`'s rate-limit bucket defaults), `redeemed_at?`,
  `redeemed_by_operator_id?`.
- **Application**: `CreateOperatorInviteHandler` (state final name once written) — input: inviter's
  `OperatorId`/`SiteId` (from claims), the target role. Checked against `Permission.SiteManageOperators`
  the same way every other permission check in this codebase already is (`IPermissionChecker`, no new
  mechanism). Returns the raw code once.
- **Application**: `RedeemOperatorInviteHandler` — input: the authenticated `sub` (from claims, never the
  body — same "identity comes from the validated token" rule `10-02` already established) and the invite
  code. In one transaction:
  1. Look up the invite by `code_hash`; reject (`404`/`410`, state which) if not found, expired, or
     already redeemed.
  2. **`SELECT id FROM sites WHERE id = @site_id FOR UPDATE`** — locks the site row so two concurrent
     redemptions against the same site's remaining capacity serialize on it, then
     `SELECT COUNT(*) FROM operators WHERE site_id = @site_id` inside that lock. If the count is already
     `>= seat_limit`, reject with a `402`/`409` RFC 7807 response naming the limit reached (state the
     exact status chosen and why once implemented — `402 Payment Required` reads as the more honest
     signal here than a generic `409`, since the actual remedy is "upgrade," not "retry"), and the invite
     is **not** consumed (an invite that fails only because the site is momentarily full should still be
     redeemable later if a seat opens up or the site upgrades — state this explicitly as the chosen
     behaviour, since the alternative — burning the invite on a capacity rejection — was considered and
     rejected as needlessly punishing the invitee for a site-level condition they do not control).
  3. If under limit: create the `Operator` row (`external_subject_id = sub`), insert `operator_roles` for
     the invite's `role_id`, mark the invite `redeemed_at`/`redeemed_by_operator_id`. One transaction,
     matching `10-02`'s own "a partial failure here must not leave a site with no roles or a token holder
     resolving to nothing" reasoning, applied to the smaller two-row shape this handler writes.
  - Reuse `10-02`'s existing "one registration per identity" constraint: a `sub` that already resolves to
    an `operators` row on *any* site (via the existing `OperatorIdentityClaimsTransformation`) is rejected
    `409` here too — this codebase's operator model has no concept of one identity holding rows on more
    than one site, and this item does not introduce one. State this plainly as a carried-over constraint,
    not a new decision.

    **Note added 2026-08-27, false as of `13-07-one-login-several-tenants.md`**: that item removes this
    exact constraint from `RegisterSiteHandler` so one identity can administer more than one `Site`. If
    `13-07` has landed by the time this item is built, this redemption handler must relax the same check
    the same way — reject only when the invite's own `site_id` already has an `Operator` row for this
    `sub` (a redundant redemption on that one site), not whenever the `sub` resolves to an `Operator` row
    *anywhere*. Read `13-07`'s own Scope and `adr/0068` before writing this handler.
- **HTTP**: `POST /api/v1/sites/{siteId}/operator-invites` (gated by `RequireOperatorIdentity` +
  `Permission.SiteManageOperators`, `201` with the raw code in the body, shown once, matching `adr/0024`'s
  "shown exactly once" precedent for a different bearer secret in this same codebase) and
  `POST /api/v1/operator-invites/redeem` (gated by `10-01`'s `RequireKeycloakIdentity` — never
  `RequireOperatorIdentity`, for the same reason `10-02`'s own bootstrap endpoint uses it: the caller has
  no `OperatorId` claim yet by definition).
- **How the code reaches the invitee**: out-of-band, copied and shared by the inviting admin however they
  choose (Slack, email client, anything) — no email-sending/deliverability system is built here, the same
  call `10-01` already made for its own "Verify Email" flow ("a custom sender or template is a separate
  concern this item does not scope"). State this explicitly rather than silently under-building against
  what a reviewer might expect an "invite" feature to include. **Note added 2026-08-25**: that chain of
  deferrals — this item pointing at `10-01`, `10-01` pointing at nobody — is now owned by
  `10-05-transactional-email-delivery.md`, which gives the deployment a real sending path. This item
  still builds no mail system of its own; if it later wants to send the code rather than have it copied,
  that is the first genuine in-app caller, and `10-05` names it as where the `IEmailSender` port question
  gets decided against a real use case instead of speculatively.
- **The multi-identity loophole, addressed explicitly, not silently assumed either way**: `12-02` already
  found that one real person can register more than one free-tier site by creating multiple Keycloak
  identities, since `10-02` enforces "one site per Keycloak identity," not "one site per person." This
  item's own seat-limit check operates **per-`site_id`**, exactly like every other tenant-scoped check in
  this codebase (`vision.md`'s "multi-tenant from day one"), and does nothing to correlate identities
  *across* sites — it could not, without either capturing operator email at registration (a real,
  separate change `12-02`'s own Out of scope already named as unbuilt) or a live call to Keycloak's Admin
  REST API from `Ago.Chat.Api` (a new class of secret `10-01`'s own ADR reasoning already avoided). **This
  item does not close that loophole. It stays a known, accepted gap** — named here explicitly rather than
  left to be rediscovered, per this stage's business context: the loophole lets one person operate more
  free sites than intended, which is a real but currently low-stakes leak (free seats are near-zero
  marginal cost by the business's own free/paid split criterion) rather than a revenue-losing one, since
  nothing about it lets a person avoid paying for a *paid*-tier seat count they are actually using. The
  natural future mechanism, if this is ever worth closing, is binding on a *verified payment method*
  rather than an identity — `13-02`'s ЮKassa integration will hold a `payment_method_id` per paying site,
  which could in principle be checked for reuse across sites the same way some SaaS products dedupe by
  card fingerprint — but that is speculative future work, not decided or built anywhere in this item or
  `13-02`.

## Two additions from `13-03`'s policy decision (2026-08-25)

`ago-business`'s `decisions/0006` settled what happens when an account holds more operators than paid
seats: nothing is deleted and nobody is chosen for the customer — the owner decides which operators
hold the seats, and everyone else keeps their account and data but cannot sign in. That needs two
things this item is the right home for, since seat counting already lives here:

- **Seat assignment**: a surface where the owner says who holds a seat, and the notion of an operator
  who has an account but no seat.
- **Operator removal**, which exists nowhere today. Needed independently of billing — people leave —
  so this is a dependency being named rather than scope being invented.

Both apply to the involuntary path too: an account dropping to Free after a failed payment lands in
exactly this state, and there the customer is by definition not responding.

## Out of scope

- Removing an operator, or decrementing seat usage — no such flow exists anywhere in this codebase today
  (`5-08` did not build one either). This item's seat-count check only ever counts up; a future
  "remove operator" item would need to reason about what happens to that operator's assigned
  conversations first, which is real, separate scope this item does not touch. Flagged here so whoever
  builds removal later does not have to rediscover that the count has no decrement path yet.
- Any UI for generating/redeeming an invite — `13-04`'s console billing surface may eventually grow one if
  the author wants it, but nothing in `roadmap.md`'s Stage 13 done-when requires a console UI for invites
  specifically (only "seats used" *display*, which `13-04` covers by reading the operator count, not by
  building an invite UI). A curl-based verification is enough for this item's own Done-when, matching how
  `5-05`/`10-01` verified backend-only flows before their console counterparts existed.
- A second color of invite ("admin-only invite link" vs "public join link", or an invite that does not
  expire) — one single-use, expiring, role-specific invite per generation call is the full shape; nothing
  in this stage's own scope asks for more.
- Changing `sites.tier`/`seat_limit` away from the free default — `13-02`'s job entirely; this item ships
  the columns and the enforcement point, not a way to raise the limit yet.
- Applying this seat check retroactively to `10-02`'s own registration flow — it already has a hard,
  structural cap of exactly one operator (one `Site` + one `Operator` in one transaction); there is no
  second operator that flow could ever create, so there is nothing for this item's check to guard there.

## Done when

- [x] `Ago.Chat.Integration.Tests`: a real admin-role operator generates an invite; a real Keycloak-signed
      token with no matching `operators` row redeems it and gets a working operator session — verified by
      querying rows directly.
- [x] Double-redemption, expired-invite, and same-site-already-operator (per `13-07`/`adr/0068`'s
      relaxed rule) each rejected with a real second call.
- [x] Seat-limit enforcement proven under real concurrency: `seat_limit=2`, one existing operator, 20
      concurrent redemptions racing the one remaining seat — exactly one succeeds.
- [x] A capacity-rejected invite confirmed still redeemable once a seat opens.
- [x] `docs/architecture/data-model.md` gains the `operator_invites` table and `sites.tier`/`seat_limit`
      columns, with the row-lock-vs-shadow-counter note (`ago-root#235`).
- [x] `docs/architecture/authorization.md` notes `Permission.SiteManageOperators`'s first real
      write-path caller (`ago-root#235`).

## Open questions

None — the mechanism follows directly from `10-01`/`10-02`'s already-decided identity and role shapes,
`adr/0016`'s existing permission, and `adr/0024`'s already-accepted precedent for a generated,
one-time-shown bearer value in this codebase (adapted to hash-not-encrypt for the reason stated above).
The multi-identity loophole and the exact seat-limit reset/decrement story are named explicitly above as
accepted gaps and future work, not as blockers — neither is required by this item's own scope or by
`roadmap.md`'s Stage 13 done-when.
