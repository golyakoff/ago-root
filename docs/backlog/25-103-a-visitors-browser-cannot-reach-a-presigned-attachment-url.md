# 25-103 · A visitor's browser cannot reach a presigned attachment URL

- **Stage**: 25
- **Status**: ready — **code complete and merged (`ago-deploy`), blocked on a DNS record before it
  can be applied or verified live.** `files.reserve-me.ru`'s A-record does not resolve yet (checked
  via `nslookup` against the real domain, compared against a known-working hostname) — issuance is
  HTTP-01 on a single certificate covering all nine of this deployment's public hostnames, so applying
  the TLS change before the record exists would fail the whole certificate, not just this one name.
  Create the A-record (same target as every other `*.reserve-me.ru` hostname), confirm it resolves,
  then apply and verify the four Done-when boxes below for real.
- **Depends on**: nothing
- **Found**: 2026-09-15, the author testing attachment upload live on the public demo — "виджет
  пробует отправить и не может" (the widget tries to send and can't). Traced to a gap `docs/
  architecture/file-storage.md` already names in two places (its own "Still open" note on the
  presigned-download path, and `23-81`'s own remarks on the upload path) but had never been given a
  number of its own.

## What is actually true

`Storage__S3__ServiceUrl` is `http://minio:9000` — the in-cluster Service DNS name
(`ago-deploy/k8s/base/api.yaml`, `worker.yaml`). `S3StorageOptions.ServiceUrl` is the **one** setting
`Ago.Platform.Storage.S3` uses both for the server's own calls to MinIO *and* as the base a presigned
URL is signed against (AWS SigV4 signs the host into the request). **Nothing in `ago-deploy` routes
any public hostname to MinIO** — confirmed by reading `k8s/overlays/demo/gateway.yaml` directly, which
lists every route this overlay serves and has no MinIO entry among them.

The consequence: every presigned URL this deployment issues — for an upload PUT or a download GET,
to a visitor or an operator — names a host a browser outside the cluster cannot resolve at all. The
request fails on DNS resolution before CORS, authentication, or anything else about the request is
ever evaluated. This is not a permission or quota problem; a conversation with a real, granted upload
permission and headroom in its budget still cannot complete an upload, because the URL it was handed
back is unreachable by construction.

## Why this is worth its own number

`file-storage.md` has stated this gap honestly, twice, since it was found — once for the download
path ("a presigned attachment GET issued by the live demo deployment is not reachable from a
visitor's browser at all yet") and once for the upload path ("nothing in `ago-deploy` currently
routes a public hostname to MinIO at all, so no presigned upload URL is reachable from outside the
cluster on this deployment today"). Both mentions call it "a pre-existing gap, not new here" and
point at each other rather than at a number — the honest record existed, the tracked item did not.

## Scope

- A new public hostname routed to the `minio` Service, **`:9000` (the S3 API) only — never `:9001`
  (MinIO's own admin web console)**, the same "no permanently internet-facing admin surface" instinct
  `gateway.yaml`'s own header already states for why `grafana.reserve-me.ru` was removed
  2026-08-25. Add the hostname to `k8s/overlays/demo/tls.yaml`'s `dnsNames` (an explicit SAN list, not
  a wildcard — confirmed by reading it) and add a `Gateway` listener + `HTTPRoute` in `gateway.yaml`
  following that file's own established pattern for every other single-Service route.
- Point `Storage__S3__ServiceUrl` at the new public HTTPS URL, for every host that constructs one
  (`ago-chat-api`, `ago-chat-worker` — check `ago-chat-webhooks` and the migrator too, since `5-02`'s
  own remarks say the option is shared config, not per-host). This is a deliberate simplification, not
  presumed final: it means the server's own admin calls to MinIO (bucket checks, `HeadObjectAsync`
  after an upload) also leave the cluster and come back in, rather than staying pod-to-pod — correct
  for this deployment's own scale, and the alternative (a second, presign-only URL setting) is real
  scope this item does not take on; name it as a follow-up if the extra hop turns out to matter, don't
  build it speculatively.
- Confirm the bucket's own access policy stays private — a presigned URL is self-authorizing by its
  own signature, so making the *network path* reachable must not also make the bucket *itself*
  publicly listable or readable without one. State what was checked, not assumed.
- Verify against the real live deployment, not only locally: a real presigned upload PUT and a real
  presigned download GET, each issued by the live API and then actually attempted from outside the
  cluster network (this machine, not `kubectl exec`), both succeeding.

## Out of scope

- A second, presign-only `ServiceUrl` split in `Ago.Platform.Storage.S3` itself (a platform-package
  change) — named above as a possible future refinement, not this item's own promise.
- Anything about the console's missing attachment-default toggle or the widget's own grant signal —
  real, separate findings from the same conversation, filed and worked as their own items.

## Done when

- [ ] A presigned upload PUT, issued by the live public API for a real granted conversation, succeeds
      from a real external network path (not from inside the cluster). **Blocked on the DNS record
      above** — the config that would make this possible is merged, unapplied.
- [ ] A presigned download GET, issued the same way, succeeds the same way. Same blocker.
- [x] The bucket's own access policy is confirmed to remain non-public — `seed/create-minio-bucket.sh`
      runs `mc mb --ignore-existing` (creates a private bucket, MinIO's own default) and `mc quota
      set`; no `mc anonymous set` or equivalent policy call exists anywhere in this repository. This
      change touches only network reachability, nothing about the bucket's own ACL.
- [ ] MinIO's own admin console (`:9001`) is confirmed **not** reachable through the new public route.
      Same blocker — the route does not exist on the live cluster until the config above is applied.
