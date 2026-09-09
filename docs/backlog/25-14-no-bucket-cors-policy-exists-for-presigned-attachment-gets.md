# 25-14 · No bucket CORS policy exists for presigned attachment GETs

- **Status**: ready — **fixed and proven locally (`ago-deploy/seed/apply-minio-cors.sh`); not yet
  applied to the k8s dev cluster or the demo overlay's own MinIO, see Done-when**
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

- [~] A presigned attachment GET succeeds via `fetch()` from an origin `sites.allowed_origins`
      permits, proven against a real bucket (MinIO locally at minimum). — **proven locally**
      (`docker-compose`'s own MinIO); **not yet applied to the k8s dev cluster or the demo overlay**,
      both reachable only via `kubectl exec`. Running the script's own commands by hand against that
      cluster is not yet a checked-in step — named as a real remaining gap, not silently assumed
      covered by the local proof.
- [x] An origin outside that allowlist is refused, proven the same way — the control, not just the
      positive case.
- [x] `docs/architecture/file-storage.md`'s note about this gap is updated to say it is closed.

## Outcome

**The premise this item was filed on was itself wrong, in the safer direction.** MinIO's real default
CORS posture is wide open (`Access-Control-Allow-Origin: *`, reflecting any origin unconditionally) —
the opposite of AWS S3's default this item and `file-storage.md` both assumed. The live gap was
over-permissiveness (any origin able to obtain a presigned URL could read the bytes), not blockage.

**A literal "bucket CORS policy" does not exist on this MinIO version** — `PutBucketCors` answers
`501 Not Implemented`. The only real knob is the server-wide admin setting `api.cors_allow_origin`,
one list for the whole server (this deployment has exactly one bucket, so that's moot here). Fixed by
`ago-deploy/seed/apply-minio-cors.sh`, which snapshots every distinct origin in `sites.allowed_origins`
into that setting and restarts the container — verified against the real local MinIO: a disallowed
origin gets no `Access-Control-Allow-Origin` header, an allowed one does.

**This is a snapshot, not a subscription — named, not hidden.** No S3-compatible CORS model (MinIO or
real AWS S3) can express a live, per-request dynamic allowlist the way `SiteOriginCorsPolicyProvider`
does for the REST API. A tenant who adds a new origin stays CORS-blocked until the script re-runs.
Nothing re-runs it automatically today; that is out of this item's own scope and is named in
`file-storage.md` rather than carried forward silently.

**A boundary tension worth reading, not just noting**: the script reads a tenant business column
(`sites.allowed_origins`) from the `ago-deploy` infrastructure repository, which that repository's own
README rule argues against on its face. No `ago-platform` port exists for "restrict CORS to this
origin set," and MinIO's mechanism has no per-request hook an application process could drive even if
one existed — so this is accepted as the same kind of explicit operational step the bucket-provisioning
gap already takes, not resolved by assertion. See `file-storage.md` for the full reasoning.

Full write-up: `docs/architecture/file-storage.md`.
