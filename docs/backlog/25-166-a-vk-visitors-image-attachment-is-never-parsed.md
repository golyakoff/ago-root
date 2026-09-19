# 25-166 · A VK visitor's image attachment is never parsed

- **Stage**: 25
- **Status**: ready — found 2026-09-19, scope pre-cut by mirroring `25-161`'s own confirmed pattern
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

- [ ] A VK visitor's photo is confirmed to arrive as a real attachment on the operator's side when the
      conversation has an upload grant, proven by a test
- [ ] A VK visitor with no grant is refused with the same clear, visitor-facing message `25-161` already
      writes for MAX, proven by a test
- [ ] Every existing VK inbound-message test still passes unchanged
- [ ] The real repro (a VK visitor sending a photo, granted and ungranted) is confirmed live, not only
      by tests
