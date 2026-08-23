# Site and operator self-registration

- **Stage**: 10
- **Status**: ready
- **Depends on**: `10-01-self-registration-identity-flow.md` — needs its `RequireKeycloakIdentity`
  policy to authenticate the bootstrap call this item adds; blocked transitively by `10-01`'s own open
  question until that lands.

## Goal

Given a validated Keycloak principal `10-01` makes possible (a real `sub`, no matching `operators` row
yet) plus the minimum a visitor supplies (a site display name, one embed origin), a new
`POST /api/v1/sites` endpoint creates one `Site`, seeds both of this codebase's built-in roles
(`"Operator"`, `"Admin"`) for that site the same way `1-05`'s script has always done for the demo site,
creates one `Operator` row with `external_subject_id` set to the principal's `sub`, and assigns it
*both* roles — so the caller can immediately do everything `5-08`'s `demo-admin` operator can do today:
work conversations and administer the site. `1-05`'s script keeps existing for local-dev demo seeding;
it stops being the *only* path a real operator is ever created through, which is this stage's own
"zero seed-script involvement" done-when.

## Context to read first

`docs/architecture/data-model.md`'s `sites`/`operators`/`roles`/`operator_roles` shapes.
`docs/backlog/1-05-seed-demo-tenant.md` — the exact role-seeding shape this item reuses (though this
item is not idempotent the way seeding is: a second registration call from the same identity must be
rejected, not silently produce a second free site — see Scope). `docs/adr/0016-rbac-authorization-model.md`
and `docs/backlog/5-08-console-attachments-and-admin-role.md` — the fixed permission sets for
`"Operator"` (`conversation:read`, `conversation:send`, `conversation:assign`) and `"Admin"`
(`site:configure`, `site:manage_operators`, `attachment:delete`), and the `demo-admin` precedent of
holding *both* role assignments rather than one role including the other's permissions. `docs/conventions/api-design.md`
(`POST`/`201`/`Location`, RFC 7807 errors). `docs/backlog/3-05-rate-limiting.md` — the `IRateLimiter`
port and per-key bucket pattern this item's own abuse-prevention check reuses rather than inventing a
second mechanism. `docs/conventions/naming-and-structure.md` for where a new use case folder belongs.

## Scope

- **Application**: a `RegisterSiteHandler` (state the final name once written) whose input is the
  authenticated principal's `sub` (read from claims, never from the request body — identity comes from
  the validated token, not user-supplied data), a site display name, and at least one initial
  `allowed_origins` entry (validated as a well-formed origin, matching whatever shape
  `Site.AllowedOrigins` already expects). In one transaction: create `Site`; create both `Role` rows
  for *this* site with the fixed permission sets above (a site's roles are tenant-local per
  `adr/0016` — a self-registered site starts with none until this handler creates them, unlike the
  demo site where `1-05`'s script always has); create one `Operator` row
  (`external_subject_id = sub`); insert both `operator_roles` rows. State explicitly why this is one
  wider transaction rather than `data-model.md`'s usual "one aggregate per transaction" — this is a
  genuine multi-row provisioning step (`Site` + two `Role`s + `Operator` + two `operator_roles`), the
  same shape `1-05`'s script already produces non-transactionally via idempotent `ON CONFLICT DO
  NOTHING` SQL, done here as one real transaction instead because a partial failure here must not leave
  a site with no roles or a token holder resolving to nothing.
- `Site.PublicKey` generated via the existing `IIdGenerator` port — never `Guid.NewGuid()` directly
  (`CLAUDE.md` rule 2), matching every other id in this codebase.
- **HTTP**: `POST /api/v1/sites`, gated by `10-01`'s `RequireKeycloakIdentity` policy — never
  `RequireOperatorIdentity`, since the caller has no `OperatorId` claim yet by definition. `201` with a
  `Location` header (state where it points — a future "get my site" read model does not exist yet;
  note explicitly that `Location` is still valid per `api-design.md` even with no matching `GET` behind
  it today, and flag the missing read endpoint as a real, separate gap rather than building one
  speculatively here).
- **One registration per identity for Stage 10**: a caller whose `sub` already resolves to an
  `operators` row (via the existing `OperatorIdentityClaimsTransformation`) gets a clean `409` RFC 7807
  response, not a second site. This matches "everyone starts on the free tier" with no multi-site story
  yet (see Out of scope) — one Keycloak identity, one site, for this stage.
- Reuse `IRateLimiter` (`3-05`'s port), keyed per-`sub` and per-IP, guarding this endpoint specifically
  — the abuse-prevention surface `10-01`'s own Scope names as the real one this project's code must
  cover, since Keycloak's registration form itself sits outside this request path.

## Out of scope

- Inviting additional operators to an already-registered site. `5-08` gave `"Admin"` the
  `site:manage_operators` permission, but no handler anywhere uses it beyond the admin console's
  read-only view — a real invite flow is new scope no roadmap stage names yet. Flagged here for
  whoever plans it next, not built speculatively as a side effect of this item.
- **A separate `Account` aggregate above `Site`.** `roadmap.md`'s Stage 13 language ("site-count caps")
  hints a future tier might allow more than one site per account, but nothing in *this* stage's own
  done-when needs that, and introducing a new aggregate for a concept with exactly one caller today is
  the same "speculative structure, one caller" trade `adr/0016` already weighed deliberately — doing it
  again here without a second real caller would be exactly the premature generalisation
  `clean-architecture.md`'s qualifying rules warn against. Flagged explicitly for whoever plans Stage 13
  to revisit with real requirements in hand, not solved here. `Site` remains the tenant (`vision.md`);
  "account holder" in this stage's own goal means "the first Operator of a newly created Site," nothing
  more.
- A tier/plan column anywhere. There is exactly one tier today (free) — nothing to store yet. Stage 13
  adds whatever column(s) billing actually needs, on whichever table turns out to need them, once that
  requirement is real.
- The console UI collecting the fields this endpoint accepts — `10-03`.
- Any database migration: `Site`, `Operator`, `Role`, `operator_roles` all already exist per
  `data-model.md`; this item is pure Application/Infrastructure/Host code against the existing schema.
  If implementation finds a real gap, state it here rather than silently adding a migration this file
  never scoped.

## Done when

- [ ] `Ago.Chat.Integration.Tests`: a real Keycloak-signed token with no matching operator, posted to
      `POST /api/v1/sites`, results in exactly one new `Site`, two new `Role`s (`"Operator"` +
      `"Admin"`, matching `5-08`'s exact permission sets), one new `Operator` with
      `external_subject_id` set from the token's `sub`, and two `operator_roles` rows — verified by
      querying the rows directly, not just asserting the `201`.
- [ ] The created operator's token subsequently resolves `OperatorId`/`SiteId` through the existing
      `OperatorIdentityClaimsTransformation` and can call an ordinary `RequireOperatorIdentity`-gated
      route (e.g. the queue) — proving the created rows are a real, working operator identity, not
      just database rows that merely look right.
- [ ] A second `POST` from the same `sub` is rejected `409`, not a second site — proven with a real
      second call, not asserted from the handler's logic alone.
- [ ] Rate limiting proven the same real-concurrency way `3-05`'s own tests prove their bucket (N
      concurrent calls, exactly the configured capacity honoured, not a sequential loop).
- [ ] `docs/architecture/data-model.md` gets a note if this item's own implementation surfaces anything
      not already documented about how `roles`/`operator_roles` get written outside `1-05`'s script
      (state explicitly, once written, whether it does or doesn't).

## Open questions

None — the mechanism follows directly from `adr/0016`/`5-08`'s already-decided role shapes and
`10-01`'s identity contract; nothing here needs the author's product-level input once `10-01`'s own
question is answered.
