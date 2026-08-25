# File storage (attachments)

Visitors and operators send screenshots, invoices, and logs. Attachments are in scope; they are also
one of the few places where a naive design silently destroys throughput, which makes them worth
building properly.

Storage is S3-compatible: **MinIO** locally and in the k8s dev cluster, any S3 provider in the demo
deployment. The API is the same, so the deployment target stops being an architectural question.

## The rule that shapes everything

**File bytes never pass through the API process.** Uploads go browser -> object storage directly,
using a presigned URL; downloads go object storage -> browser, using a presigned GET. The API only
issues short-lived credentials and records metadata.

Streaming uploads through ASP.NET Core would tie up a request thread and a connection per upload,
put multi-megabyte buffers in a process that is also holding tens of thousands of WebSockets, and
make the API's memory profile depend on user behaviour. This decision is what keeps the concurrency
story in `concurrency.md` true.

## Upload flow

1. Client asks the API for an upload slot: declared content type, declared size. **Corrected in
   `16-01`**: this step said "filename" and the implementation never took one.
   `CreateAttachmentRequest` is `(ContentType, SizeBytes)`, and the object key's extension is looked up
   from the server's own content-type allowlist, never taken from the client
   (`CreateAttachmentHandler`). That is worth keeping deliberately rather than by accident: it is a
   security property (`AttachmentOptions`'s own remark - a client cannot graft an executable extension
   onto an object) *and* a data-minimisation one, since a visitor's filename is frequently personal
   data in its own right and never enters this system at all. Adding a "show the original filename"
   feature adds a column, a wire field and an export field, and belongs in `personal-data.md` the day
   it does.
2. API validates: per-site quota, per-visitor rate limit, size ceiling, extension/type allowlist.
   It creates an `attachments` row with state `pending` and returns a presigned PUT URL scoped to
   one object key, one method, one content type, **one exact byte count**, expiring in minutes.
   **Corrected in `5-13`**: the byte count is new. Until then the size ceiling existed only in this
   step — `CreateAttachmentHandler` compared the *declared* size against `AttachmentOptions.MaxSizeBytes`
   and then presigned a PUT that carried no size constraint at all, so a client that declared 1 KiB and
   PUT 4 GiB straight at the URL was bounded by nothing. A limit the application checks and the storage
   does not enforce is not a limit.
3. Client PUTs the bytes straight to storage.
4. Client tells the API "uploaded"; the API **verifies against storage** (HEAD: exists, real size,
   real content type) before flipping the row to `ready`. A client claim is never trusted.
5. The attachment is referenced by a message; the message is sent through the normal pipeline.
6. A background job in `Worker` sweeps `pending` rows older than the presign lifetime and deletes
   orphaned objects. Without this, every abandoned upload is a permanent leak.

Steps 4-6 are the part that separates a real design from a demo. Getting them into the doc now means
no session will "simplify" them away.

**Shipped in `5-04`**: step 6, `AttachmentOrphanSweepJob` (`Ago.Chat.Worker`) - a `PeriodicTimer`
sweep, same shape as `OperatorDisconnectSweepJob` (`4-04`). Not a load-then-decide: a single atomic
`DELETE ... WHERE state = 'Pending' AND created_at < @cutoff ... RETURNING` statement is the ordering
guarantee itself - Postgres evaluates that `WHERE` against the row's committed state at the moment the
statement executes, so a confirm that commits first is already excluded, and `FOR UPDATE SKIP LOCKED`
in the claiming subquery means a row an in-flight confirm is still updating (locked, uncommitted) is
skipped outright rather than blocking on it. Proven under real concurrency
(`AttachmentOrphanSweepJobTests`, two manually sequenced transactions, the same technique
`WaitingConversationClaimQueryTests` uses for its own `SKIP LOCKED` proof), not just by inspection.
Also **shipped in `5-04`**: image attachments get a thumbnail via `AttachmentThumbnailConsumer`,
reacting to the new `AttachmentConfirmed` integration event `ConfirmAttachmentHandler` now stages in
the same transaction as the state change (`messaging.md`'s own "Shipped in `5-04`" note has the wire
details). Idempotent by a plain read-then-write check (`ThumbnailKey is not null` skips regeneration),
safe because `Competing` mode never delivers the same message to two consumers simultaneously - proven
end to end against real Postgres, RabbitMQ, and MinIO (`AttachmentThumbnailEndToEndTests`).

**Shipped in `5-03`**: steps 1-5, in `ago-chat`. `POST /api/v1/conversations/{id}/attachments`
(step 1-2 - nested under the conversation, since the participant/quota check needs that context),
`POST /api/v1/attachments/{id}/confirm` (step 4, standalone by id), `GET /api/v1/attachments/{id}`
(the read side of Access control below). Both routes accept either a visitor or an operator token on
one endpoint - the first in this codebase to do that (every hub before this was single-role by
construction) - disambiguated by a new `kind` JWT claim, since the two schemes' `aud` values alone
answer "is this token valid for this route" but not "which principal is this handler talking to".
Since `17-06`/`adr/0034` the claim is also *required* by the route's own authorization policy, not
merely read by the handler: a Keycloak token that resolves to no operator is neither kind, and used to
be classified as a visitor by default (nothing was reachable through it - the participant checks below
still applied - but the route now rejects it outright).
Step 5 (`SendVisitorMessage`/`SendOperatorMessage` gaining an optional attachment reference,
validated - exists, `Ready`, belongs to this conversation - inside `MessageBatchWriter`'s own
transaction, `4-05`) is proven at the pipeline level, not the domain level: `Attachment` is its own
aggregate (below), so the check runs read-only before either aggregate is touched, and only links the
two (`Attachment.LinkToMessage`) once the message itself has actually landed - see
`MessageBatchWriter`'s own remarks for why that ordering matters under a batch-wide rollback. Step 6
(the orphan sweep) is explicitly **not** shipped - `5-04`'s job, per `5-03`'s own Out-of-scope list.
Per-site/per-visitor/per-operator rate limits use the `3-05` two-bucket shape widened to three
(`AttachmentRateLimitOptions`) - a visitor and an operator can both create attachments, so each gets
its own budget on top of the shared per-site one.

Not shipped by `5-03`, a real gap: `GetAttachmentDownloadUrl` never sets `Content-Disposition` or a
response CSP override on the presigned GET, because doing so needs a platform-port change
(`IFileStorage.CreateDownloadUrlAsync` has no override parameter today) that a single-repository
`ago-chat` branch cannot make on its own. Deferred, not hidden.

## Access control

Objects are private. Reads are served through short-lived presigned GET URLs issued by the API after
an authorisation check: does this caller belong to this conversation. Object keys are
`site/{site_id}/conv/{conversation_id}/{uuid7}{ext}` - key structure is never the security boundary,
because guessable-or-not is not an access-control model.

Presigned read URLs are cached per (attachment, viewer) for slightly less than their lifetime, so a
chat history render of 20 images is one round trip's worth of signing, not 20.

## Validation and safety

- Size ceiling per file and per conversation, enforced at presign time and re-verified after upload.
  **Two layers since `5-13`, and they answer different questions.** The ceiling itself is the
  application's (`CreateAttachmentHandler` vs `AttachmentOptions.MaxSizeBytes`) — storage cannot know a
  product's quota. What storage now enforces is that the upload is *the size it declared*: the declared
  length is signed into the presigned PUT (`GetPreSignedUrlRequest.Headers.ContentLength`), SigV4's
  canonical request covers every header named in `X-Amz-SignedHeaders`, and MinIO recomputes the
  signature over the real request's own `Content-Length` and answers `403 SignatureDoesNotMatch` before
  accepting a byte. Verified against a real MinIO container, not assumed from AWS's documentation
  (`S3FileStorageTests`, oversized and undersized, both PUT at the URL directly with no use case
  involved). The signed value is **exact, not a bound** — a presigned PUT cannot express a range at all;
  `content-length-range` is a presigned-*POST* policy condition, and adopting it would mean every browser
  client switching from a raw PUT to a multipart form POST for the same outcome. That is why
  `UploadConstraints.MaxSizeBytes` became `UploadConstraints.SizeBytes` in `Ago.Platform.Abstractions`
  `0.16.0`: the port had been promising a ceiling it never enforced and now cannot express.
  Step 4's HEAD re-verification is unchanged and still runs — it is the layer that decides whether an
  object counts as *usable*, and it remains the only check on the content type the store actually
  recorded. The distinction worth keeping straight: HEAD can refuse to mark an attachment `ready`, it
  can never refuse the write, which is exactly the gap `5-13` closed.
- Content type sniffed from the first bytes server-side for images, not trusted from the client.
  **Not actually shipped as written**: `5-03`'s HEAD-verify trusts whatever Content-Type MinIO/S3
  itself reports for the object (an improvement over trusting the client's own pre-upload claim, since
  it reflects what the PUT request's own header declared to the object store) - it does not decode the
  first bytes to confirm the file is genuinely a PNG/JPEG/etc. True magic-byte sniffing is unbuilt;
  noted here rather than left to look done.
- Images get a thumbnail generated asynchronously in `Worker` (a broker-driven job, so it is a
  natural second consumer with a different scaling profile from the message consumer).
  **Shipped in `5-04`** - see the Upload flow section's own note.
- Downloads are served with `Content-Disposition: attachment` and a restrictive `Content-Security-Policy`
  so a stored HTML file can never execute in the site's origin. **Not shipped** - the Upload flow
  section's own "not shipped by `5-03`" note has the reason (needs a platform-port change).
- Malware scanning is out of scope, and `vision.md` says so explicitly rather than leaving a reviewer
  wondering whether we forgot.

## The port

`IFileStorage` in `Ago.Platform.Abstractions` - **corrected in `5-02`**: earlier drafts of this doc
said "`Application/Abstractions`" (i.e. a product's own project), which cannot be right - a product
repository cannot declare a port whose only implementation ships from a platform *package* it merely
depends on, ownership runs the other way, the same as `ICache`/`IEventPublisher`
(`clean-architecture.md`'s qualifying rule). `ObjectKey` is a plain string wrapper, the same shape as
`CacheKey` and for the same reason: the port never knows a product's own namespacing scheme
(`site/{site_id}/conv/{conversation_id}/{uuid7}{ext}`, below), only the finished key.

```
Task<PresignedUpload> CreateUploadAsync(ObjectKey key, UploadConstraints constraints, CancellationToken ct);
Task<Uri>             CreateDownloadUrlAsync(ObjectKey key, TimeSpan lifetime, CancellationToken ct);
Task<ObjectMetadata?> GetMetadataAsync(ObjectKey key, CancellationToken ct);
Task                  DeleteAsync(ObjectKey key, CancellationToken ct);
```

**Shipped in `5-02`**: `Ago.Platform.Storage.S3` (AWS SDK, pointed at MinIO locally via
`S3StorageOptions.ServiceUrl` - MinIO is S3-API-compatible, so no MinIO-specific client exists or is
needed). No `AmazonS3Client`, no bucket name, and no SDK type ever appears above the Infrastructure
boundary - the use case knows "a place to put a file", which is the entire reason the port exists.
Every call runs through a shared `ResiliencePipeline` (retry, per-attempt timeout, circuit breaker -
`resilience.md`'s S3/MinIO row) and throws `FileStorageUnavailableException` once that is exhausted -
unlike `ICache` there is no sensible fallback for "could not presign an upload"; `GetMetadataAsync`
treats a `404` as the expected "does not exist" outcome, excluded from both retry and the breaker's
failure count, not a failure. A real AWS-SDK quirk found live: `GetPreSignedUrlRequest.Protocol` -
not `AmazonS3Config.UseHttp` - is what actually controls a presigned URL's own scheme; `UseHttp`
alone still left presigned URLs as `https://` against a plain-HTTP local MinIO, failing the TLS
handshake the moment a client tried to use one.

Still open, not solved by `5-02` **or** `5-03`: nothing in `ago-deploy` creates the real bucket this
adapter writes to yet - every test across both repositories still creates its own via the S3 API
directly (`AttachmentFixture`, `MinioFixture`), and `5-03`'s own endpoints only ever read
`S3StorageOptions.Bucket` from config, they never provision it. This mirrors the project's own
established precedent for schema, not code: EF migrations are applied by an explicit
`dotnet ef database update` tooling step (`k8s-local.md`'s "Migrations and seeding" section), never
an app-startup side effect, because `Microsoft.EntityFrameworkCore.Design` is deliberately excluded
from the shipped image. Bucket creation deserves the same "explicit operational step, not implicit
app-startup magic" treatment - most likely an `ago-deploy` script or a `mc`/AWS-CLI one-shot alongside
the existing seed scripts - but no session has actually written that step yet. Flagging it again here
rather than silently carrying it forward a second time.

**Also still open, found live while verifying `5-10`**: neither `k8s/base/api.yaml` nor
`k8s/base/worker.yaml` sets any `Storage__S3__*` env var at all, even though `minio.yaml` deploys the
service both hosts need it for - the full k8s-cluster deployment path (`k8s-local.md`) has never
actually exercised an attachment upload, only the docker-compose fast loop has (`local-dev.md`, where
each host's own `appsettings.Development.json` supplies it locally). Unrelated but found the same way:
`k8s/base/worker.yaml` was also missing `Redis__ConnectionString` - `Ago.Chat.Worker` crashed at
startup with `Set Redis:ConnectionString` the moment it was actually run locally, since `4-04`'s
`OperatorDisconnectGraceConsumer`/`OperatorDisconnectSweepJob` need `IConnectionRegistry` and
`ChatModule` wires that up unconditionally for every host - fixed in that file and in
`Ago.Chat.Worker/appsettings.Development.json` as part of `5-10`'s own live verification, since it
blocked verifying the fan-out path at all. The `Storage__S3__*` gap is not fixed here - it needs the
same secret-naming reasoning (`MINIO_ROOT_USER`/`PASSWORD` vs. `AccessKey`/`SecretKey`) `api.yaml`'s
existing env vars already had to work out for Postgres/RabbitMQ, which is more than this item's own
scope justifies taking on.

## Data model addition

`attachments`: `id` (uuid v7), `site_id`, `conversation_id`, `message_id?`, `object_key`,
`content_type`, `size_bytes`, `state` (`pending|ready|deleted`), `created_at`, `thumbnail_key?`.
The message references the attachment, not the other way round, so an attachment can exist briefly
before its message does. **Shipped in `5-03`** (`Ago.Chat.Domain.Attachment`, its own aggregate -
see that type's own remarks on why bundling it into `Conversation` would break "one aggregate per
transaction"); `data-model.md` has the full column list and the reasoning for why neither
`attachments.message_id` nor `messages.attachment_id` carries a real foreign key (`messages` is
range-partitioned, so Postgres cannot target `messages(id)` alone). `thumbnail_key` is reserved by
the column, not by any writer - `5-04`'s async thumbnail job is the intended one.
