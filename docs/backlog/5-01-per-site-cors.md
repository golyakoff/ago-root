# Per-site CORS from the database

- **Stage**: 5
- **Status**: ready
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

## Scope

- A custom `ICorsPolicyProvider` (ASP.NET Core's extension point for a policy that cannot be known at
  startup) that, for a request against a widget-facing endpoint, resolves the site from the request
  (via the same public-key-or-token identification the handshake/hub endpoints already use) and
  allows the request's `Origin` only if it is in that site's `AllowedOrigins` - never a wildcard.
- The origin lookup goes through the existing site-config cache (`caching.md`), not a fresh Postgres
  round trip per preflight - reuse `GetSiteConfigByPublicKeyHandler`'s underlying read path or its
  cache entry directly rather than adding a second cache for the same data.
- Applies to every widget-facing surface: the visitor-session endpoint, the SignalR hub's negotiate/
  connect path (`Microsoft.AspNetCore.SignalR`'s own CORS requirements - credentials mode and origin
  matter for WebSocket/long-polling fallback), and any attachment endpoints this stage adds later
  (`5-03`) - state explicitly which endpoints are covered and confirm the policy applies to all of
  them, not just the ones exercised by today's dev harness.
- A negative test: a request from an origin *not* in a site's `AllowedOrigins` is rejected by CORS
  (real browser CORS is enforced client-side from response headers, so the test asserts the
  `Access-Control-Allow-Origin` header is absent/mismatched for that origin, the standard way to test
  ASP.NET Core CORS server-side).

## Out of scope

- A management surface for editing a site's `AllowedOrigins` - `1-05`'s seed script is still the only
  way any site gets one today; a real admin UI for it is `5-08`'s admin-role console work, if it turns
  out to be needed there, not this item.
- Rate limiting new endpoints - `3-05` already covers messages and visitor sessions; each later item
  that adds a new widget-facing endpoint (`5-03`'s attachment presign) is responsible for its own rate
  limit, not this one.

## Done when

- [ ] `Ago.Chat.Integration.Tests`: a request carrying an `Origin` header present in a seeded site's
      `AllowedOrigins` receives a matching `Access-Control-Allow-Origin` response header; a request
      from an origin not in that list does not.
- [ ] The policy is proven against the visitor-session endpoint and the hub connection path, not just
      one of the two.
- [ ] `edge.md`/`api-design.md` gets a "Shipped in `5-01`" note confirming the mechanism (which
      extension point, where the origin lookup's data comes from) matches what was documented in
      advance.
- [ ] Manually verified against the local cluster: `ago-chat/wwwroot/dev-harness.html` served from a
      *different* origin (a second static file server, or a `file://` origin) can complete the
      handshake and open a hub connection only when its origin is seeded into `AllowedOrigins`.

## Open questions

None - the mechanism (`ICorsPolicyProvider`, reusing the site-config cache) follows directly from
`edge.md`/`api-design.md`'s existing constraints.
