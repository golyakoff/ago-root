# Tenant isolation: the classification

`vision.md`'s loudest claim is "every piece of data is scoped by `site_id`; this is a multi-tenant
system from day one." This file is the evidence behind it: **every use case, every route and every
read-model query in `ago-chat`, classified by where its `site_id` comes from and what stops a caller
reaching another tenant's copy.**

It exists because an audit nobody can find later is an audit that will be run again (`17-01`).
Read `authorization.md` first for the RBAC model and the four actors — this file assumes it and
answers a narrower question: *not* "may this operator do X", but "may this operator do X **to that
tenant's data**".

## Headline numbers

| | |
|---|---|
| Use-case entry points in `Ago.Chat.Application` | **37**, across 31 `*Handler` classes |
| RBAC-gated: takes a `SiteId` and checks `IPermissionChecker` | **21** |
| Deliberately not RBAC-gated, each with a stated reason | **16** |
| HTTP routes and hub methods that carry tenant data | **21** |
| Routes taking a **client-supplied** `siteId` | **6** — two route groups, both permission-gated |
| Read-model queries | **5**, in three read stores |
| Genuinely cross-tenant reads in the whole codebase | **1** (`12-02`'s owner overview) |

The 21/16 split is not prose — it is enforced. `Ago.Chat.Architecture.Tests.TenantScopeTests` walks
the IL of every handler and fails the build unless each entry point is either RBAC-gated or listed in
`TenantScopeExemptions` with a reason. The counts above are what that scan reports.

## The three places a `site_id` can come from

Everything below reduces to this. A tenant boundary is only as good as the provenance of the value it
compares against.

1. **A server-derived claim.** `ClaimsPrincipalExtensions.GetSiteId()`, populated by
   `OperatorIdentityClaimsTransformation` from the `operators` row that the validated Keycloak `sub`
   resolves to (`5-05`, `adr/0022`). The caller cannot name a site here — cross-tenant access is
   impossible by construction, not by check. Most operator routes work this way.
2. **A signed visitor token.** `AuthEndpoints` mints `(visitorId, siteId)` together and signs them,
   so the pairing is not forgeable either. Same property as (1), different issuer.
3. **The client, in a route segment.** Exactly two route groups —
   `/api/v1/sites/{siteId}/widget-config` and `/api/v1/sites/{siteId}/webhooks/...`. This is
   deliberate and documented in the code: an operator's own site claim is not necessarily the site
   being configured. **On these routes the permission check is the entire defence**, which is why
   `CrossTenantRouteIsolationTests` exercises them over real HTTP with a real Keycloak token and the
   real `PermissionChecker`, rather than at the handler level with a fake.
4. **Nowhere — deliberately.** `GET /api/v1/owner/sites` (`12-02`) has no `site_id` at all. See
   *The one cross-tenant read* below.

## The three kinds of gate

- **Permission check** — `IPermissionChecker.HasPermissionAsync(operatorId, siteId, permission)`,
  whose Postgres implementation filters roles by `r.SiteId == siteId`. Answers "may this operator act
  on this site at all" (`adr/0016`).
- **Participant or ownership check** — a comparison against the object itself:
  `conversation.VisitorId == caller`, `conversation.OperatorId == caller`,
  `attachment.SiteId == command.SiteId`, `endpoint.SiteId == query.SiteId`. Answers "on *this*
  object". `adr/0016` draws the line: RBAC answers the first question, the aggregate the second.
- **Deliberately none** — and then the reason must be one of: the input came from the system's own
  broker, the data is public by design, the caller identity does not exist yet, or a policy at the
  HTTP edge already decided (exactly once, for the platform owner).

Most operator paths use **both** of the first two. That is not redundancy: the permission check is
scoped to a site the caller named, and only the ownership check ties the object to that site.

## Use cases

Grouped by gate. The full machine-checked list lives in
`ago-chat/tests/Ago.Chat.Architecture.Tests/TenantScopeExemptions.cs`; this table is the same
information organised for a reader.

### RBAC-gated (21)

Every one takes a `SiteId` and calls `IPermissionChecker` before doing anything else.

| Use case | `siteId` from | Permission | Additional ownership check |
|---|---|---|---|
| `AssignConversationHandler` | operator claim (hub) | `conversation:assign` | **`conversation.SiteId == command.SiteId`** — added by `17-01`, see *The finding* |
| `CloseConversationHandler` | operator claim | `conversation:close` | `conversation.OperatorId == caller` |
| `MarkConversationReadHandler` | operator claim | `conversation:read` | `Conversation.MarkReadByOperator` throws on a non-assigned caller |
| `SendOperatorMessageHandler` | operator claim | `conversation:send` | `Conversation.AddOperatorMessage`, inside the pipeline worker |
| `GetConversationHistoryHandler.HandleAsOperatorAsync` | operator claim | `conversation:read` | `conversation.OperatorId == caller` |
| `GetConversationHistoryHandler.HandleDeltaAsOperatorAsync` | operator claim | `conversation:read` | `conversation.OperatorId == caller` |
| `GetVisitorPresenceHandler` | operator claim | `conversation:read` | `conversation.OperatorId == caller` |
| `GetOperatorQueueHandler` | operator claim | `conversation:read` | n/a — reads are keyed by site and by the caller's own id |
| `GetAllConversationsForSiteHandler` | operator claim | `site:configure` | n/a — the read store filters `site_id` |
| `GetMyPermissionsHandler` | operator claim | *(reads the granted set for the caller's own pair)* | n/a — answers only about the caller |
| `CreateAttachmentHandler.HandleAsOperatorAsync` | operator claim | `conversation:send` | `conversation.OperatorId == caller` |
| `ConfirmAttachmentHandler.HandleAsOperatorAsync` | operator claim | `conversation:send` | `conversation.OperatorId == caller` |
| `GetAttachmentDownloadUrlHandler.HandleAsOperatorAsync` | operator claim | `conversation:read` | `conversation.OperatorId == caller` |
| `DeleteAttachmentHandler` | operator claim | `attachment:delete` | `attachment.SiteId == command.SiteId` |
| `GetWidgetConfigHandler` | **route segment** | `site:configure` | n/a — the site *is* the object |
| `UpdateWidgetConfigHandler` | **route segment** | `site:configure` | n/a — the site *is* the object |
| `RegisterWebhookEndpointHandler` | **route segment** | `webhook:manage` | n/a — creates a row for that site |
| `ListWebhookEndpointsHandler` | **route segment** | `webhook:manage` | n/a — loads by site |
| `RevokeWebhookEndpointHandler` | **route segment** | `webhook:manage` | `endpoint.SiteId == command.SiteId` |
| `GetWebhookDeliveriesHandler` | **route segment** | `webhook:manage` | `endpoint.SiteId == query.SiteId` |
| *(the two `GetConversationHistory` operator entry points are counted separately above)* | | | |

### Not RBAC-gated, with the reason (16)

**Visitor paths (7).** A visitor is outside the role system entirely (`adr/0016`), so there is nothing
to ask `IPermissionChecker`. What replaces it is *narrower* than a site check: the handler compares
the caller's `VisitorId` — from the signed token, never from the request — against
`conversation.VisitorId`. Being the visitor of a conversation implies being on its site; the converse
does not hold, which is why the participant comparison is the stronger of the two.

`ConfirmAttachmentHandler.HandleAsVisitorAsync`, `CreateAttachmentHandler.HandleAsVisitorAsync`,
`GetAttachmentDownloadUrlHandler.HandleAsVisitorAsync`,
`GetConversationHistoryHandler.HandleAsVisitorAsync`,
`GetConversationHistoryHandler.HandleDeltaAsVisitorAsync`, `SendVisitorMessageHandler`,
`StartConversationHandler`.

`StartConversationHandler` is the special one: it is where the pairing every other visitor check
relies on is *created*, from a token that already carries both ids. There is no prior object to check
ownership of.

**Public, pre-authentication surface (4).** These serve a site's *public* configuration — the same
values any visitor's browser is handed during the widget handshake — so there is no tenant secret to
leak and, in most cases, no principal yet to check anything for.

- `CheckCorsOriginHandler` — deliberately cross-tenant and unauthenticated, answering only "does *any*
  site allow this origin", which is layer 1 of `5-01`'s CORS design. Never the per-site origin check.
- `GetSiteConfigByPublicKeyHandler` — the widget handshake, keyed by a public key that
  `api-design.md` states is not a secret.
- `GetSiteConfigByIdHandler` — takes a `SiteId` but is never reachable with a caller-supplied one:
  its only callers are `HubOriginValidator` on both hubs, passing the connection's own validated
  claim, and no route maps it.
- `RegisterSiteHandler` — creates the tenant, so there is no site to be scoped to. Gated instead by
  `10-01`'s `RequireKeycloakIdentity` plus one-registration-per-subject, enforced by a unique index
  inside the registration transaction.

**Consumer and worker side (4).** No external caller reaches these. The input is an integration event
this system itself published, so the site is a fact already established by the write that raised it.

`DispatchWebhooksForEventHandler`, `RecordUnreadMessageHandler`,
`ResolveConversationAssignmentTargetsHandler`, `ResolveMessageDeliveryTargetsHandler`,
`ResolveOperatorIdentityHandler` — the last of which is what *produces* the `OperatorId`/`SiteId`
claims every gated handler then trusts, and so cannot itself depend on them.

**The one cross-tenant read (1).** `ListSitesForOwnerHandler`, `12-02`'s platform-owner overview. It
carries no `SiteId` **because** it is cross-tenant. The whole access-control story is `12-01`'s
`RequirePlatformOwner` policy on `GET /api/v1/owner/sites`: the authorizing fact is a Keycloak realm
role (`adr/0032`), and `Ago.Chat.Application` has no port that sees claims — re-checking in the
handler would be a second, weaker copy of the same rule, free to drift from the first. Read-only; no
owner write surface exists anywhere.

Since `12-05` this is the **one place in the codebase where a caller's own `site_id` must be
ignored**, and the reason is worth stating where the rule lives. The platform owner may now hold an
`operators` row of their own, so their token resolves an `operator_id`/`site_id` like anybody's, and
every request they make — this one included — arrives carrying one. Scoping this read to it would not
error; it would return a **shorter list of tenants**, which reads exactly like a platform with fewer
tenants. `Ago.Chat.Integration.Tests.PlatformOwnerAsTenantTests` asserts the whole result contains a
tenant the caller has no `operators` row in, which is the only shape of the claim that can fail.

This entry is the reason the guard is shaped the way it is. A rule that only inspected
`SiteId`-carrying inputs would never have looked at this handler at all — the absence of a `SiteId`
is exactly what makes it interesting. See *The guard* below.

## Routes and hub methods

| Surface | Auth | `siteId` source |
|---|---|---|
| `POST /api/v1/visitor-sessions` | anonymous | n/a — resolved from the public key, and this is what *issues* the pairing |
| `POST /api/v1/visitor-sessions/renew` | Visitor scheme | visitor claim — **and** the request's own public key must resolve to the *same* site, else `403` (`17-08`, `adr/0048`). The only route where the two `siteId` sources are compared rather than one being trusted |
| `POST /api/v1/sites` | `RequireKeycloakIdentity` — `12-04` added a `NotThePlatformOwner` policy here and `12-05` withdrew it (`adr/0063`'s amendment); the platform owner may register a tenant of their own | n/a — creates the tenant |
| `GET /api/v1/conversations/queue` | `RequireOperatorIdentity` | operator claim |
| `GET /api/v1/conversations/all` | `RequireOperatorIdentity` | operator claim |
| `POST /api/v1/conversations/{id}/close` | `RequireOperatorIdentity` | operator claim |
| `POST /api/v1/conversations/{id}/read` | `RequireOperatorIdentity` | operator claim |
| `GET /api/v1/operators/me` | `RequireOperatorIdentity` | operator claim |
| `POST /api/v1/conversations/{id}/attachments` | `EitherTokenKind` | operator claim, or the visitor token |
| `POST /api/v1/attachments/{id}/confirm` | `EitherTokenKind` | operator claim, or the visitor token |
| `GET /api/v1/attachments/{id}` | `EitherTokenKind` | operator claim, or the visitor token |
| `DELETE /api/v1/attachments/{id}` | `RequireOperatorIdentity` | operator claim |
| `GET`/`PUT /api/v1/sites/{siteId}/widget-config` | `RequireOperatorIdentity` | **client-supplied** |
| `POST`/`GET /api/v1/sites/{siteId}/webhooks` | `RequireOperatorIdentity` | **client-supplied** |
| `DELETE /api/v1/sites/{siteId}/webhooks/{id}` | `RequireOperatorIdentity` | **client-supplied** |
| `GET /api/v1/sites/{siteId}/webhooks/{id}/deliveries` | `RequireOperatorIdentity` | **client-supplied** |
| `GET /api/v1/owner/sites` | `RequirePlatformOwner` | none, deliberately |
| `/hubs/visitor` — `JoinAsync`, `SendMessageAsync`, `GetHistoryAsync` | Visitor scheme | signed visitor token |
| `/hubs/operator` — `JoinConversationAsync`, `SendMessageAsync`, `GetHistoryAsync`, `GetVisitorPresenceAsync` | `RequireOperatorIdentity` | operator claim |

Note the shape of the hub methods: they take a **conversation id**, not a site. That is why
`AssignConversationHandler` matters so much — see below.

## Read-model queries

`adr/0004` splits reads onto hand-written Dapper SQL, which is where a missing filter would be least
visible. Every query, and what scopes it:

| Query | Filter | What guarantees the scope |
|---|---|---|
| `ConversationReadStore.GetHistoryAsync` | `conversation_id` | `messages` carries no `site_id` (`data-model.md`) — the tenant is reachable only through `conversations`. `GetConversationHistoryHandler` has already proved the caller is the conversation's visitor or its assigned operator. |
| `ConversationReadStore.GetDeltaAsync` | `conversation_id` | Same handler, same two checks. |
| `ConversationReadStore.GetAllForSiteAsync` | **`site_id`** | Its input *is* a site; `GetAllConversationsForSiteHandler` gates it on `site:configure`. |
| `WebhookDeliveryReadStore.GetForEndpointAsync` | `endpoint_id` | `webhook_deliveries` has no `site_id` either. `GetWebhookDeliveriesHandler`'s `endpoint.SiteId != query.SiteId` branch is the whole of the isolation here — which is why `17-01` gave that branch a test that fails when it is removed. |
| `PlatformOverviewReadStore.ListSitesAsync` | **none, deliberately** | `12-02`. The `RequirePlatformOwner` policy, and nothing else. |

Each of these notes also lives in the read store's own remarks, so a reader who arrives at the SQL
rather than at this file finds the same answer.

## The finding: `17-01` closed a real cross-tenant hole

Recorded here rather than only in a commit message, because the *shape* of the mistake is the lesson.

`AssignConversationHandler` checked `conversation:assign` against the site on the caller's own token,
then assigned whatever conversation id it had been handed — and never compared the two. An operator of
site B could therefore claim any **`Waiting`** conversation of site A by id. Everything downstream then
followed legitimately, because every other operator-facing conversation path gates on
`conversation.OperatorId == caller` and nothing else: full message history, sending messages to that
visitor as site A's operator, closing the conversation, downloading its attachments, reading visitor
presence. The victim's own operators could no longer claim it, since it was no longer `Waiting`.

Two things about it are worth keeping:

- **The permission check was present and passed.** A guard that only asks "did this handler call
  `IPermissionChecker`" would not have caught it, and does not catch it today. Site scoping has two
  halves — *check the permission for a site*, and *prove the object belongs to that site* — and only
  the first half is mechanically detectable. The second is what the classification above is for.
- **The choke point was one handler, not twenty.** The fix is a single
  `conversation.SiteId != command.SiteId` comparison in `AssignConversationHandler`, returning
  `NotFound` (the same info-hiding shape `DeleteAttachmentHandler` and `RevokeWebhookEndpointHandler`
  already use — another tenant's row must be indistinguishable from a nonexistent one). It belongs
  there rather than in `Conversation.AssignTo`, because the aggregate's other two callers (the `4-02`
  and `4-03` assignment claimers) resolve their operator *from* the conversation's own site, so
  passing a site into the domain method would have them compare `conversation.SiteId` against itself —
  a guard that looks like one and can never fire. The handler is the only place where two
  independently-sourced facts meet.

The alternative considered and not taken: a site-scoped `IConversationRepository.GetByIdAsync(id,
siteId)`, so every operator-facing load is scoped by construction. It is the more systematic answer
and it is a real, larger change — it touches every conversation handler and has no meaning on the
visitor paths, whose commands carry no site. Named here for whoever revisits this, not built by
`17-01`.

## The guard

`Ago.Chat.Architecture.Tests.TenantScopeTests`, in the spirit of `0-02`: layering violations fail
automatically rather than relying on review, and so does this.

It reads the IL of every public entry point of every `*Handler` in `Ago.Chat.Application` — IL rather
than reflection, because an `async` method's body lives in a compiler-generated state machine, and
per-method rather than per-type, because several handlers pair a visitor entry point with an operator
one and only the latter checks anything. Each entry point must either take a `SiteId` and call
`IPermissionChecker`, or appear in `TenantScopeExemptions` with a reason.

Four properties are asserted:

1. Nothing is unaccounted for — every entry point is gated or exempt.
2. No exemption is stale — an entry naming a method that has since grown a real check, or been renamed
   or deleted, fails just as loudly as a missing one.
3. Every permission check is scoped to a site the entry point was actually given.
4. **The rule can fail.** A deliberately non-compliant handler is checked in
   (`Fixtures/TenantScopeRuleFixtures.cs`: takes a `SiteId`, loads a row by a caller-supplied id, never
   checks anything) next to a compliant twin, and a test asserts the rule flags exactly the first. A
   rule only ever observed passing is not evidence.

**Adding a use case?** Take a `SiteId` and check the permission, or add an entry to
`TenantScopeExemptions` saying what supplies the scope instead. There is no third option that builds.

## What this does not prove

Stated plainly, because a document like this is most dangerous when it is trusted past its evidence.

- **The guard does not detect a check against the wrong site.** It sees that
  `IPermissionChecker` was called, not what was compared afterwards. `17-01`'s own finding is the
  worked example. Ownership checks are covered by tests, one per branch, not by a rule.
- **Database-enforced tenancy (Postgres row-level security) does not exist here**, and nothing in this
  audit found a case the application layer cannot hold. It remains a real alternative design and a
  separate argument, deliberately out of `17-01`'s scope.
- **The `4-02`/`4-03` assignment claimers are site-scoped by construction** (they pick candidate
  operators from the conversation's own site) rather than by a check, and that construction is not
  itself guarded by a test in this family.
- Sites, operators and roles are seeded by `10-02`'s registration endpoint and by
  `deploy/seed/create-demo-tenant.sh`. Who may *grant* a role is still answered only by that script
  (`authorization.md`) — this document classifies enforcement, not administration.

## Where the proofs live

| Claim | Test |
|---|---|
| The permission checker really filters by site | `PermissionCheckerTests.HasPermissionAsync_WhenTheRoleIsForADifferentSite_ReturnsFalse` (real Postgres) |
| Client-supplied-`siteId` routes refuse another tenant, over real HTTP | `CrossTenantRouteIsolationTests` (real Keycloak, real Postgres, real endpoint mappings) |
| Another tenant's conversation cannot be claimed or read | `CrossTenantConversationAccessTests` (real Postgres, real `PermissionChecker`) |
| A visitor of one site cannot read another site's conversation | `CrossTenantConversationAccessTests.AVisitorOfAnotherSite_CannotReadTheConversation` |
| Belongs-to-site branches fail when removed | `GetWebhookDeliveriesHandlerTests`, `RevokeWebhookEndpointHandlerTests`, `DeleteAttachmentHandlerTests`, `AssignConversationHandlerTests` |
| The two token schemes cannot be substituted | `TokenSchemeSeparationTests` (`17-06`) |
| Only the platform owner reaches the cross-tenant read | `OwnerSitesEndpointTests` (`12-02`) |
| Every use case is gated or argued | `TenantScopeTests` |
