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
are mutually exclusive, so exactly one ever authenticates a real token; a new `kind` JWT claim
(`"visitor"`/`"operator"`, `JwtTokenService`) is how the handler tells them apart afterward, since
`aud` alone answers "is this token valid for this route", not "which principal is this".

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

## Compatibility

Additive changes only within a version: new optional fields are fine, renamed or removed fields are
not. Breaking changes ship as `/api/v2` alongside v1 until the widget population has moved - and
since we cannot force a shop to update its script tag, "until" is measured in months, not days.
