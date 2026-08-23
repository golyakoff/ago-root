# Embedding a self-registered site: CORS and origin verification

- **Stage**: 10
- **Status**: ready
- **Depends on**: `10-02-site-and-operator-registration.md` (a site must exist with real
  `allowed_origins`), `10-03-console-signup-onboarding.md` (the origin value in a real end-to-end run
  comes from the signup form, not a test fixture) — and `5-01-per-site-cors.md`, already shipped, whose
  mechanism this item proves rather than rebuilds.

## Goal

A site created through `10-02`/`10-03`'s flow can actually have the AGO Chat widget embedded on the
origin the visitor gave at signup, with no additional configuration step. `5-01`'s existing two-layer
CORS mechanism reads live from `sites.allowed_origins` with no static config anywhere, so this should
already work the moment the row exists — this item is where that claim is actually proven end-to-end
for a freshly self-registered site, rather than only the seeded demo site `5-01`'s own tests used, and
where any timing edge case (a cache-aside negative entry racing the site's own creation) gets found or
explicitly ruled out.

## Context to read first

`docs/backlog/5-01-per-site-cors.md` in full — the two-layer mechanism (CORS policy vs. in-app origin
check), and its own note that invalidation is TTL-based only, with no event-driven invalidation wired
up yet. `docs/architecture/caching.md`'s cache-aside and negative-caching sections. `docs/conventions/api-design.md`'s
"Widget-facing constraints" section, which already carries `5-01`'s shipped note.

## Scope

- An integration test (extending `5-01`'s own `OriginAuthorizationTests`/`SiteOriginCorsPolicyProviderTests`
  suite, matching its existing style) that runs the full sequence a real visitor's browser would:
  register via `10-02`'s endpoint with a specific origin, then immediately issue a widget handshake
  (`POST /api/v1/visitor-sessions`) from that exact origin, and confirm both CORS layers accept it —
  proving there is no gap between "site row committed" and "CORS/in-app check recognises it," which
  `5-01`'s own tests never had reason to check since they always seeded sites *before* ever touching the
  cache.
- Explicitly check the negative-cache edge case `5-01`'s TTL-only invalidation note raises: if
  something checked an origin *before* a site claiming it existed, `5-01`'s negative-caching
  (`caching.md`) could in principle strand a real new site behind a cached "no site allows this origin"
  answer until TTL expiry. State whether this is a real risk for self-registration specifically — a
  brand-new origin was, by construction, never checked by anyone before the site existed, since nobody
  could type that exact origin into a request before signup happened — and if a real gap is found
  instead, fix it and prove the fix; do not leave the question unstated either way.
- Update `5-01`'s own file and `api-design.md`'s existing "Shipped in `5-01`" note with a short
  addendum once this item proves (or disproves and fixes) the above, so a later session does not have
  to re-derive it.

## Out of scope

- Any UI or API for editing `allowed_origins` after signup. `5-01` already deferred this to "`5-08`'s
  admin-role console work, if it turns out to be needed there"; this stage does not change that —
  Stage 12's owner admin panel is the more likely home if it becomes a real ask.
- Multiple origins per site at signup time. `10-02`/`10-03` collect exactly one; supporting more is the
  same deferred editing-surface question above, not new scope here.

## Done when

- [ ] The end-to-end integration test above passes against a real Postgres + Redis, proving both CORS
      layers for a site created through this stage's own registration path, not only a pre-seeded
      fixture.
- [ ] The negative-cache timing question above is explicitly answered in this file's own text (updated
      in place) and, if a real gap was found, fixed with its own test proving the fix.
- [ ] `5-01`'s and `api-design.md`'s existing notes gain the addendum described above.

## Open questions

None — this item verifies, and if needed closes a gap in, an already-shipped and already-understood
mechanism; nothing here needs the author's input.
