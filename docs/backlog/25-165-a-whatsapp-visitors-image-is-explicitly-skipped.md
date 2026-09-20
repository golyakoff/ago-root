# 25-165 · A WhatsApp visitor's image is explicitly skipped, not just unhandled

- **Stage**: 25
- **Status**: done — `ago-chat#339` (commit `23a2dde`), confirmed genuinely deployed to the demo stand
  (this commit is a real ancestor of the deployed `177be3f7...`). The real-live-WhatsApp box is settled
  `[~]`, not ticked - this session has no WhatsApp account to send a real photo from.
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

- [x] A WhatsApp visitor's image is confirmed to arrive as a real attachment on the operator's side
      when the conversation has an upload grant, proven by a test - grant/refusal is proven generically
      by the existing `ReceiveChannelAttachmentHandlerTests` (`25-161`'s own fixture, unchanged); new
      `WhatsAppInboundMessageParserTests` (caption-less/captioned image, no `media_id`) and
      `WhatsAppApiClientTests` (media-lookup success/terminal-error/throughput-limit, download
      success/404/500, the Bearer token carried on both requests) prove WhatsApp's own wire parsing and
      two-step, doubly-authenticated download feed that generic path correctly
- [x] A WhatsApp visitor with no grant is refused with the same clear, visitor-facing message `25-161`
      already writes for MAX, proven by a test
- [x] Every existing WhatsApp inbound-message test still passes unchanged - including the pre-existing
      "image is skipped" case, updated in place to reflect the new behaviour rather than deleted
- [x] The original scope-cut's own reasoning (whatever item first wrote "skipped rather than coerced")
      is read and either confirmed obsolete or explicitly addressed - not silently overridden.
      `14-10`'s own doc comment named the reason plainly: nothing existed yet to give a non-text message
      anywhere real to go. `25-161` built exactly that destination
      (`ReceiveChannelAttachmentHandler`), so the fix's own commit message states directly that the
      stated reason no longer holds for images specifically - audio/location/an interactive reply stay
      out of scope, unchanged, for the same original reason.
- [~] The real repro (a WhatsApp visitor sending a photo, granted and ungranted) is confirmed live, not
      only by tests. This session has no WhatsApp account to send a real photo from - needs the author.

## Outcome

Fixed and merged 2026-09-19 (`ago-chat#339`, commit `23a2dde`): `WhatsAppInboundMessageParser` recognised
only `type == "text"` by deliberate `14-10` design, whose own doc comment named the reason plainly -
nothing existed yet to give a non-text message anywhere real to go. `25-161` built exactly that
destination, so the stated reason no longer holds for images specifically. `WhatsAppDtos.cs` grows
`image` (`WhatsAppMessage`) plus new `WhatsAppMediaObject`/`WhatsAppMediaInfo`; the parser recognises
`type == "image"` alongside `"text"` and folds the image's own `caption` into `Text` (WhatsApp never
populates `text` on an image message). `WhatsAppApiClient.DownloadImageAsync` does WhatsApp's own
two-step, doubly-authenticated download (`GET /{media_id}` resolves a short-lived signed URL; fetching
that URL still needs the identical Bearer token, confirmed against Meta's own documentation - the one
genuine divergence from MAX's and Telegram's anonymous download step). New
`WhatsAppInboundAttachmentDispatch` mirrors `MaxInboundAttachmentDispatch`, wired into
`WhatsAppWebhookEndpoints` - this channel's one and only inbound mechanism. `WhatsAppWebhookEndpointsTests`'
own hand-rolled DI host needed `ReceiveChannelAttachmentHandler`'s full dependency chain registered
purely so the route's endpoint metadata still resolves. New coverage: `WhatsAppInboundMessageParserTests`,
`WhatsAppApiClientTests`. Confirmed by the managing session as a real ancestor of the demo stand's
currently deployed `ago-chat-api`/`worker`/`webhooks` commit (`177be3f7...`) before this file was closed.

This item's own `Status: ready` and unticked boxes had outlived the real merge by a day - a
documentation gap, not a false closure: the GitHub issue was already correctly closed as completed the
same day the PR merged, and this file is the only piece that had not caught up.
