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
| **Visitor** | Signed token (localStorage), scoped to one `site_id`, issued by `Ago.Chat.Api` on first contact (`vision.md`, `realtime.md`); **7-day lifetime, renewed at the point of use** (`POST /api/v1/visitor-sessions/renew`), still no revocation - each a decision, not an accident: `17-06`/`adr/0034` for revocation, `17-07`+`17-08`/`adr/0048` for the lifetime and the renewal path | None beyond the token's `site_id` claim |
| **Operator** | `/hubs/operator` expects a JWT (`realtime.md`) - **issued by Keycloak** (`5-05`, `adr/0022`), validated directly against its JWKS; `OperatorId`/`site_id` are resolved from the token's `sub` via `OperatorIdentityClaimsTransformation`, not read from the token directly | `adr/0016`'s RBAC, resolved per request from `OperatorId`/`site_id` regardless of how they were resolved |
| **Webhook/API integrations** | Outbound only today: deliveries to a tenant's endpoint are HMAC-signed (`adr/0013`) so *they* can verify *us*. There is no inbound integration API yet, so "how does a third party authenticate to AGO Chat" is entirely unplanned | N/A - does not exist |
| **Platform owner** | The same Keycloak realm, the same console login page, the same `JwtSchemes.Operator` token every operator already presents (`5-05`, `adr/0022`) - distinguished only by a `platform-owner` **realm role** in the token's `realm_access.roles` claim (`12-01`, `adr/0032`). No `operators` row, no `external_subject_id` link, no `OperatorId`/`SiteId` claims - `OperatorIdentityClaimsTransformation` resolves nothing for this identity and is not consulted | The `RequirePlatformOwner` policy, and nothing else. Entirely outside `adr/0016`'s RBAC: no `site_id` to anchor a check to, `IPermissionChecker` never called. Grants five things as of `23-14`: `GET /api/v1/owner/sites`, a read-only cross-tenant overview with an optional name/id search (`12-02`, `23-14`); `GET /api/v1/owner/sites/{siteId}`, the per-tenant detail behind it - the same eight facts plus entitlements (`23-14`); the channel-identity unlink (`14-12`, `adr/0079`); and the module grant and revoke (`22-17`, `adr/0098`). The last three are **cross-tenant writes** - this cell said none existed until 2026-09-04, which had been wrong since `14-12` **`12-04`: and one thing it is explicitly refused** - `10-02`'s `POST /api/v1/sites` registration bootstrap, which would otherwise turn this identity into an ordinary tenant operator permanently (`adr/0063`) |

`site_id` scoping is the one piece already load-bearing everywhere (`vision.md`: "multi-tenant from
day one") - **and "everywhere" is now a checked claim rather than an assumption**: every use case,
route and read query is classified in `tenant-isolation.md`, and `17-01` found one place where the
scoping was genuinely absent (see the section on it at the end of this file). Every candidate model
below keeps it; none of them replace it. The **platform owner** is
the one deliberate exception, and it is an exception *outside* the model rather than a hole in it -
`adr/0032`: an owner is not an `Operator` with a wider scope, it is a caller the RBAC model has no
representation for at all, recognised by a claim that model can never write.

**The rows are not mutually exclusive, and `12-04` is the item that made that cost something.** One
Keycloak identity can hold the `platform-owner` realm role *and* have an `operators` row — the
author's own account on the public deployment does — because the two are recognised from unrelated
inputs. Any surface that has to pick one behaviour for such a caller is stating a **precedence** of
its own, not reading a fact off the token, and should say which precedence it chose and why
(`adr/0063`).

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

**One consequence `10-03` added, recorded because it is invisible from the API side.**
`RequireOperatorIdentity`'s rejection is no longer only a gate - it is also the *signal* the console
routes on. `ago-console`'s OIDC callback tells "an existing operator" from "a real Keycloak identity
with no `operators` row yet" by calling `GET /api/v1/operators/me` and reading the status: `200` is
an operator, `403` is the new state, and anything else (`401`, `5xx`, a network failure) is treated
as a failure rather than as either. That is deliberate - the console must not decode the token and
guess, because the resolution is `OperatorIdentityClaimsTransformation`'s and happens per request -
but it does mean **that endpoint's `403` for a claimless principal is now a contract**, not an
implementation detail. Changing it to a `404`, or to a `200` with an empty body, would silently send
freshly-registered visitors to a queue that will never fill for them. Nothing needs to change today;
whoever touches that route should know the console is reading its status code as an answer.

**And that `403` means two different people, which `12-04` had to correct on the live deployment**
(`adr/0063`). `adr/0032` gives the platform owner no `operators` row *deliberately*, so
`GET /api/v1/operators/me` answers `403` for that identity exactly as it does for a fresh registrant —
and the console sent the owner to `10-02`'s registration form, whose button would have committed a
`Site`, its roles and an `Operator` row for the owner's `sub` in one transaction, with no un-register
path in the product. What closed it, and what did not last:

- **Client-side, `ago-console`'s callback asks a second question** — `12-03`'s existing
  `GET /api/v1/owner/sites?limit=1` probe — and routes an accepted caller to `/owner`. Precedence is
  operator first, owner second, registrant last, because the two identities are orthogonal and one
  account can hold both.
- `12-04` also added a **server-side refusal** on `POST /api/v1/sites`
  (`AuthorizationPolicies.NotThePlatformOwner`). **`12-05` withdrew it a day later**
  (`adr/0063`'s amendment): being the platform owner and running a tenant are orthogonal, so refusing
  there made the axes exclusive at exactly one endpoint — the thing that ADR argues against. The
  defect was the *unasked-for form*, and the routing bullet above is what closed it. The endpoint's
  gate is `RequireKeycloakIdentity` alone again, and one identity may hold the `platform-owner` realm
  role **and** an `operators` row of its own.

**One person may therefore be both, and both surfaces must keep working for them.** The consequence
worth stating here, because it is invisible until it goes wrong: once the owner has a tenant,
`OperatorIdentityClaimsTransformation` resolves for that identity, so **every** request it makes
carries an `operator_id` and a `site_id` — `GET /api/v1/owner/sites` included. That endpoint consults
neither (`ListSitesForOwnerHandler` re-checks nothing; `PlatformOverviewReadStore`'s SQL has no
tenant predicate), and a version of it that did would fail *silently*: the owner would see a shorter
list of tenants, which is indistinguishable from a platform with fewer tenants. Anything added to
that read path has to keep it cross-tenant on purpose
(`PlatformOwnerAsTenantTests` is what holds the line).

**`adr/0032` is unchanged by any of this.** The platform-owner *role* still carries no tenant — it is
a Keycloak realm role and no row this codebase writes can grant it. The *person* holding it may
separately hold an ordinary operator seat, which is a different statement.

`adr/0063` records why the underlying ambiguity is answered per surface rather than by one central
"what kind of principal is this token", and states the rule that replaces the guessing: **a surface
may act on "this principal is an X" only when something authoritative said X** — never by reading the
absence of one kind as the presence of another. That is the mistake all three instances made.

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

**`Permission.SiteManageOperators` gained its first real write-path caller in `13-01`.** This section
previously noted the permission existed with no handler beyond the admin console's read-only view -
`CreateOperatorInviteHandler` (`Ago.Chat.Application`) is that caller now, gating generation of a
single-use operator invite the same way every other permission check in this codebase already is
(`IPermissionChecker`, no new mechanism). Redemption itself (`RedeemOperatorInviteHandler`) is gated by
`RequireKeycloakIdentity`, not `RequireOperatorIdentity` - the redeeming caller has no `OperatorId`
claim yet by definition, the same reasoning `10-02`'s bootstrap endpoint already established. It carries
no `SiteId` either: the site a redemption acts on is never a caller-supplied value, only the fact
`invite.SiteId` already established when the invite was generated under the permission check above -
listed in `Ago.Chat.Architecture.Tests`' `TenantScopeExemptions` with that reasoning, the same category
as `RegisterSiteHandler`.

`13-07`/`adr/0068` also changed the shape of one carried-over constraint: `13-01`'s redemption handler
rejects a `sub` only when it already resolves to an `Operator` row on *that invite's own* site - never
"resolves to an operator row anywhere", the older, single-tenant rule that predated `13-07`'s composite
`(external_subject_id, site_id)` uniqueness.

## `site:configure` gates a second, distinct thing: shipped in `11-01`

`Permission.SiteConfigure` was granted for exactly one caller until now (`GetAllConversationsForSiteHandler`'s
site-wide conversation view, `5-08` above). `11-01` gives it a second, unrelated caller:
`GetWidgetConfigHandler`/`UpdateWidgetConfigHandler` (`Ago.Chat.Application`), gating read/write access
to a site's widget appearance (`adr/0029`). Same mechanism, no new permission - `site:configure` reads
as "configure this site" broadly enough to cover both without inventing a narrower permission for
widget appearance specifically, the same `resource:action` naming judgment `adr/0016` already applies
elsewhere. Both callers are still `IPermissionChecker`-checked the ordinary way; nothing about this
widens who holds the permission - only the "Admin" role, seeded the same way as before.

## And a third: shipped in `14-04`

`Permission.SiteConfigure` gains its third pair of callers - `GetOfflineAutoReplyHandler`/
`UpdateOfflineAutoReplyHandler` (`Ago.Chat.Application`), gating read/write access to a site's offline
auto-reply script (`adr/0066`). Same mechanism, no new permission, and the backlog item said so
explicitly: a single boolean does not earn a permission of its own, and "configure this site" already
covers the site-wide conversation view and the widget's appearance without stretching. Nothing about
this widens who holds it - still the seeded `"Admin"` role and nothing else.

Worth noting for the tenant-isolation accounting (`tenant-isolation.md`): `14-04` adds a *third*
handler that takes a `SiteId` and checks no permission - `SendOfflineAutoReplyHandler` - and it is an
`Ago.Chat.Worker` consumer, in the same category as `RecordUnreadMessageHandler`. Its `SiteId` comes
off a `MessageAccepted` envelope this system itself published, so it is a fact the triggering write
already established rather than a claim to verify, and there is no principal to check a permission for:
nobody asked for the reply, a broker delivery did. It is listed in `TenantScopeExemptions` with that
reasoning, which is what keeps the arch test honest in both directions.

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

**`12-02` gave it its first route**: `GET /api/v1/owner/sites`, the cross-tenant operations
read (`OwnerSitesEndpoints`, `backlog/12-02`). Three things about it matter here. The path says
`/owner/`, never `/admin/`, so a URL in a log or a screenshot cannot blur this actor back together with
`5-08`'s site-scoped `"Admin"` role. The policy is the *entire* access-control story behind it: the
handler makes no second check and structurally cannot, since the fact that authorizes the call is a
claim, and `Ago.Chat.Application` has no port that sees claims - re-checking there would be a second,
weaker copy of the same rule, free to drift from the first. And it is read-only, which `12-02`'s Out of scope
intended to be the state of the whole actor. Proven with real tokens, not asserted: an ordinary
operator and a `site:configure`-holding `demo-admin` both get `403`, an anonymous caller `401`
(`OwnerSitesEndpointTests`).

**`23-14` gave the read a per-tenant companion**: `GET /api/v1/owner/sites/{siteId}`, mapped in the
same `OwnerSitesEndpoints` file and gated by the identical `RequirePlatformOwner` policy - the eight
aggregate facts `12-02`'s list already computes, for exactly one tenant, plus that tenant's enabled
modules (`GrantedByOwner`, `ExpiresAt`, and whether each is active right now). `GetSiteForOwnerHandler`
makes the same "no second check" argument `ListSitesForOwnerHandler` does, for the same reason: the
authorizing fact is a claim, and `Ago.Chat.Application` has no port that sees one. Unlike its sibling,
this handler *does* take a `SiteId` - chosen by the caller, never checked against anything - which is
the read-side instance of the shape the three writes below already have, and is why
`tenant-isolation.md`'s "the cross-tenant surfaces the platform owner reaches" grew from four to five
rather than gaining a sixth, separately-argued category. `12-02`'s own list also gained an optional
name/id search in the same change: the predicate narrows the *page*, never the reported total
(`OwnerSitesResponse.MatchingSites`/`TotalSites`, both present on every response) - the one place this
document's "the list is complete" claim (`flows.md` 5.1) could have quietly stopped being true, and
the reason `23-14`'s own tests assert the total explicitly rather than trusting a shorter page to speak
for itself.

## The owner acquired a write surface, twice, and this file did not notice the first time

**`14-12` was the first** (`adr/0079`): `POST /api/v1/owner/sites/{siteId}/channel-identities/{id}/unlink`.
It arrived as one clause of a larger item about verified channel linking, and the sentence above - "no
owner write or action surface anywhere, by design" - stayed in this file for three weeks after it
stopped being true. Recording that is the point of this section: the claim did not survive contact
with the second write either, and a rule stated in one place is what would have caught the first.

**`22-17` added the other two** (`adr/0098`): `PUT` and `DELETE
/api/v1/owner/sites/{siteId}/modules[/{moduleKey}]`, the platform owner granting or revoking a module
for a named tenant with no payment - a trial, or the repair of a payment that provisioned nothing.

All three share the shape `12-02` established for the read, and it is the shape that matters here:
**`RequirePlatformOwner` on the route is the entire access-control story, and the handlers make no
second check.** They carry no `OperatorId`, call no `IPermissionChecker`, and structurally cannot -
the authorizing fact is a realm-role claim and `Ago.Chat.Application` has no port that sees claims
(`adr/0032`). A route mapped with a weaker policy is therefore not a degraded check but no check.

Two consequences worth stating where the model lives rather than only in the ADRs:

- **The `SiteId` these three act on is chosen by the caller**, not resolved from the token. That is
  the definition of the actor and the whole of its risk; `tenant-isolation.md` lists all four in one
  place for that reason.
- **The module grant additionally requires the deployment-wide provisioning secret** in its body
  (`adr/0095`). So the realm role alone is not sufficient authority in practice, though the role's
  name reads as though it were.

## The tokens themselves: reviewed once, deliberately, in `17-06`

**Shipped in `17-06`** (`adr/0034`). Everything above is about what a validated token is trusted to
assert. This section is about the tokens themselves — how long they last, what protects the accounts
behind them, and whether the two kinds can be confused for one another. Read `adr/0034` for the
reasoning behind each number; only the facts are stated here.

**The realm's login-security policy is now chosen, not inherited.** Brute-force protection is on with
ten failures and a temporary, self-clearing lockout (never permanent — on a realm with open
self-registration, permanent lockout would be a denial-of-service handed to anyone who can guess a
username). The password policy states a 12-character minimum and forbids the username and email as
passwords, with no composition rules. TOTP parameters are set but no required action forces enrolment:
**there is no mandatory second factor**, and the trigger that would change that is the first account
in this realm that is not a demo account. Every value lives in both realm-import files this project
maintains and is verified against a running Keycloak by `RealmLoginSecurityTests`, which drives a real
failed-login sequence rather than reading the file back.

**Keycloak's operator-side lifetimes are set explicitly**: a 5-minute access token behind a 4-hour
idle / 12-hour maximum SSO session — short credential, long session, which is what a console someone
sits in all day needs. Keycloak has no separate refresh-token lifetime for standard sessions; the SSO
session *is* it.

**The visitor token's lifetime became a decision here, and the decision has since changed.** `17-06`
left it at 30 days and said why the number could not simply be lowered: it was a product promise (how
long a returning visitor still sees their own conversation) more than a security parameter, because
`POST /api/v1/visitor-sessions` is public and unauthenticated by design — anyone who can read a token
off a page can mint a fresh one — and the widget had no renewal path, so a shorter lifetime would only
have broken returning visitors sooner. **It is 7 days now** (`17-07`+`17-08`, `adr/0048`); the section
below is what changed and why that reasoning no longer blocks it.

**Visitor sessions have no revocation, by decision.** Not a deny-list, not a shorter-lived token with
server-side state. There is no caller: nothing in this system can currently decide that one visitor
token should stop working. Global revocation exists (rotating the visitor signing key — `17-03`), and
a per-token deny-list would additionally make an authentication decision depend on Redis, which
`adr/0009` forbids as a source of truth. The trigger that would change this is the first "end this
session" surface, visitor- or operator-facing.

**The visitor signing key is rotatable without a mass logout since `17-03`/`adr/0067`, and that
changes the sentence above.** `Ago.Chat.Api` accepts a *set* of signing keys while issuing with
exactly one; a key is retired by giving it a date, stays in the validation set for a configured drain
window (defaulting to the token's own seven-day lifetime), and leaves it on its own after that with no
restart. So an ordinary rotation is now invisible to every visitor, and "rotating the key invalidates
every token" is no longer automatic — it is what the operator gets by choosing a retirement date
already in the past, which is exactly what the leak procedure in `runbooks/secret-rotation.md` tells
them to do for a key known to be compromised, and nothing else. Global revocation therefore still
exists; it stopped being the unavoidable side effect of maintenance and became a deliberate lever.

**The two schemes genuinely cannot be substituted for one another, and this is now tested rather than
inferred** (`TokenSchemeSeparationTests`): a real visitor token gets `401` on an operator route — not
`403`, meaning it never authenticated at all — and a real Keycloak operator token gets `401` on a
visitor route. On the shared attachment route (`5-03`) each is classified as its own kind.

The review did find a **third** state that route had no answer for, and it is worth recording as a
correction to the sentence this document used to imply: "not an operator" was read as "therefore a
visitor". A signature-valid Keycloak token whose `sub` matches no `operators` row is neither, and
since `10-01` anyone can create one through the public registration form. It was mis-classified as a
visitor whose id was Keycloak's own `sub`; **nothing was reachable through it**, because the
participant checks inside every handler on that route compare that id against the conversation's real
visitor. `17-06` closed it at the policy layer — the route now requires the `kind` claim to be one of
two known values, so the third state is a clean `403` before any handler runs. `12-01`'s
platform-owner token lands there too, which is correct: an owner is not a party to any conversation.

**Registration abuse still has no CAPTCHA, by decision** (`10-01` deferred it; `adr/0034` answers it).
The brute-force settings above are explicitly *not* the answer — they protect existing accounts from
password guessing and do nothing about account creation. What bounds it today is that a registered
account cannot finish email verification while the realm has no SMTP server (`10-05`), so it can never
reach `10-02`'s bootstrap endpoint and never becomes a tenant. The trigger is the day that stops being
true.

## The visitor token renews, and lasts seven days: shipped in `17-07` and `17-08`

**Shipped in `17-07`** (the widget half) **and `17-08`** (the `Ago.Chat.Api` half), `adr/0048`. Read
the ADR for the reasoning; only the facts are here.

**`JwtTokenService.VisitorTokenLifetime` is `TimeSpan.FromDays(7)`**, sliding, with **no absolute
cap**. Every renewal issues a full fresh seven days, so a visitor who keeps returning never expires
and one who stays away for a week does — visibly, with a system note in the panel, rather than
silently. `adr/0048` records the trigger that would add a cap: the first time a visitor can
re-identify themselves without holding the original token. **`17-03`'s key-rotation drain window is
derived from this number and is therefore seven days, not thirty.**

The renewal path is **`POST /api/v1/visitor-sessions/renew`**, and it is the first
credential-issuing endpoint in this system that is itself authenticated:

- **Visitor scheme.** `sub` and `site_id` come from the validated principal, **never from the body** —
  taking either from the body would turn this into the public mint with someone else's identity
  attached. The scheme is the whole authorization story; there is no policy on top, because the
  Visitor scheme issues exactly one kind of token (unlike `5-03`'s shared attachment route, which
  needs `AuthorizationPolicies.EitherTokenKind`'s `kind` requirement precisely because it accepts
  two).
- **A second endpoint, not a flag on the mint.** A `renew: true` body field would have made one route
  public-unauthenticated and authenticated at once, with a different rate-limit key and a different
  success status on each path.
- **The body carries the site's public key**, resolved through the same cached
  `GetSiteConfigByPublicKeyHandler` the mint uses, and **a resolved `SiteId` that does not equal the
  token's claim is `403`.** That check is the tenant-isolation half of this endpoint and it belongs
  with the ownership comparisons the section below is about: the scheme proves *which visitor*, and
  only this comparison proves *which site's key they presented*. Origin is checked afterwards, the
  same `5-01` layer 2 the mint applies. An unknown public key is `404`, deliberately matching the
  mint rather than `403` — `ago-widget` reads `401`/`403` as "this identity is finished" and
  everything else as transient, so a `403` there would end the session of every visitor on a site
  whose key had merely been rotated.
- **Rate-limited per visitor** (`visitor-session-renew:visitor:{visitorId}`), not per site as the
  mint is — the mint has no visitor identity to key on, which is the point of the call, while renewal
  does. `429` carries `Retry-After`. Both halves are tested: that the bucket limits, and that it is
  keyed per visitor, so one abusive token-holder cannot exhaust a bucket shared with an entire site
  (`VisitorSessionRenewalTests`).

**This is not a revocation mechanism and does not reopen that decision** — the section above still
holds. What a shorter lifetime buys is a smaller window, not an eviction: the minting endpoint is
still public, so an attacker who read a token off a page can mint their own at any time. What it
genuinely bounds is one visitor's own transcript staying reachable from a shared or lost device, and
how long a token outlives the key that signed it.

## Tenant isolation: classified, guarded, and one hole closed - `17-01`

Everything above answers "may this operator do X". This section is about the question next to it -
"may they do X **to that tenant's data**" - and it is the one this document previously left implicit.

**The classification is `tenant-isolation.md`**, a sibling file, and it is where to go for detail and
for the current counts - this paragraph's own entry-point/route/read-model figures have drifted from
that file's headline table before (`tenant-isolation.md`'s own repeated "re-derived" notes are the
record of that), so treat the numbers there as authoritative over anything restated here. What is
still worth stating in this document specifically: since `23-14`, **two** queries in the codebase read
across tenants - `12-02`'s owner overview and `23-14`'s per-tenant detail behind it - not one; both are
reached only through `12-01`'s `RequirePlatformOwner` policy, never through `IPermissionChecker`.

**`17-01` found a real cross-tenant hole, and it is worth recording as a correction to what this
document used to imply.** The sentence "`site_id` scoping is the one piece already load-bearing
everywhere" was read - reasonably - as "the boundary is complete, only the proof is missing." It was
not. `AssignConversationHandler` checked `conversation:assign` for the site on the caller's own token
and then assigned whatever conversation id it was handed, never comparing the two, so an operator of
one site could claim a *waiting* conversation belonging to another and then pass every downstream
check legitimately - history, sending as that tenant's operator, closing, attachments, presence - all
of which gate on being the conversation's assigned operator and nothing else. Fixed by one
belongs-to-site comparison in that handler, returning `NotFound` rather than `Forbidden` (another
tenant's row must be indistinguishable from a nonexistent one, matching `DeleteAttachmentHandler` and
`RevokeWebhookEndpointHandler`).

The lesson is specific and it changes how the model should be read: **`IPermissionChecker` answers
half the question.** It proves the caller may act on a site they named; it says nothing about whether
the object they then loaded by id belongs to that site. `adr/0016` always drew that line - "RBAC
answers may this operator act at all, a per-conversation comparison answers on this one" - but the
second half had no systematic accounting until now, which is exactly how one handler came to be
missing it.

**A guard now exists**, `Ago.Chat.Architecture.Tests.TenantScopeTests`, in the same spirit as `0-02`'s
layering tests: every use case must take a `SiteId` and check `IPermissionChecker`, or appear in an
explicit exemption list with a stated reason - and the list is checked in both directions, so a stale
exemption fails as loudly as a missing one. Its own limit is stated plainly because it matters here:
it detects a *missing* check, never a check made against the wrong site. `17-01`'s finding would not
have tripped it. Ownership comparisons are covered by tests, one per branch, not by a rule.

## A new way to read someone else's conversation: shipped in `18-07`

Every ownership comparison described above answers "is this operator a party to *this*
conversation." `18-07`'s returning-visitor-history panel introduces the first exception:
`GetVisitorHistoryHandler.HandleHistoricalConversationAsOperatorAsync` lets an operator read a past,
`Closed` conversation's message history by proving they are assigned to a *different*, live
conversation with the *same visitor* — comparing `Conversation.VisitorId` on both rows, not an
assignment on the historical one, which the requesting operator may never have held.

This is deliberate, not a gap the guard above missed: the historical conversation's own
`Conversation.OperatorId` is frozen at whichever operator last held it (`Close` never clears it), so
reusing `GetConversationHistoryHandler`'s ordinary `conversation.OperatorId == RequestedBy` check
would mean only the operator who originally handled that exact past conversation could ever revisit
it — defeating the feature's own purpose. The two-check shape survives unchanged
(`GetVisitorHistoryHandler.HandleAsOperatorAsync`'s own remarks): `IPermissionChecker` still answers
"may this operator read conversations at all for this site" first, and this new comparison is what
"may this operator read *this* one" means for a historical row specifically.

**Consequence for `personal-data.md`**: a message becomes visible to an operator who was never a
party to the conversation containing it, for the first time in this codebase — see that document's
own note on `18-07` for what this changes about `messages.body`'s exposure.

## Seat assignment blocks sign-in with no new policy code: shipped in `13-03`

`OperatorIdentityClaimsTransformation` needed no code change at all to gain a new sign-in-blocking
behaviour — the two queries `ResolveOperatorIdentityHandler` resolves a signed-in principal's `sub`
through (`IOperatorRepository.GetByExternalSubjectIdAndSiteIdAsync`, the `RequestedSiteId`-present path
`adr/0068` added, and `ListByExternalSubjectIdAsync`, the `RequestedSiteId`-absent path) now both filter
on `HoldsSeat AND RemovedAt IS NULL`. A real `operators` row whose `HoldsSeat` is `false`, or whose
`RemovedAt` is set, now resolves to no row at all from either query — which `ResolveOperatorIdentityHandler`
already turns into "no `OperatorId`/`SiteId` claim added", the exact same shape `RequireOperatorIdentity`'s
`RequireClaim` check already refuses for a `sub` matching no `operators` row whatsoever.

In other words: this is not a third gate added above the existing two-actor resolution path, it is the
same resolution path now answering "no" for two more real situations (a seat toggled off, an operator
removed) that could not previously arise, because nothing before `13-03` ever gave `operators` a row
either fact to record. Proven with a real Keycloak-issued token against the real resolution path
(`OperatorSeatAssignmentAuthenticationTests`, `Ago.Chat.Integration.Tests`): a token that resolves an
operator successfully, then — after the same row's `HoldsSeat` is toggled off, or the row is removed,
with no new token issued — is refused `403` on its very next request, exactly as
`KeycloakUserWithNoMatchingOperatorRow_IsRejected` already proves for an identity with no `operators`
row at all.

## Where this is going: one role catalogue, decided in `adr/0093`

**The section below is the record of how the two-product answer worked, and it is being superseded
rather than corrected.** `adr/0093` (2026-09-03, Stage 22) decided that tenancy, identity and the role
catalogue unify across products while the domains stay apart. So the shape `20-08` built - a real
Calendar `Operator` row, invited by email, linked on first authentication - is the *last* thing built
on the per-product identity model, not the pattern to copy.

What changes for this file:

- **One role catalogue, on the account side.** The two permission vocabularies are disjoint by prefix
  (`booking:*`, `calendar:*`, `customer:*` against `conversation:*`, `site:*`), so one catalogue
  carries both without renaming anything. `adr/0027`'s "two RBAC vocabularies from day one" is the
  clause that goes.
- **A product holds no `operators` table.** `ago-faq` (`19-03`) already has none - it scopes by the
  chat `SiteId` and gates its console screens on chat's own permissions. AGO Calendar is the outlier.
- **A product reads permissions from a projection in its own database**, replicated over the outbox -
  never from a token claim. Rule 8 forbids a write decision reading a cache, and a revoked permission
  carried in a claim would outlive its revocation. This is the same shape `adr/0016` already uses on
  the chat side, applied a second time.
- **The open item this file has carried** - "the management surface for custom per-tenant roles" - is
  now one surface for every product rather than one per product.

**What does not change**: `adr/0016`'s RBAC model, `adr/0032`'s platform-owner boundary,
`adr/0022`'s claims-transformation shape, and both refusals stated at the end of the next section. An
action from a subject with no authorization is still refused rather than auto-provisioned, and that
property is what the projection has to preserve rather than replace.

**Shipped for AGO Calendar in `22-05` (2026-09-03).** The projection exists, the calendar's own
`operators`/`roles`/`operator_roles` are gone, and `PermissionChecker` reads
`role_assignment_projections`.

**The staleness this buys is a security property, so it is stated as a number rather than left as
"eventually".** A revocation takes effect once chat's outbox dispatcher has published it, the broker
has delivered it and the consumer has committed: **sub-second in the ordinary case, bounded above by
five seconds** by `OutboxDispatcherOptions.PollInterval`, the fallback for a missed `LISTEN`/`NOTIFY`.
That is not a new latency source — it is what this path already guaranteed for every other event on
it — and the permission check itself adds no window of its own: there is no cache in front of it, so
the request after the projection commits is already refused.

Compare what the rejected alternative would have cost. Permissions carried as token claims would be
stale for the **whole lifetime of the token**, with no upper bound anyone could shorten without
reissuing, which is precisely rule 8's "never cache what a write decision depends on".

Until the rest of Stage 22 lands, everything below is what is true in the code.

## A second product asks this file a question: shipped in `20-08`

**The first time an authorization question here spanned two products.** `adr/0065` promises a chat
operator may intervene in a booking a visitor started inside a conversation; `adr/0027` says AGO
Calendar defines its own `Operator`, never the same row as `Ago.Chat.Domain.Operator`, the two unified
only through Keycloak. Together they left one thing unanswered: a chat operator acting on a booking card
is, to Calendar, a `sub` with no `operators` row.

**Answered by applying `adr/0027`'s own mechanism a second time rather than amending it** (`adr/0088`):
that person becomes a real Calendar `Operator`, created deliberately in advance by the tenant — invited
by name and email from the Access screen `20-12` built — and resolved from the same Keycloak identity
they already sign in with. Calendar's own `OperatorIdentityClaimsTransformation` gained one fallback:
when a `sub` matches no operator, match the token's email claim against not-yet-linked invited rows and
call the existing `LinkExternalIdentity`.

**What this file's existing rules gave for free, and what had to be new.** Nothing about the RBAC model
(`adr/0016`), the platform-owner boundary (`adr/0032`) or the claims-transformation shape (`adr/0022`)
changed — Calendar's copy of that shape simply resolves one more way. What is genuinely new is a
narrower *identity* state than this file previously described: an operator row that exists, holds roles,
and is not yet attached to any authenticated principal.

**Two refusals worth stating here rather than only in the ADR**, because both are authorization
properties and this is the file that collects them:

- **An action from a `sub` with no operator row is refused, never auto-provisioned.** Linking happens on
  authentication, never on acting. A booking action from an unknown subject produces no claim, no
  exception, and a `403` — the same shape `KeycloakUserWithNoMatchingOperatorRow_IsRejected` already
  establishes on Chat's side, now holding for a cross-product action too.
- **An ambiguous email match is refused, not resolved cleverly.** Two invited rows sharing an address
  link neither. An already-linked operator can never be a candidate (the query filters
  `external_subject_id IS NULL`). A `sub` once bound can never be re-bound, because the direct subject
  lookup always runs first.

## A caller may now name a tenant, and it is an ordinary operator who does it: shipped in `22-14`

`adr/0100`. Until this item, every `tenant_id` on an `Ago.Calendar.Api` principal was server-derived
in the strongest sense: `OperatorIdentityClaimsTransformation` read the projection `22-05`/`adr/0093`
replicates and the caller had no way to influence the answer. That property held because a subject
resolved to exactly one tenant or to none.

**`22-05` made "one subject, two tenants" ordinary, and the refusal it produced was
indistinguishable from having no grant at all.** Two projection rows means no honest answer to "which
one", so no claim was added, so `calendar-operator` refused — and the console renders "refused" and
"never granted" identically (`19-03`). A real person with a real grant saw an empty product.

**The answer is the one this file's own `13-07`/`adr/0068` precedent already established for
`ago-chat`, applied a second time rather than reinvented**: the console names the tenant in the
`X-Ago-Active-Site` header, and the same read that establishes the grant is the one that verifies the
name — `IRoleAssignmentProjectionStore.ResolveTenantAsync` returns a requested tenant only when
`(operator_id, tenant_id)` is in its own `WHERE` clause. The claim is still something the database
said; what the caller chose is *which* of several server-known tenants, never *whether*.

**Three refusals worth stating here rather than only in the ADR**, in the same spirit as `20-08`'s two
above:

- **A named tenant this operator holds nothing in is refused, and never fallen back to one they do
  hold.** "You asked for A, here is B" would be a cross-tenant misdirection dressed as helpfulness.
  The refusal is the policy's bare `403`, before any handler runs — asserted on the empty response
  body, because `IPermissionChecker` would independently refuse a moment later and a status-only
  assertion could not tell the two apart.
- **A malformed header names nothing, so it selects nothing** and the ordinary single-tenancy
  resolution applies. Deliberately different from the previous bullet, and deliberately different from
  `ago-chat`, whose own transformation treats *any* unrecognised signal as "not asked" — there,
  ignoring it can only fail to narrow; here it would fall through to a tenancy the caller did not ask
  for.
- **One route in this product is answerable with no tenant resolved**: `GET /api/v1/me/tenancies`,
  under a new `calendar-identity` policy that requires authentication and nothing else. It exists
  because a two-tenancy identity cannot satisfy `calendar-operator` until it names one, so the
  stricter gate would refuse the very read that says what there is to name. It takes no tenant from
  the caller at all — the operator id comes from the token's own `sub`.

**What this costs, recorded here because it is an authorization property and not an implementation
detail**: `Ago.Calendar.Api` now belongs in `tenant-isolation.md`'s caller-chosen-tenant category,
whose previous four members were all the platform owner's. One method carries a property the rest of
the product got by construction.

## A caller learns what their own tenant has, not only what they hold: shipped in `23-21`

Everything above answers "may this operator do X" or "may they do X to that tenant's data". This
item answers a third, narrower question the console needed and had no honest way to answer:
*does my own tenant have X at all* - a fact independent of whether the caller personally holds the
permission for it.

**The defect this closes, restated from `flows.md` 4.3**: the console drew a permission-gated nav
item when `hasPermission(...)` was true and drew nothing when it was false, so *not entitled* and
*does not exist for this tenant* rendered identically - the same shape `22-14` found for the
calendar tenancy switcher, generalised. A person who cannot tell which of the two they are in has no
next action: they cannot ask for a grant they do not know exists.

**The fix is one widened response, never a merged one.** `GET /api/v1/operators/me`
(`OperatorPermissionsResponse`) now carries a second, separate list - `EnabledModules`, the raw
`ModuleKey` values `20-07`'s registry has enabled for the caller's own site - beside `Permissions`,
never folded into it. Read through the identical `IEnabledModuleReadStore.GetForSiteAsync` port
`23-01`'s `ListEnabledModulesForSiteHandler` already uses for the site-scoped `/sites/{siteId}/modules`
route, but reached with no permission check of its own: `GetMyPermissionsHandler` is never handed a
caller-chosen `siteId` to check in the first place, only the operator claim already resolved onto the
request, so there is nothing to gate that is not already gated by `RequireOperatorIdentity`. This is
deliberate, not an oversight parallel to `23-01`'s own fix: the entire reason this list needed a home
outside the `site:configure`-gated route is that the audience it exists for - an operator who lacks
`site:configure`, possibly lacks every permission on the calendar module too - could never reach that
route to find out. `tenant-isolation.md`'s own row for this handler has the detail.

**`ago-console` renders the difference, not merely receives it.** `consoleNav.ts`'s calendar block
now checks `EnabledModules` before deciding whether to show a nav entry at all when the caller lacks
`calendar:configure`: nothing, when the tenant itself has no calendar module (the entry would be a
capability no colleague at that tenant could ever grant - showing it anyway is the over-disclosure
`flows.md` 4.3 warns against, a price list of another tenant's plan); one entry, leading to a refusal
that says which colleague can grant it, when the tenant does have the module and this operator simply
does not hold it yet. The page-level refusal itself is a shared function
(`src/calendar/calendarAccess.tsx`) rather than the seven hand-copied blocks that existed before -
built from the console's existing eleven-component set (`adr/0030`), no new component added.

**Generalised to the other two gates by `23-24`** (`docs/design/decisions.md` §10). `site:configure`
and `site:erase` never have the third, "the tenant does not have this at all" state
`EnabledModules` exists to distinguish - every tenant's own owner already holds both, by
construction - so their nav entries are simply always drawn, muted (not absent, not `disabled`) when
the caller lacks the permission. The calendar's one grantable-but-lacking entry is muted the same
way, so all three gates read as one visual treatment rather than the calendar looking different from
the rest. `src/shell/accessRefusal.tsx`'s `AccessRefusal` is the same consolidation
`calendarAccess.tsx` did for the calendar's seven screens, now shared by the fourteen screens gated
on `site:configure`/`site:erase`, and `calendarAccess.tsx`'s own "forbidden" branch delegates to it
rather than carrying a second copy. `adr/0030` gained a second amendment for the one glyph this
needed - a lock, inline SVG, beside a muted entry - and `docs/design/gaps.md` records the icon
question it answers as answered narrowly, not closed to a general position.

## Done when nothing here is open anymore

- [x] An ADR chooses the authorization model - `adr/0016`, RBAC.
- [x] An ADR confirms the OIDC direction for operators - `adr/0022`, Keycloak (`5-05`).
- [x] `realtime.md` updated to state the shipped mechanism as fact (`1-06`, `5-05`). `vision.md` did
      not need a change - it never described an authorization model to begin with.
- [x] The admin/supervisor role and `attachment:delete` ship - `5-08`, above.
- [x] An ADR decides how a caller that is not scoped to any site is represented - `adr/0032`, a
      Keycloak realm role, outside the RBAC model rather than a wildcard inside it (`12-01`).
- [x] Every token lifetime and the realm's own login-security policy are values somebody chose -
      `adr/0034` (`17-06`), including the two answers that are "no" (per-visitor-token revocation, and
      a registration CAPTCHA), each with the trigger that would reopen it.
- [x] The one lifetime `adr/0034` could not set to the number it wanted is set to it - `adr/0048`,
      seven days plus a renewal path (`17-07` the widget, `17-08` the endpoint), so "how long one
      token stays useful" and "how long a returning visitor keeps their history" stopped being the
      same number.
