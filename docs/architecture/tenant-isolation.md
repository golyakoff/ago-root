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
| Use-case entry points in `Ago.Chat.Application` | **76**, across 69 `*Handler` classes |
| RBAC-gated: takes a `SiteId` and checks `IPermissionChecker` | **48** |
| Deliberately not RBAC-gated, each with a stated reason | **28** |
| HTTP routes and hub methods that carry tenant data | **64** |
| Routes taking a **client-supplied** `siteId` | **26** — eleven route groups, all permission-gated |
| Read-model queries | **7**, in three read stores |
| Genuinely cross-tenant reads in the whole codebase | **1** (`12-02`'s owner overview) |
| Genuinely cross-tenant **writes** | **3** — `14-12`'s owner unlink, and `22-17`'s owner module grant and revoke |

**The first three rows have not been re-derived since `14-04` and are known to be low.** There are
**103** `*Handler.cs` files under `Ago.Chat.Application/UseCases` on `main` as of 2026-09-04 against
the 69 classes recorded here; every stage since added entry points without re-running the scan. The
cross-tenant rows below them are maintained by hand and are current — they are short enough to be,
which is exactly why the long rows drifted and these did not. Only a re-scan fixes the top three,
and `22-19` is filed for it; until then read them as a floor, not a count.

**Re-derived in `14-04`**, from the scan itself rather than by adding a delta: the first three rows
had drifted (they read 37/21/16 across 31 handler classes, a count from before `12-04`/`12-05`/`14-06`
added entry points of their own). `14-04`'s own contribution is three of them — `GetOfflineAutoReply`
and `UpdateOfflineAutoReply`, both `site:configure`-gated, and `SendOfflineAutoReply`, a
`Ago.Chat.Worker` consumer exempt for the same reason `RecordUnreadMessageHandler` is — plus the
`GET`/`PUT /api/v1/sites/{siteId}/offline-auto-reply` pair, the third route group to take a
client-supplied `siteId`. The route and read-query rows below the first three are still hand-counted;
only this item's own two routes were added to them.

**Re-derived again on 2026-08-29**, for the identical reason `14-04` gives above:
`TenantScopeExemptions.cs`'s own dictionary had grown to 27 entries and this document's counts, bullet
lists and route table had not kept pace with what shipped in between — `13-01`/`13-02` (operator
invites, billing/YooKassa), `13-07` (`ListMyTenanciesHandler`), `14-01`/`14-02` (channel receive/
deliver/credentials), `16-02` (conversation lookup and erasure requests), `16-03` (tenant export),
`18-06` (auto-close) and `18-07` (returning-visitor history) each added one or more entry points,
several of them behind new client-supplied-`siteId` route groups the routes row had not counted. Two
more gaps predate even `14-04` and were simply never folded in: `8-07`'s `MintDemoTenantHandler`, and
`14-04`'s own `GetOfflineAutoReplyHandler`/`UpdateOfflineAutoReplyHandler` — that item's own paragraph
above says both were added as RBAC-gated, but neither row ever made it into the table below. All seven
headline rows are restated from a full rescan rather than a further delta, the same way `14-04` chose
to for the first three: 60 entry points across 52 handler classes (33 gated, 27 exempt), 48 routes and
hub methods (17 of them client-supplied `siteId`, across nine route groups), and 7 read-model queries.
The cross-tenant-read count alone held at 1 — nothing added since `12-02` reads across tenants.

**A same-day delta, not a third rescan.** `13-03` (subscription lifecycle, seat assignment) merged the
day this document was reconciled, adding six entry points across five new handler classes:
`CancelSubscriptionHandler`, `ChangeSubscriptionSeatsHandler`, `ToggleOperatorSeatHandler`,
`RemoveOperatorHandler` and `GetSeatAssignmentSummaryHandler` (all `site:configure` or
`site:manage-operators`-gated, on a new `/api/v1/sites/{siteId}/operators/...` route group plus two more
routes on the existing billing group) and `ProcessSubscriptionRenewalHandler` (worker-side, exempt — the
identical shape `AutoCloseConversationHandler` already has). Folded straight into the counts above rather
than left for a future rescan, since the gap would otherwise reopen within hours of closing it: 66 entry
points across 59 handler classes (38 gated, 28 exempt), 54 routes and hub methods (22 client-supplied
`siteId`, across ten route groups). Read-model queries and the cross-tenant-read count are unaffected —
`13-03` added no new read store.

**A second same-day delta.** `18-02` (transfer a conversation) added one entry point in one new
handler class, `TransferConversationHandler` — `conversation:assign`-gated (the same permission
`AssignConversationHandler` already uses), `siteId` from the operator claim like `/close` and `/read`
beside it, not client-supplied, on the existing `/api/v1/conversations/{conversationId}/transfer`
sub-resource rather than a new route group. Folded straight in for the same reason `13-03`'s delta was:
67 entry points across 60 handler classes (39 gated, 28 exempt), 55 routes and hub methods (22
client-supplied `siteId`, across ten route groups, unchanged — the new route is not one of them).
Read-model queries and the cross-tenant-read count are unaffected — `18-02` added no new read store.

**A third same-day delta.** `18-04` (internal notes and tags) added nine entry points across nine new
handler classes, all RBAC-gated, none exempt: `AddConversationNoteHandler`
(`conversation:note_write`), `GetConversationNotesHandler`/`ListTagsHandler`/
`GetConversationTagsHandler` (`conversation:read` — a note or a tag is read context for whoever can
already read the conversation, the same reasoning the write permission's own remarks give),
`CreateTagHandler`/`RenameTagHandler`/`DeleteTagHandler` (`site:configure` — managing the tag
vocabulary itself, distinct from applying one), `TagConversationHandler`/`UntagConversationHandler`
(`conversation:tag`). Nine new routes: two on the existing `/api/v1/conversations/{conversationId}/notes`
sub-resource shape (`siteId` from the operator claim, not client-supplied) and three more on
`/api/v1/conversations/{conversationId}/tags` (same shape), but the tag *vocabulary* endpoints
(`GET`/`POST /api/v1/sites/{siteId}/tags`, `PUT`/`DELETE .../{tagId}`) are a genuinely new,
**eleventh** client-supplied-`siteId` route group — four of the nine new routes. Folded straight in:
76 entry points across 69 handler classes (48 gated, 28 exempt), 64 routes and hub methods (26
client-supplied `siteId`, across eleven route groups). Read-model queries and the cross-tenant-read
count are unaffected — `18-04` added no new read store.

The gated/exempt split is not prose — it is enforced. `Ago.Chat.Architecture.Tests.TenantScopeTests` walks
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
3. **The client, in a route segment.** Eleven route groups as of this writing —
   `/api/v1/sites/{siteId}/widget-config`, `/api/v1/sites/{siteId}/webhooks/...`, since `14-04`
   `/api/v1/sites/{siteId}/offline-auto-reply`, and since `13-01`/`13-02`/`14-02`/`16-02`/`16-03`
   `/api/v1/sites/{siteId}/operator-invites`, `/api/v1/sites/{siteId}/billing/checkout-sessions`,
   `/api/v1/sites/{siteId}/channels/max`, `/api/v1/sites/{siteId}/channels/telegram`,
   `/api/v1/sites/{siteId}/erase` and `/api/v1/sites/{siteId}/exports/...`, and since `13-03`
   `/api/v1/sites/{siteId}/billing/subscriptions/{id}/...` (two more routes on the existing billing
   group) plus a new `/api/v1/sites/{siteId}/operators/...` group (seat toggle, removal, seat-summary),
   and since `10-06` `/api/v1/sites/{siteId}/installation` — a read whose failure mode is unusually
   quiet, since leaking it returns another tenant's public key with a `200` rather than throwing.
   This is deliberate and documented in the code: an operator's own site claim is not necessarily the
   site being configured. **On these routes the permission check is the entire defence**, which is why
   `CrossTenantRouteIsolationTests` exercises them over real HTTP with a real Keycloak token and the
   real `PermissionChecker`, rather than at the handler level with a fake.
4. **Nowhere, or from a route the caller chose — the platform owner's four.**
   `GET /api/v1/owner/sites` (`12-02`) has no `site_id` at all; the three owner writes (`14-12`'s
   unlink, `22-17`'s module grant and revoke) take one the caller names, gated only by
   `RequirePlatformOwner`. See *The cross-tenant surfaces the platform owner reaches* below.

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

### RBAC-gated (48)

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
| `GetSiteInstallationHandler` | **route segment** | `site:configure` | n/a — the site *is* the object |
| `RegisterWebhookEndpointHandler` | **route segment** | `webhook:manage` | n/a — creates a row for that site |
| `ListWebhookEndpointsHandler` | **route segment** | `webhook:manage` | n/a — loads by site |
| `RevokeWebhookEndpointHandler` | **route segment** | `webhook:manage` | `endpoint.SiteId == command.SiteId` |
| `GetWebhookDeliveriesHandler` | **route segment** | `webhook:manage` | `endpoint.SiteId == query.SiteId` |
| `GetOfflineAutoReplyHandler` | **route segment** | `site:configure` | n/a — the site *is* the object |
| `UpdateOfflineAutoReplyHandler` | **route segment** | `site:configure` | n/a — the site *is* the object |
| `CreateCheckoutSessionHandler` | **route segment** | `site:configure` | n/a — the site *is* the object; `13-02` |
| `CreateOperatorInviteHandler` | **route segment** | `site:manage-operators` | n/a — the invited role is looked up by the same `SiteId`; `13-01` |
| `RegisterChannelCredentialHandler` | **route segment** | `channel:manage` | n/a — creates a row for that site; `14-02`/`adr/0069` |
| `RevokeChannelCredentialHandler` | **route segment** | `channel:manage` | `credential.SiteId == command.SiteId`; `14-02`/`adr/0069` |
| `RequestSiteErasureHandler` | **route segment** | `site:erase` | n/a — the site *is* the object; `16-02` |
| `RequestSiteExportHandler` | **route segment** | `site:export` | n/a — the site *is* the object; `16-03` |
| `GetSiteExportStatusHandler` | **route segment** | `site:export` | `record.SiteId == query.SiteId`, inside `IExportRequestRepository.GetAsync`; `16-03` |
| `GetConversationByIdHandler` | operator claim | `conversation:erase` | `readStore.GetByIdAsync` is scoped by `query.SiteId`; a different site's conversation is `NotFound`, not `Forbidden`; `16-02` |
| `RequestConversationErasureHandler` | operator claim | `conversation:erase` | `erasureRequests.RequestConversationErasureAsync` is scoped by `command.SiteId` as well as `ConversationId`; `16-02` |
| `GetVisitorHistoryHandler.HandleAsOperatorAsync` | operator claim | `conversation:read` | `conversation.OperatorId == caller`; `18-07` |
| `GetVisitorHistoryHandler.HandleHistoricalConversationAsOperatorAsync` | operator claim | `conversation:read` | `conversation.OperatorId == caller` on the requesting conversation, **and** `historical.VisitorId == conversation.VisitorId` on the historical one; `18-07` |
| `CancelSubscriptionHandler` | **route segment** | `site:configure` | n/a — the site *is* the object; `13-03` |
| `ChangeSubscriptionSeatsHandler` | **route segment** | `site:configure` | n/a — the site *is* the object; `13-03` |
| `ToggleOperatorSeatHandler` | **route segment** | `site:manage-operators` | n/a — the operator being toggled is looked up by the same `SiteId`; `13-03` |
| `RemoveOperatorHandler` | **route segment** | `site:manage-operators` | n/a — the operator being removed is looked up by the same `SiteId`; `13-03` |
| `GetSeatAssignmentSummaryHandler` | **route segment** | `site:manage-operators` | n/a — the site *is* the object; `13-03` |
| `TransferConversationHandler` | operator claim | `conversation:assign` | `conversation.OperatorId == command.FromOperatorId`; target looked up by `(OperatorId, SiteId)` so a cross-site target is structurally impossible, not merely refused; `18-02` |
| `AddConversationNoteHandler` | operator claim | `conversation:note_write` | `readStore.GetByIdAsync` is scoped by `command.SiteId`; a different site's conversation is `NotFound`, not `Forbidden`; `18-04` |
| `GetConversationNotesHandler` | operator claim | `conversation:read` | same site-scoped conversation lookup as the write side; `18-04` |
| `CreateTagHandler` | **route segment** | `site:configure` | n/a — the site *is* the object; `18-04` |
| `RenameTagHandler` | **route segment** | `site:configure` | `tag.SiteId == command.SiteId`; `18-04` |
| `DeleteTagHandler` | **route segment** | `site:configure` | `tag.SiteId == command.SiteId`; `18-04` |
| `ListTagsHandler` | **route segment** | `conversation:read` | n/a — the read is keyed by `SiteId` directly; `18-04` |
| `GetConversationTagsHandler` | operator claim | `conversation:read` | conversation lookup scopes to `SiteId`; `18-04` |
| `TagConversationHandler` | operator claim | `conversation:tag` | conversation *and* tag both resolved by `SiteId`, so a cross-site tag cannot be attached; `18-04` |
| `UntagConversationHandler` | operator claim | `conversation:tag` | same double scoping as the apply side; `18-04` |
| *(the two `GetConversationHistory` operator entry points are counted separately above)* | | | |

### Not RBAC-gated, with the reason (28)

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

**Public, pre-authentication surface (6).** These serve a site's *public* configuration — the same
values any visitor's browser is handed during the widget handshake — so there is no tenant secret to
leak and, in most cases, no principal yet to check anything for.

- `CheckCorsOriginHandler` — deliberately cross-tenant and unauthenticated, answering only "does *any*
  site allow this origin", which is layer 1 of `5-01`'s CORS design. Never the per-site origin check.
- `GetSiteConfigByPublicKeyHandler` — the widget handshake, keyed by a public key that
  `api-design.md` states is not a secret.
- `GetSiteConfigByIdHandler` — takes a `SiteId` but is never reachable with a caller-supplied one.
  Its callers are `HubOriginValidator` on both hubs, passing the connection's own validated claim, and
  since `14-04` `SendOfflineAutoReplyHandler`, passing the site id off an envelope this system
  published. No route maps it.
- `MintDemoTenantHandler` — `8-07`/`adr/0058`'s live-demo bootstrap. Creates the tenant, the same
  category as `RegisterSiteHandler` right below, but reachable with no principal at all by design: a
  per-IP rate limit and a cap on total live demo tenants replace authentication, and the handler only
  ever writes a brand-new Site/Operator/roles package, never reads or touches an existing site. Off
  entirely unless `DemoTenant:Enabled` says otherwise.
- `RegisterSiteHandler` — creates the tenant, so there is no site to be scoped to. Gated instead by
  `10-01`'s `RequireKeycloakIdentity` plus one-registration-per-subject, enforced by a unique index
  inside the registration transaction.
- `RedeemOperatorInviteHandler` — `13-01`. The redeeming caller has no `SiteId` claim yet, by
  definition — the same category and the same reason as `RegisterSiteHandler` right above. The
  presented invite code's own `code_hash` lookup resolves the site the write lands on, never a value
  this caller supplies.

**Consumer and worker side (11).** No external caller reaches most of these: the input is an
integration event this system itself published, so the site is a fact already established by the
write that raised it. Four of the eleven (`ReceiveChannelMessageHandler`, `AutoCloseConversationHandler`,
`ListMyTenanciesHandler`, `ProcessSubscriptionRenewalHandler`) are not broker-triggered and are called
out individually below — they sit here because, like the broker-fed ones, none of them has a
caller-supplied `SiteId` to check.

`DispatchWebhooksForEventHandler`, `RecordUnreadMessageHandler`, `SendOfflineAutoReplyHandler`,
`ResolveConversationAssignmentTargetsHandler`, `ResolveMessageDeliveryTargetsHandler`,
`DeliverChannelMessageHandler`, `ResolveOperatorIdentityHandler` — the last of which is what
*produces* the `OperatorId`/`SiteId` claims every gated handler then trusts, and so cannot itself
depend on them.

`SendOfflineAutoReplyHandler` (`14-04`, `adr/0066`) is the newest of that broker-fed group and the
only one that *writes a message*, so it is worth one extra sentence. Its `SiteId` comes off a
`MessageAccepted` envelope this system itself published; it uses that id for exactly two things, both
self-consistent — reading that same site's cached configuration, and asking whether that same site has
an operator online — and it then writes into the conversation that envelope named. There is no
principal to check a permission for: nobody asked for the reply, a broker delivery did, and the message
it writes is authored by the system itself, which `adr/0016` has no representation for (exactly as it
has none for a visitor).

`ReceiveChannelMessageHandler` (`14-01`, adapter side for AGO Inbox) carries a `SiteId` no external
caller can influence either, but not from a broker envelope: no channel provider's payload has a way
to name a site, so the concrete adapter resolves it from the credentials the message arrived on — the
site that owns the MAX bot token, or rents the SMS long number — before the command is even
constructed. There is also no principal to check a permission for, an SMS sender being outside the
RBAC model exactly as a visitor is (`adr/0016`); what replaces it is stronger than a site check: every
write lands only in the `Visitor` that this site's own `ChannelIdentity` row resolves to, so a message
can only ever reach a conversation belonging to the site whose credentials received it.

`AutoCloseConversationHandler` (`18-06`, worker side) is keyed by neither a caller nor a broker event —
the only input is a `ConversationId` that `AutoCloseInactiveConversationsJob`'s own candidate scan
already restricted to `Assigned` conversations past their per-channel-kind inactivity window, a fact
the scan itself established by reading `conversations.state` and `messages.created_at`, not a claim to
verify. There is also no principal to check a permission for — nobody asked for this close, a
scheduled sweep did — and what a `SiteId` check would have protected against is already ruled out
structurally: `IConversationRepository.GetByIdAsync` loads exactly the row the scan named.

`ProcessSubscriptionRenewalHandler` (`13-03`, worker side) is the identical shape as
`AutoCloseConversationHandler` immediately above — the only input is a `BillingSubscriptionId` that
`SubscriptionRenewalJob`'s own candidate scan already restricted to rows whose `current_period_end` has
passed or whose retry is due, a fact the scan established by reading `billing_subscriptions` directly,
not a claim to verify. No principal to check a permission for — nobody asked for this renewal attempt,
a scheduled sweep did — and the one write this handler can make (a real charge against a stored payment
method) acts only on the row the scan named, never on a caller-supplied id.

`ListMyTenanciesHandler` (`13-07`/`adr/0068`) is the odd one structurally: it is reached by an
authenticated caller over HTTP, not a broker delivery, but it has no single `SiteId` to scope to *by
design* — it is the console switcher's own read, "every site this identity administers." Gated instead
by `RequireKeycloakIdentity` (an identity with zero or several tenancies cannot yet satisfy
`RequireOperatorIdentity`), and `IOperatorRepository.ListByExternalSubjectIdAsync` filters at the query
itself on the caller's own `sub`, read from the validated token, so the row set this handler can ever
see is already restricted to that identity's own operator rows before a `Site` is joined in —
structurally the same "`sub`-keyed lookup feeding an identity's own tenancy" category
`ResolveOperatorIdentityHandler` above is in, not a cross-tenant read the way `ListSitesForOwnerHandler`
below genuinely is.

**An operator's own presence (2).** `SetOperatorPresenceHandler.GoOnlineAsync`/`GoOfflineAsync`
(`4-06`), called only from `OperatorHub.OnConnectedAsync`/`OnDisconnectedAsync`. No `SiteId` at all,
deliberately: the only input is the caller's own `OperatorId`, resolved from the connection's own
validated JWT before either method runs. There is no site-scoped resource being acted on to check
ownership of — only "record this connection's own presence" — so a `SiteId` parameter would be an
unused, unverifiable claim rather than a real check.

**Inbound, HTTP-triggered webhook (1).** `13-02`/`adr/0025`. The third-party mirror of the consumer/
adapter category above — reached over HTTP rather than the broker, but the same shape: the tenant is a
fact established by our own prior write, not a caller's claim. `ProcessYooKassaWebhookHandler` carries
no `SiteId` at all: the input is ЮKassa's own payment id, which no external caller can choose a site
with — `IBillingWebhookApplier` resolves the one `billing_subscriptions` row that payment id names and
acts on that row's own `SiteId`, a fact `CreateCheckoutSessionHandler` already established (gated by
`site:configure` the ordinary way) at checkout-session creation. There is also no principal to check a
permission for — nobody asked for this write, ЮKassa's own webhook delivery did — and the attack
surface is narrower still: the endpoint rejects a missing or invalid `Webhook-Signature` header before
this handler is ever constructed, so every payment id it ever sees is one ЮKassa itself signed with a
key only this deployment and ЮKassa hold.

**The cross-tenant surfaces the platform owner reaches (4).** `ListSitesForOwnerHandler`, `12-02`'s
platform-owner overview, is the read. It carries no `SiteId` **because** it is cross-tenant. The whole
access-control story is `12-01`'s `RequirePlatformOwner` policy on `GET /api/v1/owner/sites`: the
authorizing fact is a Keycloak realm role (`adr/0032`), and `Ago.Chat.Application` has no port that
sees claims — re-checking in the handler would be a second, weaker copy of the same rule, free to
drift from the first.

**Three cross-tenant *writes* sit beside it, and this section claimed until 2026-09-04 that none
existed anywhere.** `UnlinkChannelIdentityAsOwnerHandler` (`14-12`, `adr/0079`) was the first, and the
claim was already false before `22-17` added `EnableModuleForSiteAsOwnerHandler` and
`RevokeModuleForSiteAsOwnerHandler` (`adr/0098`). All three take a `SiteId` **the caller chooses**,
which is both the point and the risk: they are the only handlers here where an operator-shaped token
names a tenant it holds no `operators` row in and is obeyed. None carries an `OperatorId` or calls
`IPermissionChecker`, for the same reason the read does not — so the route's policy is the entire gate
in all four cases. **That the "no owner write surface exists anywhere" sentence survived one
counter-example until a second arrived is the argument for these four being listed in one place
rather than described where each was built.**

Since `12-05` the read is the **one place in the codebase where a caller's own `site_id` must be
ignored rather than merely unused**, and the reason is worth stating where the rule lives. (The three
writes above never see it either, but each is handed the tenant it acts on in the route, so there is
nothing to ignore — the danger there is the opposite one, of trusting a `SiteId` the caller chose.) The platform owner may now hold an
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
| `POST /api/v1/demo/credentials` | anonymous | n/a — creates a brand-new tenant, deliberately with no principal at all; `8-07`/`adr/0058`, off unless `DemoTenant:Enabled` |
| `GET /api/v1/me/tenancies` | `RequireKeycloakIdentity` | n/a — deliberately no single site, the console switcher's own read; `13-07`/`adr/0068` |
| `POST /api/v1/operator-invites/redeem` | `RequireKeycloakIdentity` | n/a — the presented invite's own `code_hash` names the site, not the caller; `13-01` |
| `GET /api/v1/conversations/queue` | `RequireOperatorIdentity` | operator claim |
| `GET /api/v1/conversations/all` | `RequireOperatorIdentity` | operator claim |
| `POST /api/v1/conversations/{id}/close` | `RequireOperatorIdentity` | operator claim |
| `POST /api/v1/conversations/{id}/read` | `RequireOperatorIdentity` | operator claim |
| `POST /api/v1/conversations/{id}/erase` | `RequireOperatorIdentity` | operator claim; `16-02` |
| `GET /api/v1/conversations/{id}` | `RequireOperatorIdentity` | operator claim; `16-02`, the erasure completion poll |
| `GET /api/v1/conversations/{id}/visitor-history` | `RequireOperatorIdentity` | operator claim; `18-07` |
| `GET /api/v1/operators/me` | `RequireOperatorIdentity` | operator claim |
| `POST /api/v1/conversations/{id}/attachments` | `EitherTokenKind` | operator claim, or the visitor token |
| `POST /api/v1/attachments/{id}/confirm` | `EitherTokenKind` | operator claim, or the visitor token |
| `GET /api/v1/attachments/{id}` | `EitherTokenKind` | operator claim, or the visitor token |
| `DELETE /api/v1/attachments/{id}` | `RequireOperatorIdentity` | operator claim |
| `GET`/`PUT /api/v1/sites/{siteId}/widget-config` | `RequireOperatorIdentity` | **client-supplied** |
| `GET /api/v1/sites/{siteId}/installation` | `RequireOperatorIdentity` | **client-supplied**; `10-06` |
| `GET`/`PUT /api/v1/sites/{siteId}/offline-auto-reply` | `RequireOperatorIdentity` | **client-supplied** |
| `POST`/`GET /api/v1/sites/{siteId}/webhooks` | `RequireOperatorIdentity` | **client-supplied** |
| `DELETE /api/v1/sites/{siteId}/webhooks/{id}` | `RequireOperatorIdentity` | **client-supplied** |
| `GET /api/v1/sites/{siteId}/webhooks/{id}/deliveries` | `RequireOperatorIdentity` | **client-supplied** |
| `POST /api/v1/sites/{siteId}/operator-invites` | `RequireOperatorIdentity` | **client-supplied**; `13-01` |
| `POST /api/v1/sites/{siteId}/billing/checkout-sessions` | `RequireOperatorIdentity` | **client-supplied**; `13-02` |
| `POST /api/v1/billing/webhooks/yookassa` | anonymous, signature-verified | n/a — resolved from the payment id via `billing_subscriptions`; `13-02`/`adr/0025` |
| `POST /api/v1/sites/{siteId}/channels/max` | `RequireOperatorIdentity` | **client-supplied**; `14-02`/`adr/0069` |
| `DELETE /api/v1/sites/{siteId}/channels/max/{id}` | `RequireOperatorIdentity` | **client-supplied**; `14-02`/`adr/0069` |
| `POST /webhooks/max/{credentialId}` | anonymous, signature-verified | n/a — resolved from the credential id, not the caller; `14-01`/`14-02` |
| `POST /api/v1/sites/{siteId}/channels/telegram` | `RequireOperatorIdentity` | **client-supplied**; `14-02`/`adr/0069` |
| `DELETE /api/v1/sites/{siteId}/channels/telegram/{id}` | `RequireOperatorIdentity` | **client-supplied**; `14-02`/`adr/0069` |
| `POST /api/v1/sites/{siteId}/erase` | `RequireOperatorIdentity` | **client-supplied**; `16-02` |
| `POST /api/v1/sites/{siteId}/exports` | `RequireOperatorIdentity` | **client-supplied**; `16-03` |
| `GET /api/v1/sites/{siteId}/exports/{exportId}` | `RequireOperatorIdentity` | **client-supplied**; `16-03` |
| `GET /api/v1/owner/sites` | `RequirePlatformOwner` | none, deliberately |
| `/hubs/visitor` — `JoinAsync`, `SendMessageAsync`, `SendStructuredMessageAsync`, `GetHistoryAsync` | Visitor scheme | signed visitor token |
| `/hubs/operator` — `JoinConversationAsync`, `SendMessageAsync`, `SendStructuredMessageAsync`, `GetHistoryAsync`, `GetVisitorHistoryConversationAsync`, `GetVisitorPresenceAsync` | `RequireOperatorIdentity` | operator claim |

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
| `ConversationReadStore.GetByIdAsync` | `conversation_id` **and** `site_id` | `16-02`. Returns `null` for a different site's conversation, indistinguishable from a nonexistent one; `GetConversationByIdHandler` gates the call on `conversation:erase`. |
| `ConversationReadStore.GetVisitorHistoryAsync` | `conversation_id` (excluded) via `visitor_id` | `18-07`. `visitor_id` is not itself a `site_id`, but `GetVisitorHistoryHandler` has already proved the caller is assigned to a live conversation with this visitor before this query runs. |
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
| Only the platform owner reaches the cross-tenant writes | `OwnerModuleEndpointsTests` (`22-17`) — an ordinary operator **and** a `site:configure`-holding admin both refused, and the owner token refused on the tenant's own self-service route |
| Every use case is gated or argued | `TenantScopeTests` |
