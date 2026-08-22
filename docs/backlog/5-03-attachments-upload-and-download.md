# Attachments: presign, verify, and the download path

- **Stage**: 5
- **Status**: done
- **Depends on**: `5-02-file-storage-port-and-s3-adapter.md` (needs `IFileStorage` published and
  consumable), `5-01-per-site-cors.md` (the presign/confirm endpoints are widget-facing - CORS must
  already cover new endpoints generically, or this item extends the same policy explicitly)

## Goal

A visitor or operator can attach a file to a conversation and the other side can view it -
`file-storage.md`'s full upload flow (steps 1-5; the background sweep is `5-04`) plus the read side
("Access control" section) become real. This is the backend half of the Stage 5 done-when bar ("file
exchange"); the widget/console UI that calls these endpoints is `5-08`/`5-10`.

## Context to read first

`file-storage.md` in full, especially "Upload flow" steps 1-5 and "Access control" - re-read after
`5-02` in case that item's own work changed the port's exact shape. `adr/0008`. `data-model.md`'s
existing schema conventions (`id` uuid v7, `site_id` on every table, `timestamptz`) - the `attachments`
table this item adds must follow them, not invent new ones. `api-design.md`'s HTTP conventions
(resource-shaped, `201`+`Location`, RFC 7807 errors, idempotency key on create) and rate-limiting
precedent (`3-05`'s `MessageSendRateLimitOptions` shape - this item's own attachment-upload limit
should look the same, a new options class beside it, not inside it). `caching.md` if the per-viewer
presigned-GET cache (below) needs it.

## Scope

- `attachments` table + migration: `id`, `site_id`, `conversation_id`, `message_id?`, `object_key`,
  `content_type`, `size_bytes`, `state` (`pending|ready|deleted`), `created_at`, `thumbnail_key?` -
  exactly `file-storage.md`'s "Data model addition". The message references the attachment, not the
  reverse, so an attachment can exist briefly before its message does.
- `POST /api/v1/attachments` (or nested under conversations - decide and state which, consistent with
  `api-design.md`'s "actions become sub-resources" rule): validates per-site quota, per-visitor/
  per-operator rate limit (new options class, same shape as `3-05`), size ceiling, extension/content-
  type allowlist; creates the `pending` row; returns a presigned PUT scoped to one key/method/content-
  type, short-lived.
- `POST /api/v1/attachments/{id}/confirm`: HEAD-verifies against storage (`IFileStorage.
  GetMetadataAsync`) before flipping `pending` -> `ready` - a client's "uploaded" claim is never
  trusted, restated from `file-storage.md` because it is the step most tempting to skip.
- Object key structure: `site/{site_id}/conv/{conversation_id}/{uuid7}{ext}` - never the access-control
  boundary itself, only organisation.
- The message-send path (`SendVisitorMessage`/`SendOperatorMessage`, `Ago.Chat.Application`) gains an
  optional attachment reference - state explicitly how this interacts with `4-05`'s pipeline (the
  attachment id is part of `PendingMessage`, validated - does the referenced attachment exist, belong
  to this conversation, and sit in `ready` state - inside `MessageBatchWriter`'s own transaction, the
  same place every other write-time invariant already lives, not as a separate pre-check).
- Download: `GET /api/v1/attachments/{id}` (or similar) returns a presigned GET after an authorization
  check (caller is a participant of the attachment's conversation - the same check
  `GetConversationHistoryHandler` already makes for messages). Presigned URLs cached per
  `(attachment, viewer)` for slightly less than their lifetime (`file-storage.md`), so rendering a
  history page of N images is one signing round trip, not N.
- Downloads served with `Content-Disposition: attachment` and a restrictive CSP - `file-storage.md`'s
  own reasoning (a stored HTML file must never execute in the site's origin).

## Out of scope

- Thumbnail generation, the orphan sweeper - `5-04`.
- Any widget/console UI - `5-08`/`5-10`.
- `attachment:delete` as a moderation permission - `5-08`, alongside the admin role it is meant for.
- Malware scanning - project-wide out of scope (`vision.md`).

## Done when

- [x] `Ago.Chat.Integration.Tests`: the full upload flow against real Postgres + real MinIO - presign,
      PUT directly to the returned URL, confirm, verify the row is `ready` and its metadata matches
      what storage actually holds (not what the client claimed). `AttachmentFixture` +
      `AttachmentUploadFlowTests` (`FullFlow_PresignPutConfirm_EndsReadyWithMatchingMetadata`), same
      "one fixture per genuinely-needed resource combination" shape as `SiteCachingFixture`.
- [x] Confirming an attachment whose bytes were never actually uploaded (or whose real
      size/content-type mismatches the declared one) fails, and the row stays `pending` - proves the
      HEAD-verify step is load-bearing, not decorative.
      `AttachmentUploadFlowTests.Confirm_WithoutEverPuttingTheObject_FailsAndStaysPending` and
      `Confirm_WhenTheUploadedBytesDontMatchTheDeclaredSize_FailsAndStaysPending`, plus
      `ConfirmAttachmentHandlerTests`' fake-storage equivalents for the content-type mismatch case.
- [x] Sending a message that references a `ready` attachment succeeds; referencing a `pending` one, a
      `deleted` one, or one belonging to a different conversation fails with a clear error - proven at
      `MessageBatchWriter`'s level (a concurrency/integration test, matching `4-05`'s own test style),
      not just at the HTTP layer. Five new cases in `MessageBatchWriterTests` (real Postgres):
      ready/pending/deleted/wrong-conversation/unknown-attachment. `Attachment.MarkDeleted()` was
      added specifically so the `deleted` case is reachable at all - nothing in `5-03` itself calls it
      outside tests (`5-04`'s orphan sweep is the intended real caller), same "the state exists before
      its writer does" shape as `thumbnail_key` below.
- [x] A visitor/operator who is not a participant of the attachment's conversation cannot obtain a
      download URL for it. `GetAttachmentDownloadUrlHandlerTests` (both entry points) plus the
      participant check itself mirrors `GetConversationHistoryHandler`'s exact shape.
- [x] Per-site/per-visitor upload rate limits are enforced and tested, matching `3-05`'s own test
      shape - widened to three buckets (`AttachmentRateLimitOptions`: per-visitor, per-operator,
      per-site), since unlike sending a message, creating an attachment is something both sides do.
      `CreateAttachmentHandlerTests` covers all three, including a `SelectiveFakeRateLimiter` proving
      the per-site bucket specifically is consulted, not just that some bucket exists.
- [x] `data-model.md` gets the `attachments` table documented; `api-design.md` or `file-storage.md`
      gets a "Shipped in `5-03`" note with the actual endpoint shapes chosen.

## Open questions - resolved

Endpoint shape went with the recommendation below exactly: `POST
/api/v1/conversations/{conversationId}/attachments` (create), `POST /api/v1/attachments/{id}/confirm`,
`GET /api/v1/attachments/{id}` (download). All three accept either a visitor or an operator token on
one route (`AttachmentEndpoints`'s own remarks) - the first endpoints in this codebase to do that,
disambiguated by a new `kind` JWT claim (`api-design.md`'s `5-03` note has the detail).

**New gap surfaced, not closed here**: `GetAttachmentDownloadUrl` cannot set `Content-Disposition` or
a CSP override on the presigned GET - `IFileStorage.CreateDownloadUrlAsync` has no override parameter,
and adding one is a platform-repo change this branch cannot make alone. Left for a follow-up slice
that touches `ago-platform`; `file-storage.md` carries the same note so it is not silently dropped.

**New gap surfaced, not closed here**: nothing creates the real MinIO bucket in `ago-deploy` -
`5-02`'s own gap, still open after `5-03`. See `file-storage.md`'s "The port" section for the
recommended shape (an explicit tooling step, matching the migrations precedent) and why no session has
written it yet.
