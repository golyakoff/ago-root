# 25-14 · No bucket CORS policy exists for presigned attachment GETs

- **Status**: ready
- **Date found**: 2026-09-09, building `23-62` — a saved-conversation archive needs an attachment's
  real bytes, not a link
- **Depends on**: none

## What was found

Every existing consumer of a presigned attachment GET reaches it through plain navigation —
`<img src>` for an inline preview, `<a href>` for a download link — which a browser never subjects to
CORS. `23-62`'s save-conversation feature is the first caller that needs the bytes themselves, via
`fetch()`, to bundle a visitor's attachments into a saved-conversation `.zip` (`adr/0162`). A browser's
`fetch()` *is* subject to CORS, and MinIO/S3 sends no `Access-Control-Allow-Origin` header by default —
so, on the real deployment, `23-62`'s attachment fetch likely fails for every tenant origin today.

**Nothing observable told anyone this was missing.** `23-62`'s own code degrades gracefully — a failed
attachment fetch just leaves that attachment out of the archive, marked unavailable, per this
codebase's "never break the host page" discipline — so the gap produces a quieter, smaller archive
rather than an error a tenant would report. Documented as a known limitation in
`docs/architecture/file-storage.md` rather than left silent.

## Scope

A bucket CORS policy scoped to tenant origins, mirroring the per-site allowlist
`SiteOriginCorsPolicyProvider` already enforces for the REST API — so a presigned GET's `fetch()`
succeeds only from an origin that `sites.allowed_origins` already permits, the identical boundary this
codebase already draws for every other cross-origin call.

## Where this is likely to go wrong

- **MinIO locally and the real S3-compatible provider in production may configure CORS differently.**
  Confirm the policy applies (and is provable) on both, not just whichever is easier to test against.
- **A bucket-level CORS policy is static; the allowed-origins list is per-tenant and changes.** Decide
  whether this needs a wildcard scoped to the deployment's own domain pattern, or a mechanism that
  reacts to `sites.allowed_origins` changing — a stale, narrower CORS policy would silently reintroduce
  this exact gap for a tenant who changes their own origin later.

## Done when

- [ ] A presigned attachment GET succeeds via `fetch()` from an origin `sites.allowed_origins`
      permits, proven against a real bucket (MinIO locally at minimum).
- [ ] An origin outside that allowlist is refused, proven the same way — the control, not just the
      positive case.
- [ ] `docs/architecture/file-storage.md`'s note about this gap is updated to say it is closed.
