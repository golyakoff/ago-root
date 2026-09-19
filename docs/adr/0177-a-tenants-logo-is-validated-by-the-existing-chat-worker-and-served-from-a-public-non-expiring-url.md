# ADR-0177: A tenant's logo is validated by the existing Chat Worker, and served from a public, non-expiring URL

- **Status**: Accepted
- **Date**: 2026-09-19
- **Stage**: 25

## Context

`25-160` lets a tenant upload a small logo image to brand its own outbound reply email
(`TenantReplyEmailShell`, `25-156`'s text-only shell). Two decisions in that item's design carry real
architectural weight, both reached with the author before any code was written:

**How the upload gets validated.** Decoding an uploaded image, confirming its real pixel dimensions,
confirming its format, and confirming it is not an animated GIF is real work that must not block the
HTTP request that accepts the upload - a tenant should not wait on a synchronous image decode inside a
console click. That work needs an asynchronous home. `Ago.Chat.Worker` already owns exactly this class
of job: `AttachmentThumbnailGenerator` (`5-04`) already decodes, resizes and re-encodes chat-attachment
images with SkiaSharp, downloading and uploading through presigned URLs the same way a browser would
(`IFileStorage` is presign-only by design, `adr/0008`). The question was whether this new job deserves
its own deployable - a small "Image Processing Service" - or whether it is one more consumer inside the
Worker that already does this.

**How the finished logo gets served.** A validated logo has to reach two different readers: the
`EmailChannelAdapter` composing a reply (server-side, needs the raw bytes to inline as base64 with
`Content-ID`, so the image renders even when the recipient's mail client blocks remote image loads), and
the console's own settings screen (client-side, an ordinary `<img>` preview). Every existing
attachment-facing read in this codebase goes through `IFileStorage.CreateDownloadUrlAsync` - a presigned,
time-limited GET, correct for a private, short-lived chat attachment. A logo is neither: it must still
resolve weeks later when a visitor opens an old reply email, and it is not sensitive data an
authorization check needs to gate. The question was whether to reuse the presigned-per-viewer model
anyway, or to serve the logo from a different kind of URL entirely.

Both questions were the kind of fork a reviewer would ask "why not the existing pattern" about, so both
are recorded here rather than left implicit in the code.

## Decision

**Validation runs as a new, ordinary `Competing` consumer inside `Ago.Chat.Worker`** -
`SiteLogoValidator`/`SiteLogoValidationConsumer`, the direct sibling of
`AttachmentThumbnailGenerator`/`AttachmentThumbnailConsumer`. The upload endpoint
(`Ago.Chat.Api`) does only cheap, decode-nothing checks (byte-size ceiling, rate limit) and stages a
`SiteLogoValidationRequested` event in the outbox in the same transaction that records the `pending`
status; the new consumer downloads the pending object, decodes it with SkiaSharp (already a dependency
of this repository, not a new one), confirms real dimensions, format, and single-frame-ness, and either
promotes the object to a public key or records a rejection reason. No new deployable, no new scaling
group, no new failure mode beyond the ones this Worker already has.

**The finished logo is served from a plain, non-expiring URL, not a presigned one.** The permanent
object key sits under its own prefix (`site/{siteId}/logo/...`, distinct from the `pending` prefix the
upload uses) so a deployment's own MinIO/S3 bucket policy can grant anonymous `GET` on that prefix alone.
`Ago.Chat.Api`/`Ago.Chat.Module` compute this URL directly (`ISiteLogoPublicUrlBuilder`, a small
product-level port - `IFileStorage` gets no new method) by joining the deployment's already-public S3
service URL (`25-103`) to the object key, with ordinary HTTP `Cache-Control` semantics instead of SigV4
expiry. The email-composition read path additionally caches the already-base64-encoded bytes in Redis,
write-through populated by the validating consumer itself the moment it finishes decoding - a second,
independent decision about *that one caller's* performance, not about how the object is addressed, and
not what this ADR is about.

## Consequences

**Positive:**

- One Worker to operate, one broker, one set of dashboards - a second consumer on an existing process is
  strictly additive to what this deployment already runs and monitors.
- The logo survives indefinitely with no renewal mechanism to build or forget - a visitor opening a
  six-month-old reply email still sees a working `<img>` tag in the console's own preview, and the email
  itself never depended on the URL at all (it inlines the bytes).
- No new package: SkiaSharp, presigned-upload-then-`HttpClient`-PUT, and `Competing` subscriptions are
  all patterns this codebase already runs in production for chat attachments.

**Negative, or accepted as a real cost:**

- A public object-storage prefix is a real, if narrow, exposure: anyone who learns or guesses a logo's
  object key can fetch it with no authorization check, for as long as the tenant keeps that logo. This is
  judged acceptable because a logo is not sensitive - it is the same image already visible to the public
  on the tenant's own storefront - but it is a deliberate trade against the presigned model's stronger
  default, not a free lunch.
- The bucket-policy change that actually makes the public prefix readable is an operational step outside
  this item's own code (the same "explicit operational step, not implicit app-startup magic" gap
  `file-storage.md` already records for MinIO CORS configuration) - this item's own code assumes it is
  done, not that it does it.
- `ISiteLogoPublicUrlBuilder`'s implementation re-reads the same `Storage:S3` configuration section
  `Ago.Platform.Storage.S3`'s own `AddS3FileStorage` already binds internally, rather than the platform
  package exposing that value itself - a small duplication accepted because the alternative is a platform
  (`ago-platform`) change with only one caller today.
- If a second product ever needs the identical "validate a small tenant-uploaded image, serve it from a
  public URL" shape, the trigger is to extract a shared library, not to stand up the hosted service this
  decision declined to build now (the same `ago-platform`-as-NuGet precedent `adr/0012` already
  established for a different kind of sharing).

## Alternatives considered

- **A standalone "Image Processing Service."** Rejected: decoding and validating a small image is a
  pure, stateless function; wrapping it in its own deployable adds a network boundary, its own scaling
  group and its own failure mode for what is really a library call already proven inside this Worker.
  The platform-layer "premature generalisation" warning (`clean-architecture.md`) applies here even
  though the deployable in question would be product-level, not platform-level.
- **Reusing the presigned-per-viewer model `IFileStorage`/attachments already use.** Rejected: a chat
  attachment is private and short-lived by design; a logo is neither. Re-signing or expiring a URL a mail
  client has no way to refresh would either break old emails or require a renewal mechanism this feature
  has no reason to need.
- **A dedicated Postgres `blobs` table instead of object storage.** Not seriously pursued: object storage
  already has the exact port (`IFileStorage`) and CDN/browser-cache-friendly HTTP semantics this needs; a
  Postgres table would still need its own caching layer in front to avoid a database hit on every email,
  and would compete with hot OLTP tables for buffer cache and WAL for no offsetting benefit.
- **Building or measuring a CDN in front of the public hostname now.** Deferred, not rejected: the
  browser's own HTTP cache is what this item relies on today; a CDN is a future, separate, measured
  improvement if traffic ever justifies it - `CLAUDE.md`'s "performance claims need numbers" applies to a
  decision that has not been measured yet.
