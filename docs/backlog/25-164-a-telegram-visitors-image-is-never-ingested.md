# 25-164 · A Telegram visitor's image is never ingested

- **Stage**: 25
- **Status**: done — `ago-chat#338` (commit `03dd234`), confirmed genuinely deployed to the demo stand.
  The real-live-Telegram box is settled `[~]`, not ticked - this session has no Telegram account to send
  a real photo from.
- **Found**: 2026-09-19, answering the author's own question after `25-161` (MAX) landed: does that fix
  cover any other bot channel? Checked directly - `Ago.Chat.Infrastructure.Telegram\TelegramInboundMessageParser.cs`
  has **zero** occurrences of `attachment`/`image`/`photo` (grepped, case-insensitive, whole file) - the
  identical gap `25-161` found and fixed for MAX, unconfirmed until now for Telegram specifically.
- **Depends on**: `25-161` (merged, `ago-chat#337`) - this item reuses its new, channel-agnostic
  `Ago.Chat.Application.UseCases.ReceiveChannelAttachment.ReceiveChannelAttachmentHandler` rather than
  building a second grant-check/upload pipeline. Only the Telegram-specific wire-parsing and download
  glue is new work here.

## What is actually true today

A Telegram visitor's sent photo is either silently dropped in full (no caption) or reduced to its
caption alone (with one) - the same shape `25-161`'s own report described for MAX, not yet confirmed by
a live repro for Telegram specifically, but the code-level evidence is identical: nothing in
`TelegramInboundMessageParser.cs` reads a photo/document field off Telegram's own webhook payload, so
nothing downstream ever creates an `Attachment`, so the `23-78` upload grant is never checked either.

## Scope

Mirror `25-161`'s own shape exactly, substituting Telegram's own wire format and API:

- `TelegramDtos.cs`/`TelegramInboundMessageParser.cs`: extract an inbound photo. Telegram's own Bot API
  sends a `photo` array of `PhotoSize` objects (varying resolutions of the same image) on an inbound
  message update, each carrying a `file_id` - not a directly fetchable URL the way MAX's own payload
  is. Confirm this against Telegram's own published Bot API documentation before assuming the exact
  field names/shape.
- `TelegramApiClient.cs`: a `file_id` needs a `getFile` call first (resolves it to a `file_path`), then
  a second request against `https://api.telegram.org/file/bot<token>/<file_path>` to fetch the actual
  bytes - a two-step download, unlike MAX's single direct URL. Add whatever `DownloadImageAsync`-shaped
  method this requires, following `MaxApiClient.DownloadImageAsync`'s own precedent for shape and
  error handling (terminal vs. transient failure split).
- A new `TelegramInboundAttachmentDispatch` (or an equivalently named type), mirroring
  `MaxInboundAttachmentDispatch` exactly: downloads the image, calls
  `ReceiveChannelAttachmentHandler.PrepareAsync`, does the one presigned-URL PUT
  (`IFileStorage` is presign-only, `adr/0008`; Application may not hold an `HttpClient`, CLAUDE.md rule
  2), then `CompleteAsync`.
- Wire it into whichever of `TelegramLongPollingService`/Telegram's webhook path actually receives
  inbound updates - check both, since `25-161`'s own MAX fix had to touch both its webhook and
  long-polling entry points for the identical reason (one parser, two delivery mechanisms).

## Out of scope

- WhatsApp and VK - each is its own item (`25-165`, `25-166`), since each has its own wire format and
  its own reason the fix cannot be copy-pasted.
- Anything about the `23-78` grant mechanism itself, or `ReceiveChannelAttachmentHandler`'s own logic -
  both are already correct and unchanged; this item only adds a new caller.

## Done when

- [x] A Telegram visitor's photo is confirmed to arrive as a real attachment on the operator's side
      when the conversation has an upload grant, proven by a test - grant/refusal itself is proven
      generically and channel-agnostically by the existing `ReceiveChannelAttachmentHandlerTests`
      (`25-161`'s own fixture, unchanged); this item's own new `TelegramInboundMessageParserTests`
      (caption-less photo, captioned photo, out-of-order sizes, empty photo array) and
      `TelegramApiClientTests` (getFile success/no-file_path/400/500, download success/404/500) prove
      Telegram's own wire parsing and two-step download feed that generic path correctly
- [x] A Telegram visitor with no grant is refused with the same clear, visitor-facing message `25-161`
      already writes for MAX, proven by a test - the same generic `ReceiveChannelAttachmentHandlerTests`
      path this fix now feeds
- [x] Every existing Telegram inbound-message test still passes unchanged
- [~] The real repro (a Telegram visitor sending a photo, granted and ungranted) is confirmed live, not
      only by tests. This session has no Telegram account to send a real photo from - needs the author.

## Outcome

Fixed and merged 2026-09-19 (`ago-chat#338`, commit `03dd234`): `TelegramInboundMessageParser` had zero
attachment handling - a caption-less photo failed its own blank-body bail-out and vanished entirely, a
captioned one kept only its caption, mirroring `25-161`'s own MAX finding exactly. `TelegramDtos.cs`
grows `photo`/`caption` (`TelegramMessage`) plus new `TelegramPhotoSize`/`TelegramFile`; the parser
extracts the highest-resolution photo explicitly by width (Telegram's own size ordering is documented
prose, not an enforced schema guarantee) and folds `caption` into `Text` so a captioned photo still
produces its own plain-text message independently. `TelegramApiClient.DownloadImageAsync` does
Telegram's two-step download (`getFile` resolves a `file_id` to a `file_path`, a second request against
a distinct URL shape fetches the bytes) - unlike MAX's single direct URL. New
`TelegramInboundAttachmentDispatch` mirrors `MaxInboundAttachmentDispatch`'s download-prepare-upload-
complete protocol exactly, wired into `TelegramLongPollingService` - Telegram's own one and only inbound
mechanism (no webhook receiver exists for this channel). New coverage:
`TelegramInboundMessageParserTests`, `TelegramApiClientTests`, and one
`TelegramTokenRedactingLoggingHandlerTests` case proving the new `file/bot<token>/...` URL's token
segment is redacted too. Confirmed by the managing session as genuinely present in the demo stand's
currently deployed `ago-chat-api`/`worker`/`webhooks` image before this file was closed.

This item's own `Status: ready` and unticked boxes had outlived the real merge by a day - a
documentation gap, not a false closure: the GitHub issue was already correctly closed as completed the
same day the PR merged, and this file is the only piece that had not caught up.
