# Attachment thumbnails and orphan sweep

- **Stage**: 5
- **Status**: done
- **Depends on**: `5-03-attachments-upload-and-download.md`

## Goal

The two background jobs `file-storage.md` names but `5-03` deliberately leaves out: an image
attachment gets a thumbnail without blocking the upload confirmation, and an abandoned upload (client
presigned a PUT, never finished, or never confirmed) does not leak an object in storage forever.

## Context to read first

`file-storage.md`'s "Upload flow" step 6 and "Validation and safety"'s thumbnail bullet. `5-03`'s own
file for the exact `attachments` schema and confirm-endpoint shape this item reacts to.
`messaging-contract` skill and `2-04`'s `OutboxDispatcher`/Worker-consumer precedent - thumbnailing is
"a broker-driven job, so it is a natural second consumer with a different scaling profile from the
message consumer" (`file-storage.md`'s own words), meaning this is an outbox-event-driven `Worker`
consumer, not a job polling the `attachments` table directly. `concurrency.md`'s `PeriodicTimer`/
`BackgroundService` rules for the sweeper.

## Scope

- An `AttachmentReady` integration event (`Ago.Chat.Contracts`), staged to the outbox in the same
  transaction as `5-03`'s confirm step flipping `pending` -> `ready` (`adr/0005` - the same rule every
  other write in this project follows).
- `AttachmentThumbnailConsumer` (`Ago.Chat.Worker`): reacts to `AttachmentReady` for image content
  types only, downloads the object (via `IFileStorage`, not a raw SDK call), generates a thumbnail
  (the library `5-02`'s Open question flags - confirm the choice here since this is the first and only
  consumer of it), uploads it back under a derived key, and updates the attachment row's
  `thumbnail_key`. Idempotent - a redelivered `AttachmentReady` for an attachment that already has a
  `thumbnail_key` is a no-op, not a duplicate thumbnail (`2-05`'s idempotency precedent).
- `AttachmentOrphanSweepJob` (`Ago.Chat.Worker`, `PeriodicTimer`): finds `attachments` rows still
  `pending` older than the presign lifetime (`5-02`'s config) and deletes both the row and, if present,
  the storage object (`IFileStorage.DeleteAsync` - tolerate "already gone", never fail the sweep over
  a race with a confirm that landed a moment earlier). State the sweep interval as an unmeasured
  starting point, same as every other timer in this project.
- Both jobs registered in `Ago.Chat.Worker`'s `Program.cs`, matching every other Worker job's
  registration shape (`4-02`'s `ConversationAssignmentJob`, `4-04`'s sweep/grace jobs).

## Out of scope

- Thumbnailing non-image attachments (PDFs, logs) - `vision.md`/`file-storage.md` only describe image
  thumbnails; a generic preview system is not asked for.
- Re-thumbnailing on demand (a UI "regenerate thumbnail" action) - nothing calls for it yet.

## Done when

- [x] `Ago.Chat.Integration.Tests`: confirming an image attachment (`5-03`'s flow) results in a real
      thumbnail object in storage and `thumbnail_key` populated, against real Postgres/RabbitMQ/MinIO.
      `AttachmentThumbnailEndToEndTests` - its own, non-shared containers (matching
      `UnreadCounterEndToEndTests`' own reasoning), the real `OutboxDispatcher` and the real
      `AttachmentThumbnailConsumer`, nothing stubbed.
- [x] Redelivering the same event twice results in exactly one thumbnail object, not two, and no
      error - the idempotency proof. `AttachmentThumbnailGeneratorTests.GenerateAsync_CalledTwiceForTheSameAttachment_IsIdempotent`
      (real Postgres + MinIO), proving the actual guarantee (`ThumbnailKey is not null` skips
      regeneration) directly rather than orchestrating a genuine RabbitMQ nack/redelivery.
- [x] `Ago.Chat.Integration.Tests`: a `pending` attachment older than the presign lifetime is deleted
      (row and object) by the sweep; a `pending` attachment younger than that, and a `ready` one of any
      age, are left alone. `AttachmentOrphanSweepJobTests`, three cases.
- [x] A race proven, not just handled by inspection: an attachment confirmed *during* a sweep tick is
      not deleted. The ordering guarantee: `AttachmentOrphanSweepQuery` is a single atomic
      `DELETE ... WHERE state = 'Pending' ... RETURNING` statement, not a select-then-delete - Postgres
      evaluates that `WHERE` against committed state at execution time, and `FOR UPDATE SKIP LOCKED` in
      the claiming subquery means a row an in-flight confirm is still updating (locked, uncommitted) is
      skipped outright rather than blocked on. Proven with two manually sequenced transactions
      (`AttachmentOrphanSweepJobTests.SweepAsync_SkipsARowLockedByAnInFlightConfirm_NeverDeletingIt`),
      the same technique `WaitingConversationClaimQueryTests` uses for its own `SKIP LOCKED` proof.
- [x] `file-storage.md` gets a "Shipped in `5-04`" note.

## Open questions - resolved

Thumbnail library: **SkiaSharp**, not the `5-02`-recommended `SixLabors.ImageSharp` - the author's own
call once the two licenses were compared. `SkiaSharp` is MIT, unconditionally free for commercial use;
`ImageSharp` is the "Six Labors Split License" (free under a $1M annual-revenue threshold for a direct
dependency, paid above it, and as of `v4.0.0` requires a license file just to compile even under the
free tier). Costs a native binding (heavier container image, a `SkiaSharp.NativeAssets.*` package per
target platform) instead of ImageSharp's pure-managed one - accepted for the licensing certainty.

**New gap surfaced, not closed here**: `Attachment.ConfirmReady`'s HEAD-verify trusts whatever
Content-Type MinIO/S3 itself reports for the object, not true first-bytes content sniffing -
`file-storage.md`'s "Validation and safety" section originally implied the latter; corrected in the
same change as this close-out rather than left to look done.
