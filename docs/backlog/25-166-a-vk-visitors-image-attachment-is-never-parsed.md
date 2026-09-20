# 25-166 · A VK visitor's image attachment is never parsed

- **Stage**: 25
- **Status**: done — `ago-chat#340` (commit `40bd114`), confirmed genuinely deployed to the demo stand
  (this commit is a real ancestor of the deployed `177be3f7...`). The real-live-VK box is settled `[~]`,
  not ticked - this session has no VK account to send a real photo from.
- **Found**: 2026-09-19, answering the author's own question after `25-161` (MAX) landed. Checked
  directly - `VkInboundMessageParser.cs` recognises only `VkCallbackEventTypes.MessageNew`'s own text
  content; nothing in it reads an `attachments` array off the event payload. VK's Callback API attaches
  photos (and other media) to a `message_new` event as a structured `attachments` list alongside the
  message body - this parser's own doc comment describes deliberately ignoring *other event kinds*
  (a wall post, a community join), which is a different and correct cut from ignoring a real
  attachment *within* the one event kind it does handle.
- **Depends on**: `25-161` (merged, `ago-chat#337`) - reuses
  `Ago.Chat.Application.UseCases.ReceiveChannelAttachment.ReceiveChannelAttachmentHandler` the same way.

## What is actually true today

A VK visitor's sent photo is silently dropped - the parser reads `MessageNew`'s own text body and
nothing else, so a message that is only a photo (no caption) likely fails the same blank-body bail-out
`25-161` found in MAX's parser, and a captioned one keeps only its caption.

## Scope

Mirror `25-161`'s own shape, substituting VK's own wire format and API:

- `VkDtos.cs`/`VkInboundMessageParser.cs`: extract a `photo`-kind entry from `message_new`'s own
  `attachments` array. VK's Callback API already includes several resolution variants
  (`photo_130`/`photo_604`/... or a `sizes` array, depending on API version) with **directly fetchable
  URLs** - no separate resolve-then-download step the way Telegram/WhatsApp need, closer to MAX's own
  single-URL shape. Confirm the exact field names and API-version shape against VK's own published
  Callback API documentation before assuming this.
- `VkApiClient.cs`: if the URL is directly fetchable (per the above), this may need only a
  `DownloadImageAsync`-shaped method with no separate resolve call, following
  `MaxApiClient.DownloadImageAsync`'s own precedent for shape and error handling - simpler than
  Telegram/WhatsApp if VK's own wire shape confirms this.
- A new `VkInboundAttachmentDispatch` (or equivalently named type), mirroring
  `MaxInboundAttachmentDispatch`: downloads the image, calls
  `ReceiveChannelAttachmentHandler.PrepareAsync`, does the one presigned-URL PUT, then `CompleteAsync`.
- Wire it into VK's own inbound webhook entry point.

## Out of scope

- Telegram and WhatsApp - each is its own item (`25-164`, `25-165`).
- Any VK attachment kind other than a photo (a sticker, a document, a shared post) - images only, per
  this item's own name.

## Done when

- [x] A VK visitor's photo is confirmed to arrive as a real attachment on the operator's side when the
      conversation has an upload grant, proven by a test - grant/refusal is proven generically by the
      existing `ReceiveChannelAttachmentHandlerTests` (`25-161`'s own fixture, unchanged); new
      `VkInboundMessageParserTests` (caption-less/captioned photo, out-of-order sizes, a non-photo
      attachment ignored) prove VK's own wire parsing feeds that generic path correctly
- [x] A VK visitor with no grant is refused with the same clear, visitor-facing message `25-161` already
      writes for MAX, proven by a test
- [x] Every existing VK inbound-message test still passes unchanged
- [~] The real repro (a VK visitor sending a photo, granted and ungranted) is confirmed live, not only
      by tests. This session has no VK account to send a real photo from - needs the author.

## Outcome

Fixed and merged 2026-09-19 (`ago-chat#340`, commit `40bd114`): `VkInboundMessageParser` recognised only
`message_new`'s own `text` field - nothing read the event's `attachments` array, so a caption-less photo
failed the blank-body bail-out and vanished, a captioned one kept only its caption, mirroring `25-161`'s
own MAX finding. `VkDtos.cs` grows `attachments` (`VkMessage`) plus new
`VkAttachment`/`VkPhoto`/`VkPhotoSize`, confirmed against VK's own current post-5.77 `sizes` array shape
rather than the older deprecated fixed-name fields. The parser extracts a `photo`-kind attachment,
picking the highest resolution explicitly by `width` rather than trusting array order or the size-letter
code. VK's own photo URL is directly fetchable with no auth and no separate resolve step - simpler than
Telegram's/WhatsApp's two-step downloads, the same single-URL shape MAX's own attachment already has, so
`VkApiClient.DownloadImageAsync` shares `MaxApiClient.DownloadImageAsync`'s shape wholesale. New
`VkInboundAttachmentDispatch` mirrors `MaxInboundAttachmentDispatch`, wired into `VkWebhookEndpoints` -
needing no per-request credential at all, unlike every other channel. `VkWebhookEndpointsTests`' own
hand-rolled DI host needed the identical dependency-chain fix `25-165` needed for the same reason. New
coverage: `VkInboundMessageParserTests`, and `VkApiClientTests`' own https-only defensive floor on the
one value read straight off an inbound payload. Confirmed by the managing session as a real ancestor of
the demo stand's currently deployed `ago-chat-api`/`worker`/`webhooks` commit (`177be3f7...`) before this
file was closed.

This item's own `Status: ready` and unticked boxes had outlived the real merge by a day - a
documentation gap, not a false closure: the GitHub issue was already correctly closed as completed the
same day the PR merged, and this file is the only piece that had not caught up.
