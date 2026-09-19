# 25-165 · A WhatsApp visitor's image is explicitly skipped, not just unhandled

- **Stage**: 25
- **Status**: ready — found 2026-09-19, scope pre-cut by mirroring `25-161`'s own confirmed pattern
- **Found**: 2026-09-19, answering the author's own question after `25-161` (MAX) landed. Checked
  directly - `WhatsAppInboundMessageParser.cs`'s own doc comment states plainly: "Only
  `WhatsAppMessage.Type` `\"text\"` is recognised... every other type (image, audio, location, an
  interactive reply) is skipped rather than coerced into a text-shaped stand-in." Unlike `25-161`
  (MAX) and `25-164` (Telegram), where the gap was an omission, this one is a **documented, deliberate**
  scope cut from whatever item first shipped this parser - worth reading that item's own reasoning
  before assuming it is safe to widen.
- **Depends on**: `25-161` (merged, `ago-chat#337`) - reuses
  `Ago.Chat.Application.UseCases.ReceiveChannelAttachment.ReceiveChannelAttachmentHandler` the same way.

## What is actually true today

A WhatsApp visitor's sent photo is dropped in full - not degraded, not partially handled, deliberately
ignored by a parser that only recognises `"text"`. Read the original scope-cut's own reasoning (find it
via `git log`/`git blame` on `WhatsAppInboundMessageParser.cs` before writing any code) - if it named a
real constraint (e.g. WhatsApp Business API's media-fetch mechanics being harder than a bot API's) that
constraint still needs answering, not just overriding a comment.

## Scope

Mirror `25-161`'s own shape, substituting WhatsApp's own wire format and API:

- `WhatsAppDtos.cs`/`WhatsAppInboundMessageParser.cs`: recognise `WhatsAppMessage.Type == "image"`
  alongside `"text"`. The WhatsApp Business (Cloud) API sends an inbound image as a `media_id` (an
  opaque reference), never a fetchable URL - confirm the exact field names against WhatsApp's own
  published Cloud API documentation before assuming MAX's or Telegram's shape carries over.
- `WhatsAppApiClient.cs`: a `media_id` needs a `GET /<media_id>` call first (resolves to a short-lived
  signed URL), then a second authenticated request to actually fetch the bytes - a two-step download
  with its own token requirements, distinct from both MAX's and Telegram's. Add whatever
  `DownloadImageAsync`-shaped method this requires, following `MaxApiClient.DownloadImageAsync`'s own
  precedent for shape and error handling.
- A new `WhatsAppInboundAttachmentDispatch` (or equivalently named type), mirroring
  `MaxInboundAttachmentDispatch`: downloads the image, calls
  `ReceiveChannelAttachmentHandler.PrepareAsync`, does the one presigned-URL PUT, then `CompleteAsync`.
- Wire it into WhatsApp's own inbound entry point (`WhatsAppChannelAdapter` or wherever inbound webhooks
  land - confirm there is only one delivery mechanism here, unlike MAX/Telegram's webhook-plus-polling
  pair, before assuming a single wiring point is enough).

## Out of scope

- Telegram and VK - each is its own item (`25-164`, `25-166`).
- Any other WhatsApp message type this parser also skips (audio, location, an interactive reply) -
  images only, per this item's own name; each of those is a separate future item if wanted.

## Done when

- [ ] A WhatsApp visitor's image is confirmed to arrive as a real attachment on the operator's side
      when the conversation has an upload grant, proven by a test
- [ ] A WhatsApp visitor with no grant is refused with the same clear, visitor-facing message `25-161`
      already writes for MAX, proven by a test
- [ ] Every existing WhatsApp inbound-message test still passes unchanged
- [ ] The original scope-cut's own reasoning (whatever item first wrote "skipped rather than coerced")
      is read and either confirmed obsolete or explicitly addressed - not silently overridden
- [ ] The real repro (a WhatsApp visitor sending a photo, granted and ungranted) is confirmed live, not
      only by tests
