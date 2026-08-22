# File storage port and S3/MinIO adapter

- **Stage**: 5
- **Status**: ready
- **Depends on**: nothing (a platform-level primitive; no product code changes)

## Goal

`IFileStorage` exists and is implemented against MinIO/S3, so `5-03` has a real port to build the
attachment upload/download flow on instead of inventing one under pressure. This item is `ago-platform`
only - no bucket policy, no attachment table, no endpoint. `file-storage.md`'s own port shape:

```
Task<PresignedUpload> CreateUploadAsync(ObjectKey key, UploadConstraints constraints, CancellationToken ct);
Task<Uri>             CreateDownloadUrlAsync(ObjectKey key, TimeSpan lifetime, CancellationToken ct);
Task<ObjectMetadata?> GetMetadataAsync(ObjectKey key, CancellationToken ct);
Task                  DeleteAsync(ObjectKey key, CancellationToken ct);
```

## Context to read first

`file-storage.md` in full - "The rule that shapes everything" (bytes never pass through the API) is
why every method here is presign-or-metadata, never a byte stream. `adr/0008` (presigned direct-to-
storage uploads - already accepted, this item is what makes it real). `repositories.md`'s "Why the
platform is a package, not a folder" and `adr/0012` - this is a new platform package, versioned and
published the same way `4-03`'s `Ago.Platform.Caching.Redis` addition was (`CHANGELOG.md` entry,
`dotnet pack`, consumed by `ago-chat` via `Directory.Packages.props`).

**A real inconsistency in the existing docs, found while reading them for this item**: `file-storage.md`
says `IFileStorage` lives in "`Application/Abstractions`" (i.e. `Ago.Chat.Application`), but the
`vertical-slice` skill's own guidance lists `IFileStorage` beside `ICache`/`IEventPublisher` as a
"generic technical" port that "already exists in `Ago.Platform.Abstractions` - reuse it, do not
duplicate." These cannot both be right: a product repository (`ago-chat`) cannot declare a port whose
implementation ships from a platform *package* it merely depends on - ownership runs the other way,
same as `IRateLimiter`/`ICache`/`IEventPublisher` today. Resolve this by treating the skill's version as
correct (matching every other technology-generic port this project has), implement `IFileStorage` in
`Ago.Platform.Abstractions`, and fix `file-storage.md`'s wording in the same change - do not silently
pick one without correcting the doc that disagrees.

## Scope

- `IFileStorage`, `ObjectKey`, `UploadConstraints`, `PresignedUpload`, `ObjectMetadata` in
  `Ago.Platform.Abstractions` - domain-free, no S3/MinIO type visible above this boundary
  (`clean-architecture.md`'s qualifying rule, same reasoning already applied to `IEventPublisher`/
  `ICache`).
- `Ago.Platform.Storage.S3` (new project): implements `IFileStorage` with the AWS SDK for .NET
  (`AWSSDK.S3`), pointed at MinIO's S3-compatible endpoint locally and any real S3-compatible provider
  in a real deployment - `file-storage.md`'s own framing ("the API is the same, so the deployment
  target stops being an architectural question"). Presigned PUT/GET generation, a `HeadObjectAsync`-
  backed `GetMetadataAsync` (the verification step `5-03` needs - a client's "uploaded" claim must
  never be trusted, per `file-storage.md`).
- Config: endpoint, bucket, credentials, presign lifetimes - bound the same way Postgres/RabbitMQ/
  Redis connection info already is (`docker/.env`/`infra-credentials`, never committed).
- Registration (`AddFileStorage(...)`) following `Ago.Platform.Caching.Redis`/`Ago.Platform.Messaging.
  RabbitMq`'s own `IServiceCollection` extension-method shape.
- `CHANGELOG.md` entry and a version bump (`dotnet pack`), same release mechanics as every other
  platform addition this project has made.

## Out of scope

- The `attachments` table, any endpoint, the thumbnail consumer, the orphan sweeper - all `5-03`/`5-04`,
  product code that consumes this port.
- Bucket creation/lifecycle policy as infrastructure-as-code (`ago-deploy`) - flagged as a real gap
  `5-03` must close (nothing today creates the bucket this adapter writes to), not solved here, since
  this item has no attachment feature yet to need a bucket for.
- Malware scanning - `file-storage.md`/`vision.md` already say this is out of scope, project-wide.

## Done when

- [ ] `Ago.Platform.Integration.Tests`: a real MinIO container (Testcontainers) - presign a PUT, upload
      bytes directly to the presigned URL (no `IFileStorage` call in between, proving the URL is
      genuinely usable by a bare HTTP client the way a browser would use it), then `GetMetadataAsync`
      confirms real size/content-type against what was actually stored.
- [ ] A presigned GET URL, used directly, returns the uploaded bytes.
- [ ] `DeleteAsync` against a real object, then `GetMetadataAsync` returns `null` - proves the sweeper
      `5-04` will build on a real delete, not an assumed one.
- [ ] A container-failure test (MinIO stopped): every method fails cleanly (a typed exception or a
      documented sentinel - decide and state which, matching this project's existing "advice vs throw"
      precedents for platform ports), never a raw SDK exception leaking through the port.
- [ ] `file-storage.md`'s "The port" section is corrected to say `Ago.Platform.Abstractions`, and a
      short note added explaining why (the ownership-direction reasoning above).
- [ ] `CHANGELOG.md` bumped; `ago-chat`'s `Directory.Packages.props` updated once `5-03` actually
      consumes the package (this item only needs the package to build and publish cleanly on its own).

## Open questions

**Needs the author's decision before `5-03`/`5-04` can be scoped precisely**: nothing in this item
itself is blocked, but `file-storage.md` never named a thumbnail library, and `CLAUDE.md` requires
stating what a new package replaces and why hand-rolling is worse before adding one. Recommendation for
`5-04` to confirm: `SixLabors.ImageSharp` (pure managed, no native dependency to containerize, active
maintenance) over `SkiaSharp` (native binding, heavier container image) - hand-rolling JPEG/PNG
decoding and resampling is clearly worse than either, so the real choice is between these two, not
whether to add a package at all.
