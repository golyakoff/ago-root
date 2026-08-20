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

1. Client asks the API for an upload slot: filename, declared content type, declared size.
2. API validates: per-site quota, per-visitor rate limit, size ceiling, extension/type allowlist.
   It creates an `attachments` row with state `pending` and returns a presigned PUT URL scoped to
   one object key, one method, one content type, expiring in minutes.
3. Client PUTs the bytes straight to storage.
4. Client tells the API "uploaded"; the API **verifies against storage** (HEAD: exists, real size,
   real content type) before flipping the row to `ready`. A client claim is never trusted.
5. The attachment is referenced by a message; the message is sent through the normal pipeline.
6. A background job in `Worker` sweeps `pending` rows older than the presign lifetime and deletes
   orphaned objects. Without this, every abandoned upload is a permanent leak.

Steps 4-6 are the part that separates a real design from a demo. Getting them into the doc now means
no session will "simplify" them away.

## Access control

Objects are private. Reads are served through short-lived presigned GET URLs issued by the API after
an authorisation check: does this caller belong to this conversation. Object keys are
`site/{site_id}/conv/{conversation_id}/{uuid7}{ext}` - key structure is never the security boundary,
because guessable-or-not is not an access-control model.

Presigned read URLs are cached per (attachment, viewer) for slightly less than their lifetime, so a
chat history render of 20 images is one round trip's worth of signing, not 20.

## Validation and safety

- Size ceiling per file and per conversation, enforced at presign time and re-verified after upload.
- Content type sniffed from the first bytes server-side for images, not trusted from the client.
- Images get a thumbnail generated asynchronously in `Worker` (a broker-driven job, so it is a
  natural second consumer with a different scaling profile from the message consumer).
- Downloads are served with `Content-Disposition: attachment` and a restrictive `Content-Security-Policy`
  so a stored HTML file can never execute in the site's origin.
- Malware scanning is out of scope, and `vision.md` says so explicitly rather than leaving a reviewer
  wondering whether we forgot.

## The port

`IFileStorage` in `Application/Abstractions`:

```
Task<PresignedUpload> CreateUploadAsync(ObjectKey key, UploadConstraints constraints, CancellationToken ct);
Task<Uri>             CreateDownloadUrlAsync(ObjectKey key, TimeSpan lifetime, CancellationToken ct);
Task<ObjectMetadata?> GetMetadataAsync(ObjectKey key, CancellationToken ct);
Task                  DeleteAsync(ObjectKey key, CancellationToken ct);
```

Implemented in `Ago.Platform.Storage.S3` (AWS SDK, pointed at MinIO locally). No `AmazonS3Client`,
no bucket name, and no SDK type ever appears above the Infrastructure boundary - the use case knows
"a place to put a file", which is the entire reason the port exists.

## Data model addition

`attachments`: `id` (uuid v7), `site_id`, `conversation_id`, `message_id?`, `object_key`,
`content_type`, `size_bytes`, `state` (`pending|ready|deleted`), `created_at`, `thumbnail_key?`.
The message references the attachment, not the other way round, so an attachment can exist briefly
before its message does.
