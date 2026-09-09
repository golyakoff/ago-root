# 25-30 · The widget's static assets sent no CORS header at all

- **Stage**: 25
- **Status**: done — `ago-widget#72`, deployed and confirmed live
- **Depends on**: nothing
- **Found**: 2026-09-09, live, while investigating a separate reported booking-flow bug on
  `golyakov.net`

## What is actually true

Every file `ago-widget-assets`' nginx serves — `widget.js`, its lazy-loaded module chunks
(`widget-module-booking.js` and any future one), the demo pages it also serves under a different
build target — sent no `Access-Control-Allow-Origin` header at all. `<script src="widget.js">` never
needed one (CORS never governs a plain script-tag load), but `ui/moduleLoader.ts`'s own dynamic
`import()` of `widget-module-booking.js` does: the browser treats a dynamic import as a fetch-shaped
cross-origin request. On every tenant's own origin except whichever one happened to share this
server's own origin, that import silently failed
(`TypeError: Failed to fetch dynamically imported module`), console-visible only, no application-level
symptom the tenant would necessarily connect to the actual cause.

## Fix

`nginx.conf`'s `location /` gained `add_header Access-Control-Allow-Origin "*" always;`. A wildcard,
not a per-tenant allowlist the way the API's own `sites.allowed_origins` is — every file this server
holds is public, unauthenticated, and meant to be embedded on any site in the world by design, so
there is nothing here a wildcard exposes that the file's own existence at a public URL did not already.

## Done when

- [x] The built `assets` image sends `Access-Control-Allow-Origin: *` on every file it serves,
      confirmed by building the image locally and checking the header directly.
- [x] Deployed live (all three widget images move together — `demo-shop1`, `demo-shop2`,
      `widget-assets`); confirmed against the real production endpoint
      (`chat-api.reserve-me.ru/widget/widget-module-booking.js`).
