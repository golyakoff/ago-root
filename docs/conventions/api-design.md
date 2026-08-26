# API and protocol design

## HTTP

- REST-ish, resource-shaped, versioned by path: `/api/v1/...`. The widget is embedded on sites we do
  not control and cannot be forced to upgrade, so v1 is a promise.
- Plural resources, no verbs in paths. Actions that are not CRUD become sub-resources:
  `POST /api/v1/conversations/{id}/close`.
- `POST` returns `201` with a `Location`; idempotent retries of a create carry a client-supplied
  idempotency key and return the original result rather than a second row.
- Errors are RFC 7807 problem details with a stable machine-readable `type` and a `traceId`. Error
  text is for humans; clients branch on `type`, never on the message.
- Pagination is keyset only: `?before=<cursor>&limit=<n>`, response carries the next cursor. No page
  numbers, no `OFFSET` (`data-model.md`).
- Timestamps are ISO-8601 with offset (`date-and-time.md`).

## Outbound webhooks

The tenant-facing half of the HTTP surface, and the only place this system sends a request to a server
it does not control. Added in `16-01` because the rule below had been decided in `6-02`/`6-05`, held
in the code, and written down nowhere a reader would look before changing it.

- **A webhook payload carries no message body.** The delivered JSON is
  `(eventType, conversationId, occurredAt)` and nothing else, built once and sent identically to every
  endpoint of a site (`DispatchWebhooksForEventHandler`). A receiver that wants the text calls the API
  for it, with its own credentials, against its own permissions.
- **This is now a privacy property as well as a scope decision** (`personal-data.md`). Two things
  follow from it. Message content never leaves the deployment as a side effect of a tenant configuring
  a URL - so an erasure request does not have to chase copies sitting on third-party servers this
  project has no relationship with. And `webhook_deliveries.payload`, a row nothing ever prunes, holds
  no transcript.
- **Adding a field to that payload is a personal-data change**, whatever its size. It is also
  irreversible in a way an API response is not: once delivered, the data is on someone else's disk.
  Argue it in the change, and update `personal-data.md` in the same commit.
- What *is* stored from the other direction: `webhook_deliveries.response_snippet` keeps up to 2000
  characters of the receiver's own response body, for debugging. That is a third party's content held
  indefinitely, listed in `personal-data.md` rather than treated as log noise.
- Signing, secret lifecycle and the delivery/retry contract are `adr/0024`'s subject, not this
  section's.

## Realtime protocol

- Hub methods are thin transports; payload shapes live in `Ago.Chat.Contracts` and are versioned with
  the same additive-only rule as integration events.
- Client -> server messages carry `clientMessageId` for deduplication; server -> client messages carry
  the persisted id and `sequence`.
- Anything a client can send at high frequency (typing, presence) is throttled client-side and
  coalesced server-side, and never persisted.
- The client resumes by sending its last known `sequence` per conversation; the server replies with
  the delta. Reconnect must be cheap, because reconnects are normal (`adr/0010`).

## Widget-facing constraints

- CORS is per-site, driven by `allowed_origins` from the database, never by a wildcard and never by
  an ingress annotation (`edge.md`).
- The public site key identifies a tenant; it is not a secret and grants nothing beyond starting a
  visitor session. Anything sensitive requires the signed visitor token.
- Everything the widget calls is rate-limited per site and per visitor (`caching.md`), and returns
  `429` with `Retry-After`, which the widget must honour with jittered backoff.
- Payload ceilings are small and enforced; file bytes never come through the API (`adr/0008`).

**Shipped in `5-01`**: two layers, not one - a browser's CORS preflight (`OPTIONS`) carries only the
`Origin` header and the target URL, never the request body and never another header's *value* (only
its *name*, via `Access-Control-Request-Headers`), so nothing at preflight time can say *which site*
a request is for; `POST /api/v1/visitor-sessions` only learns that from its JSON body, and an
authenticated call only learns it from a JWT claim.

1. **CORS policy** (`SiteOriginCorsPolicyProvider`, a custom `ICorsPolicyProvider`): allows an
   `Origin` if *any* site's `AllowedOrigins` contains it (`ISiteRepository.AnyAllowsOriginAsync`,
   cache-aside behind `CheckCorsOriginHandler`, `caching.md`'s pattern reused with a new key). This
   is what lets a legitimate widget's preflight succeed at all - it does **not** prove the origin
   belongs to *this* request's site, only that it belongs to *some* site.
2. **In-app origin check** (`AuthEndpoints.HandleVisitorSessionAsync`, `HubOriginValidator` for both
   hubs): once a handler has actually resolved which site a request is for (the body's public key, or
   a JWT's `site_id` claim), it compares the caller's `Origin` against *that specific site's*
   `AllowedOrigins` and rejects on a mismatch. This is the real multi-tenant boundary - CORS is a
   browser-side convenience (it controls whether a page's own JavaScript may read the response), not
   an authorization mechanism, since `Origin` is trivially forgeable by any non-browser caller. For
   the two SignalR hubs specifically, this in-app check is not defense-in-depth, it is the *only*
   enforcement point: a WebSocket upgrade's `Origin` is not subject to the same preflight/policy
   mechanism plain HTTP is.

A real bug found live while building this, unrelated to CORS itself but blocking it: caching a raw
`bool` through `ICache.GetOrCreateAsync<T>` silently never called the factory, because an
*unconstrained* generic `T?` has no runtime nullability for a value-type `T` - `ICache` now
constrains `where T : class` project-wide (`Ago.Platform.Abstractions`, `0.9.0`), and this layer's own
positive/negative cache wraps its `bool` in a small reference-type result instead.

**Shipped again in `20-06`, for AGO Calendar, with three deliberate differences.** The same two
layers (`TenantOriginCorsPolicyProvider`, `EmbedScopeResolver`/`OriginPolicy`), adapted from "site" to
"tenant". What changed, and why each change was a decision rather than a drift:

- **The public key travels in a path segment, not a body.** `5-01` could not do this - the
  visitor-session endpoint's public key arrives in JSON - and the finding above is exactly why
  `20-06` did. Every public read is `GET /api/v1/embed/{publicKey}/…`, which is a URL a preflight can
  see. The policy still asks only the coarse question anyway: the one route that *cannot* name a
  tenant in its URL is `20-03`'s booking `POST`, which names a calendar, and a policy that were
  precise on three routes and coarse on the fourth would invite the belief that the precise ones are
  a boundary.
- **No cache on layer 1.** AGO Chat caches because it has an `ICache` wired; AGO Calendar
  deliberately does not (`Ago.Calendar.Infrastructure.Redis` registers only the rate limiter, and
  says why). The read is one `EXISTS` against a GIN index, browsers cache preflights for
  `Access-Control-Max-Age`, and adding a cache would import `5-01`/`10-04`'s stale-negative problem
  for an unmeasured saving. It also makes `20-06`'s allowed-origins editor - the one `5-01` deferred -
  take effect immediately, which is asserted by a test that approves an origin and reads the surface
  with no wait.
- **A *missing* `Origin` is not a rejection here, and in AGO Chat it is.** AGO Chat's visitor-session
  endpoint has exactly one legitimate caller, a browser. AGO Calendar's booking surface is
  deliberately reachable without one - `21-01` reaches it from a channel adapter with no browser in
  the path, and that is the product model the whole `20-06` embed decision rests on. `Origin` is
  forgeable by any non-browser caller anyway, so requiring it would ban the product's own second
  channel to gain nothing. What layer 2 stops is the attack a browser can actually mount: a page at
  an origin approved for tenant A using it against tenant B, where the browser attaches the real
  `Origin` and the page cannot remove it.

Observed live during `20-06`, and worth quoting because it is the clearest statement of why layer 1
alone is not a boundary: a request carrying tenant B's own approved origin against tenant A's public
key returned `404` **together with** `Access-Control-Allow-Origin: <tenant B's origin>`. The browser
was told it could read the response; the response was a refusal.

**Addendum (`10-04`)**: proven end-to-end for a site created through `10-02`'s real self-registration
path, not only pre-seeded fixtures - register, then an immediate widget handshake from that exact
origin, passes both CORS layers with no wait. The negative-cache timing question this mechanism's
TTL-only invalidation raises (could a pre-existing cached "no site allows this origin" strand a brand
new site?) is answered **not a real risk for self-registration**: the origin is unknown to the system
until `RegisterSiteHandler` commits it, the registration call itself never carries the customer's own
origin (it comes from the console), and the registering user has no public key to probe with before
registration completes - so nothing can ever populate a negative cache entry for that exact origin
ahead of time. Full reasoning and the tests proving both the real flow and the underlying (unfixed,
unreachable-here) TTL-only-invalidation limitation: `docs/backlog/5-01-per-site-cors.md`'s own
addendum, `docs/backlog/10-04-self-registered-site-embedding-verification.md`.

**Shipped in `5-03`**: `AttachmentEndpoints` is the first HTTP endpoint file to translate a
`Result<T>`/`Error` failure into an RFC 7807 response - `Ago.Chat.Api.Http.ErrorExtensions.ToProblem`
maps `ConversationErrors`' stable codes (`Attachment.NotFound`, `Message.RateLimited`, ...) to a
status code and a bare `type` slug (not a resolvable URL - `AuthEndpoints`' own precedent,
`"rate-limited"` not `"https://.../rate-limited"`), plus `traceId` from `HttpContext.TraceIdentifier`.
`AuthEndpoints` predates this: its own `Results.Problem` calls were built by hand because
`Error`/`Result<T>` had no HTTP-facing consumer yet.

It is also the first place two authentication schemes are accepted on one route
(`RequireAuthorization(policy => policy.AddAuthenticationSchemes(JwtSchemes.Visitor, JwtSchemes.Operator)...)`) -
every hub before this was single-role by construction (`VisitorHub` vs `OperatorHub`), but presigning
an upload is something both a visitor and an operator legitimately do. The two schemes' `aud` claims
are mutually exclusive, so at most one ever authenticates a real token; a `kind` JWT claim
(`"visitor"`/`"operator"`, `JwtTokenService`) is how the handler tells them apart afterward, since
`aud` alone answers "is this token valid for this route", not "which principal is this".

**Corrected in `17-06`** (`adr/0034`): "exactly one" was the wording here, and it is wrong by one
case. The Operator scheme also authenticates a Keycloak token whose `sub` matches no `operators` row —
a state anyone can reach through the realm's public registration form since `10-01` — and that
principal gets no `kind` claim at all, so it is neither. The rule for a multi-scheme route is
therefore: **require the `kind` claim to hold one of the values the route actually understands**, in
the policy, not in the handler's branch. `AuthorizationPolicies.EitherTokenKind` is the one instance,
and `TokenSchemeSeparationTests` is what holds it. If a second multi-scheme route is ever added, this
is the shape to copy - "not kind A, therefore kind B" is the mistake.

**Shipped in `5-09`**: the widget's `@microsoft/signalr` client defaults to `withCredentials: true`
on its HTTP transport (negotiate, long-polling), which sends the browser's cookie jar cross-origin
and then requires the server's CORS policy to answer with `Access-Control-Allow-Credentials: true`
for the request to succeed at all. Found live: the real per-site CORS policy (`5-01`) does not set
that header - deliberately, since nothing in this protocol was ever meant to use cookies (the
widget's own storage rule: "No cookies on the host domain," `embeddable-widget` skill) - so every
negotiate call failed its preflight until `VisitorConnection` (`ago-widget/src/connection.ts`) set
`withCredentials: false` explicitly. The fix is client-only; the server's CORS policy was already
correct and needed no change. Any other SignalR client this project adds (`5-06`'s console, against
`/hubs/operator`) starts from the same default and needs the same explicit override unless it
genuinely intends to authenticate via a cookie instead of a bearer token.

**Shipped in `6-08`**: `CloseConversationHandler`/`AssignConversationHandler` each catch a concurrent-
write conflict on the conversation row (`6-06`'s finding: a message send bumps `conversations.xmin`)
and reload-and-retry once, safe because `Close()`/`AssignTo()` re-validate their own invariant against
fresh data. A second conflict inside that retry becomes `Conversation.ConcurrencyConflict`, mapped to
`409` - never the raw `500` every caller got before. Translated at the persistence port's own boundary
(`ConversationConcurrencyConflictException`, `Ago.Chat.Application.Abstractions`), not with EF Core's
own exception type, since `Ago.Chat.Application` may not reference EF Core.

**Shipped in `5-15`**: `POST /api/v1/conversations/{id}/read` - "actions that are not CRUD become
sub-resources" again, a sibling of `/close`. Two things about it are worth reading as convention
rather than as one endpoint's detail. First, it takes `{"upToSequence": n}` rather than being a bare
"clear it" action: the body carries the state the caller is asserting ("my read position is n"), which
is what lets the server keep counting a message that arrives in the same instant instead of silently
muting it. Second, it is REST despite the console already holding an open SignalR connection to the
same server, and the reason is this convention itself - a non-assigned operator gets a real `403` with
a problem-details body and a `type` a client can branch on, where a hub method could only have thrown
a `HubException` carrying a string that is indistinguishable from a transport fault. A write whose
failure modes matter belongs on HTTP; a hub method is for what the connection is *for*.

## Compatibility

Additive changes only within a version: new optional fields are fine, renamed or removed fields are
not. Breaking changes ship as `/api/v2` alongside v1 until the widget population has moved - and
since we cannot force a shop to update its script tag, "until" is measured in months, not days.
