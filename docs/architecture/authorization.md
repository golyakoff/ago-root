# Authorization: current state and what's still open

## Status

**The authorization model is decided: RBAC, scoped per tenant (`adr/0016`).** Operator-side checks
exist in `Application` from Stage 1 onward (`1-02`, `1-06`). **Operator authentication is decided and
shipped: OIDC via Keycloak (`adr/0022`, `5-05`)** - `1-06`'s dev-only stub is gone. What remains open
is narrower still: the management surface for custom per-tenant roles (Stage 5 console work -
`adr/0016` fixed the model, not that surface).

Do not read anything before `1-02`/`1-06` land as authorized. Until then, `visitor` and `operator`
tokens *identify* a principal and *scope* it to a `site_id`; nothing yet asks "is this principal
allowed to do this specific thing." A visitor token proves "this is the same browser that opened this
conversation," not "this browser may read conversation X." Handlers must not be trusted to have
checked this until those items ship (`clean-architecture.md`: auth decisions are application code,
never edge or infrastructure - `edge.md`, `naming-and-structure.md`).

**Signing key sharing, `3-06`**: `Ago.Chat.Api`'s signing key was generated fresh per process
(`Program.cs`) - correct for the single-instance `dotnet run` loop `local-dev.md` describes, but a
token issued by one replica cannot be validated by another, which only matters once there is more
than one replica. Found running the local overlay with 3 replicas for real: a token issued by pod A
401'd the instant a request landed on pod B. `Auth:SigningKey` (bound from the same
`infra-credentials` mechanism `docker/.env`'s Postgres/RabbitMQ passwords already use - gitignored,
never committed) lets every replica share one key; its absence still falls back to the original
random-per-process key. **Still true, but only for the Visitor scheme now** - `5-05`/`adr/0022`
replaced this signing story outright for the Operator scheme, not by evolving it: Keycloak's own
JWKS is the signature source there, no local key involved at all.

## The four actors, and what's already true about each

| Actor | Identification today | Authorization today |
|---|---|---|
| **Visitor** | Signed token (cookie/localStorage), scoped to one `site_id`, issued by `Ago.Chat.Api` on first contact (`vision.md`, `realtime.md`) | None beyond the token's `site_id` claim |
| **Operator** | `/hubs/operator` expects a JWT (`realtime.md`) - **issued by Keycloak** (`5-05`, `adr/0022`), validated directly against its JWKS; `OperatorId`/`site_id` are resolved from the token's `sub` via `OperatorIdentityClaimsTransformation`, not read from the token directly | `adr/0016`'s RBAC, resolved per request from `OperatorId`/`site_id` regardless of how they were resolved |
| **Webhook/API integrations** | Outbound only today: deliveries to a tenant's endpoint are HMAC-signed (`adr/0013`) so *they* can verify *us*. There is no inbound integration API yet, so "how does a third party authenticate to AGO Chat" is entirely unplanned | N/A - does not exist |
| **Platform owner** | The same Keycloak realm, the same console login page, the same `JwtSchemes.Operator` token every operator already presents (`5-05`, `adr/0022`) - distinguished only by a `platform-owner` **realm role** in the token's `realm_access.roles` claim (`12-01`, `adr/0032`). No `operators` row, no `external_subject_id` link, no `OperatorId`/`SiteId` claims - `OperatorIdentityClaimsTransformation` resolves nothing for this identity and is not consulted | The `RequirePlatformOwner` policy, and nothing else. Entirely outside `adr/0016`'s RBAC: no `site_id` to anchor a check to, `IPermissionChecker` never called. Grants exactly one thing as of `12-02`: `GET /api/v1/owner/sites`, a read-only cross-tenant overview. No write or action surface for this actor exists |

`site_id` scoping is the one piece already load-bearing everywhere (`vision.md`: "multi-tenant from
day one"). Every candidate model below keeps it; none of them replace it. The **platform owner** is
the one deliberate exception, and it is an exception *outside* the model rather than a hole in it -
`adr/0032`: an owner is not an `Operator` with a wider scope, it is a caller the RBAC model has no
representation for at all, recognised by a claim that model can never write.

## Decided: the authorization model

`adr/0016` chose **granular permissions (RBAC)** over roles + tenant scoping: named permissions
(`conversation:read`, `conversation:send`, `conversation:assign`, `site:configure`, ...) bound to a
`Role`, roles assigned per tenant. Chosen knowingly over the simpler, cheaper roles+scoping
alternative, to have the recognizable pattern in place before Stage 5's console needs it for real
rather than retrofitting it under pressure then - see `adr/0016`'s Consequences for the trade accepted.

Stage 1 ships exactly one hardcoded role (`"Operator"`) and the check mechanism, not a role-management
surface - that arrives with Stage 5's console.

## Permissions and roles beyond Stage 1 - deliberately deferred, not forgotten

Discussed while writing `1-02`/`1-06`, decided to defer rather than build speculatively
(`clean-architecture.md`: an abstraction with one caller is a guess about the second one). Recorded
here so a later session designing Stage 4 or Stage 5 does not have to rediscover the reasoning:

- **`conversation:transfer`** - an operator hands off their *own already-assigned* conversation to a
  named colleague (escalation, shift change, wrong expertise). Distinct from `conversation:assign`,
  which claims an unassigned conversation out of the waiting queue - transfer moves an assigned one
  directly between two operators, no queue involved. Natural home: **Stage 4**, next to the real
  assignment engine, since both are "who is allowed to move a conversation between operators" and
  benefit from being designed together rather than transfer arriving as an afterthought. **Still
  open** - confirmed while shipping `5-08` (the admin role and `attachment:delete`, below) that Stage
  4 never actually built this; it stays deferred here, not silently dropped.
- **`attachment:upload`/`attachment:view` as separate permissions from `conversation:send`/`read`** -
  considered and rejected for now: nothing in `vision.md` calls for an operator who can read a
  conversation's text but not its files (or vice versa). If a real compliance scenario needs that
  split later, it is a permission split, not a data-model change - cheap to add when a caller actually
  needs it.
- **`site:manage_webhooks`** - not designed yet, but Stage 6 (`Ago.Chat.Webhooks`, `adr/0013`:
  "tenant endpoint registration") will need exactly this kind of check. Flagging now so Stage 6's
  planning session connects it to this model instead of inventing a parallel one.

## Operator authentication: OIDC via Keycloak

**Shipped in `5-05`** (`adr/0022`) - no longer a direction, a fact. The console redirects to Keycloak
(Authorization Code + PKCE); `Ago.Chat.Api`'s Operator JWT scheme validates the returned token
directly against Keycloak's own JWKS (`Authority`-based discovery, no local signing key involved -
still a JWT, so `realtime.md`'s "`/hubs/operator` authenticated by the operator's JWT" never changed,
only *who signs it* did). Keycloak's token proves identity to Keycloak; it carries no `OperatorId` or
`site_id` of its own, since Keycloak has never heard of either concept - a new
`IClaimsTransformation` (`OperatorIdentityClaimsTransformation`) resolves the validated token's `sub`
against the `operators` table's new `external_subject_id` column and adds those claims after the
fact, the same "resolve at request time" shape `PermissionChecker` already used for role resolution.
A `sub` matching no operator adds nothing; the `RequireOperatorIdentity` authorization policy is what
turns that into a clean rejection.

Self-issuing tokens against a password table in `ago-chat`'s own database was considered and rejected,
for the reason this section always gave: a real feature (password reset, hashing, brute-force
lockout) that competes for review attention with the concurrency and data work this project exists to
demonstrate, for a problem every OIDC provider has already solved correctly.

**Shipped in `10-01`** (`adr/0028`) - a second, strictly weaker authorization policy,
`RequireKeycloakIdentity`, exists now alongside `RequireOperatorIdentity` on the same `Operator` JWT
scheme. It accepts any token that is signature/audience/lifetime-valid against Keycloak's JWKS -
including one whose `sub` resolves to no `operators` row - and is wired to exactly one route,
`10-02`'s `POST /api/v1/sites` bootstrap endpoint. It exists because Keycloak's own
`registrationAllowed: true` realm setting means a real visitor can now complete Keycloak's hosted
registration form and hold a genuine, terminable authentication state `RequireOperatorIdentity` was
never meant to admit - see `adr/0028` for why the two policies must stay distinct rather than
`RequireOperatorIdentity` relaxing its own `RequireClaim(OperatorId)` check. The **Visitor** and
**Webhook/API integrations** rows in the actor table above are unaffected - this is a second
enforcement point on the existing Operator identification mechanism, not a fourth actor.

Consequence this pinned down early, now realised: `Ago.Chat.Api` holds OIDC configuration
(`Auth:Keycloak:Authority`/`Audience`) - not a secret itself (an issuer URL and a public client id,
neither confidential), but Keycloak's own admin credentials are, and stay in `infra-credentials`
alongside every other local-dev password (`repositories.md` - "no secrets, ever").

## Admin/supervisor role and `attachment:delete`: shipped in `5-08`

**Shipped in `5-08`** - no longer deferred, a fact. `Permission.SiteConfigure`
(`"site:configure"`), `Permission.SiteManageOperators` (`"site:manage_operators"`), and
`Permission.AttachmentDelete` (`"attachment:delete"`) all exist now (`Ago.Chat.Domain.Permission`,
matching `adr/0016`'s `resource:action` naming convention exactly). A second built-in role,
`"Admin"`, holds all three - seeded the same way `1-05`'s `"Operator"` role was
(`deploy/seed/create-demo-tenant.sh`), granted only via that script. **Who can grant a role is still
answered only by the seed script** - this item considered and explicitly rejected building a
role-assignment surface now: `adr/0016`'s Consequences already named a general role-editor UI as
future work, not a Stage 5 deliverable, and nothing in this item's own scope forced the question open
sooner. The demo tenant now seeds two operators - `demo-operator` (`"Operator"` only) and
`demo-admin` (`"Operator"` + `"Admin"`, so it can also be assigned conversations and exercise
`attachment:delete` on its own thread, not just view the site-wide list) - specifically so "an admin
sees every conversation for a site, an ordinary operator does not" is something a session can verify
against two real accounts, not just assert.

The admin role's distinguishing feature - seeing every conversation for a site - is gated on
`Permission.SiteConfigure`, checked by `GetAllConversationsForSiteHandler`
(`Ago.Chat.Application`) the same way every other permission check in this codebase already is
(`IPermissionChecker`, no new mechanism). Deliberately narrower than it might first sound: this item
does **not** extend `JoinConversationAsync`/`GetConversationHistoryHandler`'s participant checks to
let an admin open the full message thread of a conversation assigned to someone else - the console's
admin view is read-only summary data (visitor, state, assigned operator, started, unread count), not
a way to browse into another operator's conversation. Extending message-level read access site-wide
was judged materially bigger than this item's own scope (a second, riskier change to the
assignment/read-access model this item was never asked to make) and is flagged here, explicitly, as
follow-up work for whichever session actually needs it, rather than half-built silently. The
attachment-delete action itself has no such restriction - `DeleteAttachmentHandler` checks
`attachment.SiteId` against the caller's own site, not conversation assignment, so an admin can
moderate any attachment on their site regardless of who it is assigned to; the console UI just cannot
*navigate* to an arbitrary conversation's thread to reach it today.

`attachment:delete` deletes the row (`Attachment.MarkDeleted`, terminal) and both storage objects -
the main upload and, if `5-04`'s thumbnail job already produced one, the thumbnail too. Found live
while manually verifying this item: an early version only deleted the main object, leaving a real
orphaned thumbnail behind in MinIO on every delete - `DeleteAttachmentHandler`'s own remarks have the
detail. Same "tolerate already-gone" reasoning `5-04`'s orphan sweeper uses for the storage side,
extended to the row itself: a retried delete is idempotent, not an error.

## `site:configure` gates a second, distinct thing: shipped in `11-01`

`Permission.SiteConfigure` was granted for exactly one caller until now (`GetAllConversationsForSiteHandler`'s
site-wide conversation view, `5-08` above). `11-01` gives it a second, unrelated caller:
`GetWidgetConfigHandler`/`UpdateWidgetConfigHandler` (`Ago.Chat.Application`), gating read/write access
to a site's widget appearance (`adr/0029`). Same mechanism, no new permission - `site:configure` reads
as "configure this site" broadly enough to cover both without inventing a narrower permission for
widget appearance specifically, the same `resource:action` naming judgment `adr/0016` already applies
elsewhere. Both callers are still `IPermissionChecker`-checked the ordinary way; nothing about this
widens who holds the permission - only the "Admin" role, seeded the same way as before.

## The platform owner: shipped in `12-01`

**Shipped in `12-01`** (`adr/0032`) - a fourth actor, and the first one that is not scoped to a site
at all. A third authorization policy, `RequirePlatformOwner`, sits on the same `JwtSchemes.Operator`
scheme alongside `RequireOperatorIdentity` and `RequireKeycloakIdentity`, and accepts exactly one
thing: a signature/audience/lifetime-valid Keycloak token whose `realm_access.roles` claim contains
the `platform-owner` **realm role**. `PlatformOwnerAuthorizationHandler` (`Ago.Chat.Api/Auth/`)
parses that claim - Keycloak emits it as a JSON object, so a plain `RequireClaim` cannot express the
check - and succeeds on nothing else.

Why it is not `5-08`'s `"Admin"` role with a wider scope, restated here because it is the whole point
of the item: an admin operator is an `Operator` row, resolved through
`OperatorIdentityClaimsTransformation`, scoped to one `site_id`, checked through `PermissionChecker`.
The platform owner has none of those. `PlatformOwnerAuthorizationHandler` reads exactly one input - a
claim Keycloak signs - and that input is not writable by anything in this system, so no `INSERT` into
`roles`/`operator_roles`, however broadly granted, can satisfy it. The separation runs both ways and
both ways are tested: the owner identity has no `operators` row, so `RequireOperatorIdentity` rejects
the very token `RequirePlatformOwner` accepts, and a `demo-admin` token that really does hold
`site:configure` (proven against `PermissionChecker` in the same test, not asserted) is rejected by
`RequirePlatformOwner` while `RequireOperatorIdentity` accepts it.

Fail-closed by construction, not by convention: the role name is a compile-time constant rather than
configuration (there is no key to omit and no empty value to mis-read as "no restriction"), and the
handler calls `context.Fail()` explicitly on every non-matching path, which is sticky for the whole
policy evaluation - a second handler added for the same requirement later cannot grant what this one
denied. A missing claim, a claim that is not JSON, a `roles` value that is not an array, and a
case-different role name all land there, each with a test.

**Who holds the role is never in this repository.** The realm role is *defined* in every realm-import
file the project maintains and *granted* only in the test one, to a fixed identity that exists solely
inside a Testcontainers container. `ago-deploy/k8s/base/keycloak-realm-import.json` defines it and
grants it to nobody - deliberately, since that one file provisions the public demo realm and every
credential in it is committed to a public repository, so a committed grant would be the leak itself
(`repositories.md`, "no secrets, ever"). The real grant is a manual action in Keycloak's admin
console. Consequence, accepted: a freshly imported realm has no platform owner until someone assigns
the role by hand, which is the correct default and not a defect. Note when doing it: the demo/local
Keycloak runs `start-dev --import-realm` with no persistent volume, so a hand-made grant is lost on
every pod restart - and Keycloak imports with `IGNORE_EXISTING`, so on a Keycloak whose realm *does*
persist, adding the role to the import file does not create it either.

`12-01` deliberately built no owner *action*. `RequirePlatformOwner` is wired to no route yet - the
cross-tenant query is `12-02`, the console view is `12-03`, and any write access an owner might have
is not designed. Nothing about the role's presence widens any existing policy.

**`12-02` gave it its first and only route**: `GET /api/v1/owner/sites`, the cross-tenant operations
read (`OwnerSitesEndpoints`, `backlog/12-02`). Three things about it matter here. The path says
`/owner/`, never `/admin/`, so a URL in a log or a screenshot cannot blur this actor back together with
`5-08`'s site-scoped `"Admin"` role. The policy is the *entire* access-control story behind it: the
handler makes no second check and structurally cannot, since the fact that authorizes the call is a
claim, and `Ago.Chat.Application` has no port that sees claims - re-checking there would be a second,
weaker copy of the same rule, free to drift from the first. And it is read-only: still no owner *write*
or action surface anywhere, by design (`12-02`'s Out of scope). Proven with real tokens, not asserted:
an ordinary operator and a `site:configure`-holding `demo-admin` both get `403`, an anonymous caller
`401` (`OwnerSitesEndpointTests`).

## Done when nothing here is open anymore

- [x] An ADR chooses the authorization model - `adr/0016`, RBAC.
- [x] An ADR confirms the OIDC direction for operators - `adr/0022`, Keycloak (`5-05`).
- [x] `realtime.md` updated to state the shipped mechanism as fact (`1-06`, `5-05`). `vision.md` did
      not need a change - it never described an authorization model to begin with.
- [x] The admin/supervisor role and `attachment:delete` ship - `5-08`, above.
- [x] An ADR decides how a caller that is not scoped to any site is represented - `adr/0032`, a
      Keycloak realm role, outside the RBAC model rather than a wildcard inside it (`12-01`).
