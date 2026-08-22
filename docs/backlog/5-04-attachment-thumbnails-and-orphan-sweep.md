# Attachment thumbnails and orphan sweep

- **Stage**: 5
- **Status**: ready
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

- [ ] `Ago.Chat.Integration.Tests`: confirming an image attachment (`5-03`'s flow) results in a real
      thumbnail object in storage and `thumbnail_key` populated, against real Postgres/RabbitMQ/MinIO.
- [ ] Redelivering the same `AttachmentReady` event twice results in exactly one thumbnail object, not
      two, and no error - the idempotency proof.
- [ ] `Ago.Chat.Integration.Tests`/`Concurrency.Tests`: a `pending` attachment older than the presign
      lifetime is deleted (row and object) by the sweep; a `pending` attachment younger than that, and
      a `ready` one of any age, are left alone.
- [ ] A race proven, not just handled by inspection: an attachment confirmed *during* a sweep tick (the
      sweep's own query already selected it as a candidate, the confirm lands before the delete runs)
      is not deleted - state which ordering guarantee prevents this (e.g. the sweep re-checks state
      immediately before deleting, inside the same transaction that would delete it) and prove it under
      concurrency.
- [ ] `file-storage.md` gets a "Shipped in `5-04`" note.

## Open questions

None beyond `5-02`'s already-flagged thumbnail-library choice, which this item is what actually needs
it decided.
