# Per-site CORS from the database

- **Stage**: 5
- **Status**: done
- **Depends on**: nothing (foundational - every widget-facing item in this stage needs cross-origin
  calls to actually work, not just pass same-origin tests)

## Goal

`Ago.Chat.Api` accepts cross-origin requests from a visitor's own site, and only that site -
`Site.AllowedOrigins` (already modelled in Domain, `1-01`) becomes the actual CORS policy, not just a
stored list nothing reads. `edge.md` is explicit that this belongs in the app, never the ingress: "CORS
logic that depends on a site's `allowed_origins`... belongs in the app." Today there is no CORS
middleware wired up at all - `Program.cs`'s own comment says so ("Real cross-origin widget CORS is
Stage 5").

## Context to read first

`edge.md`'s "What the edge must not be responsible for" section, `api-design.md`'s "Widget-facing
constraints" (CORS is per-site, driven by `allowed_origins` from the database, never a wildcard, never
an ingress annotation), `Site.cs` (`Ago.Chat.Domain`) - `AllowedOrigins` already exists, this item is
the first thing that reads it for a real decision. `GetSiteConfigByPublicKeyHandler`
(`Ago.Chat.Application.UseCases.GetSiteByPublicKey`) - the widget's own handshake path, and the
existing precedent for "look up a site by its public key, cheaply, with caching" (`caching.md`) this
item's origin check should reuse rather than duplicate.

**A design constraint found while starting this item, not obvious from the docs above - read before
writing any CORS policy code**: a browser's CORS preflight (`OPTIONS`) carries the `Origin` header and
the target URL, but never the request body and never the *value* of any other header (only their
*names*, via `Access-Control-Request-Headers`). `POST /api/v1/visitor-sessions` identifies its site by
`PublicKey` in the JSON body - which means an `ICorsPolicyProvider` cannot resolve "which site is this
request for" during preflight, because the one piece of data that would answer that question has not
arrived yet. The same is true for any endpoint that identifies its tenant via a header value (a bearer
token's `site_id` claim) rather than the URL or query string itself.

The consequence, and the actual design this item must build: **CORS is not, and cannot be, the
tenant-isolation boundary here** - it is a browser-side convenience that decides whether a page's own
JavaScript gets to read the response, and it is well-established that `Origin` is trivially forgeable
by any non-browser caller anyway. The real per-site boundary is an **in-application origin check**,
made once the request has actually identified which site it is for (the body's `PublicKey`, or a
token's `site_id` claim) - this is "in the app" exactly as `edge.md`/`api-design.md` already say, it
just is not *inside the CORS policy resolution step* specifically. Two layers, not one:

1. **CORS policy** (`ICorsPolicyProvider`): allows an `Origin` if *any* site's `AllowedOrigins` contains
   it. Not a bulk "load every site" union - a new origin-keyed lookup (`ISiteRepository` gains an
   `AnyAllowsOriginAsync(origin)` method translating to `WHERE @origin = ANY(allowed_origins)`, cheap
   with an index on the array column), behind its own small Application handler that follows
   `GetSiteConfigByPublicKeyHandler`'s exact cache-aside + negative-caching shape (`caching.md`), just
   keyed by origin instead of public key - the same pattern, a new key, not a new mechanism. This is
   what lets a legitimate widget's preflight succeed at all; it does not by itself prove the origin
   belongs to *this* request's site.
2. **In-app check**: once the handler (or the hub's `OnConnectedAsync`) has resolved which site the
   request is actually for, it compares the request's `Origin` header (or, for a hub connection, the
   value captured at connect time) against *that specific site's* `AllowedOrigins` and rejects
   (`403`/aborts the connection) on a mismatch - this is the real multi-tenant boundary, and it holds
   even against a caller that spoofs `Origin` and skips CORS entirely.

## Scope

- The per-origin `ICorsPolicyProvider` (layer 1 above), backed by its own cache-aside read
  (`CheckCorsOriginHandler`), refreshed the same TTL-based way `GetSiteConfigByPublicKeyHandler`'s own
  cache already is - no event-driven invalidation wired up yet, since `SiteSettingsChanged` has no
  producer today either (`caching.md`).
- The in-app origin check (layer 2 above), added at every point a site is resolved from caller-supplied
  data: `AuthEndpoints.HandleVisitorSessionAsync` (after the existing `GetSiteConfigByPublicKeyHandler`
  lookup), and the hub connection path (`VisitorHub`/`OperatorHub`'s `OnConnectedAsync`, or
  `HubConnectionRegistration` if that is the more natural shared point - decide and state which,
  reading the JWT's already-present `site_id` claim, no new claim needed).
- Applies to every widget-facing surface: the visitor-session endpoint, both hubs, and any attachment
  endpoints this stage adds later (`5-03`) - state explicitly which endpoints are covered.
- A negative test for *each* layer, since they fail differently: an origin absent from *every* site's
  list never gets a CORS-allow header at all (layer 1); an origin present for site A but used against a
  request actually resolved to site B gets a CORS-allow header (browsers would let the JS read the
  response) but the in-app check still rejects the request (layer 2) - prove both, since a test that
  only covers layer 1 would pass even if layer 2 were never wired up.

## Out of scope

- A management surface for editing a site's `AllowedOrigins` - `1-05`'s seed script is still the only
  way any site gets one today; a real admin UI for it is `5-08`'s admin-role console work, if it turns
  out to be needed there, not this item.
- Rate limiting new endpoints - `3-05` already covers messages and visitor sessions; each later item
  that adds a new widget-facing endpoint (`5-03`'s attachment presign) is responsible for its own rate
  limit, not this one.

## Done when

- [x] `Ago.Chat.Integration.Tests` (layer 1, CORS): a request carrying an `Origin` header present in
      *any* seeded site's `AllowedOrigins` receives a matching `Access-Control-Allow-Origin` response
      header; a request from an origin in *no* site's list does not.
      `SiteOriginCorsPolicyProviderTests` - exercises `SiteOriginCorsPolicyProvider.GetPolicyAsync`
      directly (real Postgres + real Redis), not through a full HTTP pipeline/`TestServer`: the
      ASP.NET Core CORS *middleware* that turns a non-null `CorsPolicy` into real response headers is
      framework code this project does not re-test, matching how every other endpoint here is proven
      by calling its handler method directly.
- [x] `Ago.Chat.Integration.Tests` (layer 2, in-app): two seeded sites, each with its own distinct
      `AllowedOrigins` entry - a visitor-session request whose body names site A but whose `Origin`
      header is site B's approved origin (present in *some* site's list, so layer 1 alone would let it
      through) is rejected. Same proof against a hub connection using a token whose `site_id` claim
      names one site while the connection's origin is another site's approved value.
      `OriginAuthorizationTests` - both the visitor-session endpoint (`AuthEndpoints.
      HandleVisitorSessionAsync`, called directly, matching `RateLimitingTests`' own precedent) and
      `HubOriginValidator` (a real `HubCallerContext` fake carrying a real `IHttpContextFeature`, since
      SignalR's `GetHttpContext()` extension is `Microsoft.AspNetCore.SignalR.GetHttpContextExtensions`
      reading `Microsoft.AspNetCore.Http.Connections.Features.IHttpContextFeature` - SignalR's own
      HttpConnections-specific feature, not the generic ASP.NET Core hosting one; found only by
      reflecting the real assemblies after guessing wrong twice).
- [x] Both layers proven against the visitor-session endpoint and both hubs, not just one surface.
- [x] `edge.md`/`api-design.md` gets a "Shipped in `5-01`" note stating both layers explicitly - the
      CORS-is-not-authorization finding is exactly the kind of thing a later session must not have to
      rediscover.
      Done in `api-design.md`'s "Widget-facing constraints"; `caching.md` also got a note (see the
      real finding below).
- [x] Manually verified against the local cluster: `ago-chat/wwwroot/dev-harness.html` served from a
      *different* origin (a second static file server, or a `file://` origin) can complete the
      handshake and open a hub connection when that origin is seeded into the relevant site's
      `AllowedOrigins`, and cannot when it is not seeded anywhere at all (layer 1's own browser-visible
      behaviour - the layer 2 cross-tenant case is proven by the automated test above, since
      constructing it by hand would mean deliberately mis-seeding two real sites just to watch a
      browser reject one).

      Done, after fixing a real blocker found along the way: `dev-harness.html`'s every network call
      (`fetch('/api/v1/visitor-sessions', ...)`, both `HubConnectionBuilder().withUrl('/hubs/...')`
      calls) was root-relative, resolving against whatever origin serves the HTML file itself - serving
      it from a second static server 404'd the visitor-session call immediately, never reaching the
      real Api's CORS policy at all. Fixed with an `?api=http://host:port` override
      (`const API_BASE = new URLSearchParams(location.search).get('api') || ''`, defaulting to the
      existing same-origin behaviour `local-dev.md` already documents, so nothing already using this
      harness breaks).

      Verified live with two throwaway static servers over the demo site's real seeded config
      (`http://localhost:8080`/`:5009` already allowed, `http://localhost:8095` added for this test,
      `:8096` deliberately left unseeded): from `:8095?api=http://localhost:5009` the visitor-session
      POST completed (`OPTIONS` preflight `204`, `POST` `201`) and `JoinAsync` opened a real hub
      connection - a genuine cross-origin success, not same-origin masquerading as one. From
      `:8096?api=http://localhost:5009`, the browser itself rejected it: `Access to fetch ...  has been
      blocked by CORS policy: ... No 'Access-Control-Allow-Origin' header is present on the requested
      resource` - the exact browser-enforced behaviour this Done-when item asks for, not inferred from
      server logs.

A real finding, not part of this item's own scope, fixed along the way because it blocked layer 1
outright: `Ago.Platform.Abstractions.ICache.GetOrCreateAsync<T>` silently never called its factory
when caching a raw `bool` - an *unconstrained* generic `T?` has no runtime nullability for a
value-type `T` (`default(T?)` for `T = bool` is `false`, confirmed empirically, not a distinguishable
null), so the port's own miss-check treated a cold key as an already-cached `false` every time. Fixed
at the source: `ICache` now constrains `where T : class` (`Ago.Platform.Abstractions`/
`Ago.Platform.Caching.Redis`, `0.9.0`, `CHANGELOG.md`), and this item's own `CheckCorsOriginHandler`
wraps its `bool` in a small reference-type result, the same pattern every existing cache caller
(`SiteLookupResult`) already used. `RedisCacheTests` gained a regression test proving the
reference-type case - a DTO wrapping a "falsy" value - still round-trips and still calls the factory
exactly once.

## Open questions

None - the mechanism (a per-origin `ICorsPolicyProvider` plus a per-site in-app check) follows
directly from `edge.md`/`api-design.md`'s existing constraints once the preflight-timing limitation is
accounted for, above.
