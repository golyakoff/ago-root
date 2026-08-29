# Fix: a presigned upload's declared size is never actually enforced by S3/MinIO itself

- **Stage**: 5 — **scheduled into Stage 15** (2026-08-24). Kept at its original number because a
  dozen docs already reference `5-13`; renumbering a file to record a scheduling decision would
  break those references to no benefit. It belongs to Stage 15's work because it was found while
  investigating the public deployment's disk-exhaustion exposure, and it is the one path by which a
  stranger can write unbounded bytes to the node's shared disk (`15-05`) — **corrected 2026-08-29**:
  there never was a 2Gi ceiling to write past; `local-path` applies no quota, so the target is the
  node's shared free space (58G measured 2026-08-29), less urgent by volume than a 2Gi ceiling would
  have made it, worse in kind, since filling it takes down every component at once rather than one.
- **Status**: done (`ago-platform` `0.16.0`) — the declared length is signed into the presigned PUT
  (`GetPreSignedUrlRequest.Headers.ContentLength`) and MinIO refuses a mismatched request with
  `403 SignatureDoesNotMatch` before accepting a byte. Proven at the storage layer, not the
  application's: both new tests PUT straight at the presigned URL with no use case involved, and both
  failed against the pre-fix code with `Expected: Forbidden, Actual: OK` (a 4096-byte PUT stored
  happily against a URL presigned for 64 bytes). 79 tests green, zero warnings. One thing this item
  did not anticipate: the mechanism can only sign an *exact* length, never a ceiling, so
  `UploadConstraints.MaxSizeBytes` was renamed to `SizeBytes` — see Scope below.
  **Still required, not done here**: `ago-chat` pins exact package versions, so the fix does not reach
  it until `Directory.Packages.props` moves to `0.16.0`.
- **Depends on**: nothing — `ago-platform`'s `Ago.Platform.Storage.S3` only

## Goal

`CreateAttachmentHandler` checks a client's *declared* size against `AttachmentOptions.MaxSizeBytes`
(10 MiB) before presigning, but the presigned PUT URL itself carries no size constraint — a client
can declare a small size, then upload an arbitrarily large object directly to the presigned URL,
bypassing the ceiling entirely. After this item, the actual byte count is enforced at the storage
layer, not just checked against a value the uploader fully controls.

## Context to read first

Found live while investigating disk-exhaustion exposure for `docs/backlog/8-05-*`'s public demo
(2026-08-24) — not exploitable *today* (see below), but a real gap in the mechanism itself.
`Ago.Platform.Storage.S3/S3FileStorage.cs`'s `CreateUploadAsync` — presigns a plain `PUT` with only
`ContentType` and an expiry; `UploadConstraints.MaxSizeBytes` is captured in the record but never
read by this method at all. `ConfirmAttachmentHandler`/`Attachment.ConfirmReady` do re-verify the
*actual* uploaded object's size against the *declared* size after the fact (`5-03`'s own Done-when:
"mismatched size... fails, stays pending") — but that check runs after the bytes are already sitting
in storage; it can only ever refuse to mark the attachment `Ready`, not prevent the write. The
`AttachmentOrphanSweepJob` (`5-04`) does clean up an unconfirmed row and its storage object after
`UploadLifetime` (10 minutes) — a real backstop, but it bounds exposure to minutes per object, not
bytes per object.

**Why this is not exploitable on the live public deployment today**: `Storage__S3__ServiceUrl` is
`http://minio:9000` — cluster-internal DNS, not reachable from outside the cluster at all (`minio`'s
own Service carries no public Gateway route). A presigned URL handed to a real external visitor is
therefore already unusable, confirmed live: a real presign request against `https://chat.reserve-me.ru`
returned `uploadUrl: "http://minio:9000/..."`, which no external browser can resolve. Attachments are
functionally broken for any real visitor right now — a separate, known gap, not fixed here (fixing
*that* would require deciding how to expose MinIO publicly first, which is exactly the decision that
would reopen this item's own concern if made without this fix landing first).

## Scope

- `S3FileStorage.CreateUploadAsync`: add `constraints.MaxSizeBytes` as a signed `Content-Length`
  header on the presigned PUT request (`GetPreSignedUrlRequest.Headers`) — the AWS SDK includes any
  header set there in the canonical request the signature covers, so the actual PUT must carry that
  exact `Content-Length` or S3/MinIO rejects the signature outright, before accepting a single byte.
  **Done.** Consequence this item's own wording did not follow through on: the mechanism signs one
  exact number, so the field stopped being a ceiling the moment it started being enforced. Keeping the
  name `MaxSizeBytes` would have left the port promising a bound it cannot express — a presigned PUT
  has no range condition at all (`content-length-range` belongs to a POST policy, which this item's
  Out-of-scope already rejected). Renamed to `UploadConstraints.SizeBytes`, with the ceiling staying
  where it always actually lived: `CreateAttachmentHandler`'s own check against
  `AttachmentOptions.MaxSizeBytes`, before it declares anything.
- Confirm MinIO (not just AWS S3) honors a signed `Content-Length` header the same way — a real
  integration-test assertion against the Testcontainers MinIO instance this project's own S3 tests
  already use, not assumed from AWS's own documented behavior alone. **Done**: MinIO
  `RELEASE.2025-09-07T16-13-09Z` answers `403 SignatureDoesNotMatch`, asserted by error code rather
  than by "not 2xx" — a bare non-success assertion would pass on a typo in the URL and prove nothing
  about the signature.
- `ago-widget`'s `uploadToPresignedUrl` (and `ago-console`'s equivalent): confirm neither one
  overrides or strips a `Content-Length` header on its own `fetch`/XHR call in a way that would
  conflict with the signed value (browsers normally set this automatically from the actual body size,
  which is exactly what needs to match — this is a verification step, not expected to need a code
  change). **Verified, no change needed**: both are `xhr.send(file)` with only `Content-Type` set by
  hand, and both declare `file.size` at presign time, so the browser's own `Content-Length` is the
  same number that was signed. `Content-Length` is a forbidden header name in both `fetch` and XHR, so
  neither client could override it even deliberately.

## Out of scope

- Exposing MinIO publicly so attachments actually work for a real external visitor — a separate
  decision (a public route, a CDN, or switching the presign to reflect a public-facing endpoint while
  still routing to the same bucket) with its own trade-offs, not this item's job. This item exists
  so that decision, whenever it's made, doesn't reopen the size-enforcement gap by construction.
- Presigned POST + policy document (`content-length-range` condition) as an alternative mechanism —
  the signed-header approach is a smaller change to an already-working PUT flow; POST would need
  `ago-widget`'s upload code to switch from a raw `PUT` to a multipart form `POST`, a larger change
  for the same outcome.

## Done when

- [x] A real MinIO integration test proves a PUT with a mismatched `Content-Length` against a
      presigned URL fails at the storage layer, not just at `ConfirmAttachmentHandler`. Two:
      oversized and undersized, both PUT directly at the URL with no use case in the picture.
- [x] The existing size-ceiling test (`declaredSizeBytes > options.MaxSizeBytes` → rejected before
      presigning) still passes unchanged — this item adds a second, storage-level enforcement layer,
      it does not replace the existing declared-size check. That test lives in `ago-chat` and is
      untouched; it constructs no `UploadConstraints` of its own, so the rename does not reach it.
- [x] `file-storage.md` updated to state the two-layer enforcement (declared-size check before
      presigning, signed `Content-Length` enforced by the store itself) as shipped fact.

## Follow-up for the `ago-chat` side (not this branch's lane)

- Bump `Ago.Platform.*` to `0.16.0` in `Directory.Packages.props`. Nothing in `ago-chat` needs a code
  change: `CreateAttachmentHandler` and `AttachmentThumbnailGenerator` both construct
  `UploadConstraints` positionally with the exact size they intend to upload, so the rename is
  source-compatible for both.
- One comment goes stale, not one test. `AttachmentUploadFlowTests.Confirm_WhenTheUploadedBytesDontMatchTheDeclaredSize_FailsAndStaysPending`
  still passes — it never asserts the PUT succeeded, and confirm still fails with
  `Attachment.VerificationFailed`, now because the object is absent rather than because it was the
  wrong size. Its inline comment ("even though the presigned PUT itself succeeded") is what becomes
  untrue, and the test is arguably worth re-pointing at the case it now actually covers.

## Open questions

None — the mechanism (a signed header S3/MinIO must match) is a documented AWS SDK capability; the
only real unknown is confirming MinIO's own presigned-URL implementation honors it identically,
which this item's own Scope makes a required, verified step rather than an assumption.
