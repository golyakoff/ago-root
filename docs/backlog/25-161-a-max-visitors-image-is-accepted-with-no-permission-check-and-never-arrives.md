# 25-161 · A MAX visitor's image is accepted with no permission check, and never arrives either way

- **Stage**: 25
- **Status**: done — `ago-chat#337` (commit `ee85027`), confirmed genuinely deployed to the demo stand.
  The live-MAX-bot box is settled `[~]`, not ticked - it needs a real MAX account, which this session
  does not have. Root cause below, confirmed by the worker this item's own "analyze first" instruction
  asked for.
- **Found**: 2026-09-19, live-testing the MAX channel. Two distinct symptoms, both real:
  1. A MAX visitor can attach and send an image with **no prompt or gate at all** - the product already
     has an operator-facing "allow this visitor to send files" control (`23-78`,
     `GrantAttachmentUploadHandler`/`RevokeAttachmentUploadHandler`,
     `IConversationAttachmentUploadGrantRepository`, the console's own
     `AttachmentUploadGrantToggle`), and the expectation is that a visitor without a grant is told they
     need one before a file is accepted - not silently allowed through.
  2. **Separately, and worse**: even after the operator turns the grant on, the image still never
     arrives on the operator's side.
  - Live repro: dialogue with visitor 🦉🍌 (`01a0add1`) - two images sent from the MAX side, the first
    while ungranted, the second after the operator enabled the grant. Neither reached the operator.

## What this session already found, so the worker does not have to re-find it

Not a diagnosis - a lead, checked directly rather than assumed, to save the worker's own first steps:

- `Ago.Chat.Infrastructure.MaxBot\MaxInboundMessageParser.cs` has **zero occurrences** of
  `attachment`/`image`/`photo` (grepped directly, case-insensitive, whole file) - inbound MAX parsing
  may only ever read a text body today, never anything MAX's own webhook payload carries for a sent
  photo. Worth confirming against `MaxDtos.cs`/MAX's own API docs for what an inbound photo attachment
  actually looks like on the wire, and against `MaxApiClient.cs` for whether anything downloads one.
- The `23-78` grant mechanism (`GrantAttachmentUploadHandler` et al.) exists and is real, but whether
  anything on the **inbound** path for a non-widget channel (MAX, and possibly Telegram/WhatsApp/VK
  too) actually **checks** it before accepting a file is unconfirmed - the widget's own enforcement is
  presumably client-side (hide/disable the attach button), which has no equivalent for a channel where
  the visitor is using that platform's own native UI, not ours. If nothing server-side enforces the
  grant for bot channels, that is symptom 1's real cause.
- These may be one root cause or two unrelated ones (e.g. "no inbound MAX attachment ingestion at all"
  would independently explain symptom 2 regardless of symptom 1's own fix) - not assumed either way.

## How this item is meant to be worked

Decided by the author, 2026-09-19: **the worker analyzes first, then implements** - not this session.
Investigate both symptoms down to a real, confirmed root cause (reading the actual MAX webhook payload
shape, the actual inbound parsing/attachment-creation path, and how/whether the `23-78` grant is
consulted anywhere on it) before writing a fix. If the two symptoms turn out to have different causes,
say so plainly and fix both - do not force them into one narrative. If mid-investigation the item
turns out to be two genuinely separate promises (rule 15), stop and report that split back rather than
picking one arbitrarily.

## Scope

Not pre-cut, deliberately - the worker's own analysis decides the real shape of the fix. At minimum,
by the time this item closes:
- A MAX visitor attempting to send a file with no grant gets a clear response explaining that the
  operator must first allow file uploads - never silent acceptance, never silent loss.
- A MAX visitor's image, sent after a grant, actually reaches the operator's side as a real attachment
  - visible, downloadable, the same as a widget-sent attachment.

## Out of scope

- Any channel other than MAX, unless the worker's own investigation finds the identical gap already
  proven to affect one (in which case: report it, do not silently expand scope to fix it here too -
  that is a new item, per rule 15).

## Done when

- [x] The real root cause of both symptoms is written down in this file, with the actual code path
      named - see Root cause, confirmed below
- [x] A MAX visitor with no attachment-upload grant is refused with a clear, visitor-facing message
      when they try to send a file, proven by a test
- [x] A MAX visitor's image, sent after a grant, is confirmed to arrive as a real attachment on the
      operator's side, proven by a test. Not yet proven by a real send through the live MAX bot (see
      the open box below)
- [x] Every existing widget-channel attachment/grant test still passes unchanged
- [~] The exact repro from this item - two images through a real MAX conversation, one refused, one
      delivered - confirmed live, not only by tests. **Checked and left open, not merely unchecked**:
      this fix's own commit (`ee85027`) is confirmed present in the demo stand's deployed
      `ago-chat-api`/`worker`/`webhooks` image (`git ls-tree`/`git show` against `MaxInboundAttachmentDispatch.cs`/
      `ReceiveChannelAttachmentHandler.cs`). Unlike `25-158`/`25-159`, this box has no console-access
      workaround even once `25-189` is fixed: it needs a real MAX bot conversation, and this session has
      no MAX account to send from. Left open rather than ticked or split off - the same live check this
      item asked for from the start, still genuinely owed, but only performable by the author.

## Root cause, confirmed

One cause for both symptoms: `MaxInboundMessageParser` had **no attachment handling at all**, only a
text path. A caption-less MAX photo failed the parser's own blank-body bail-out and vanished entirely;
a captioned one kept its caption but silently dropped the image. Because nothing on that path ever
created an `Attachment` domain object, nothing ever reached `CreateAttachmentHandler.HandleAsVisitorAsync`
- the one place the `23-78` grant (`Conversation.HasAttachmentUploadGrant`) is actually checked - so
symptom 1 ("no permission check") was a consequence of the missing ingestion path, not a second,
independent bug. Confirmed against MAX's own published Go client schema for the wire shape of an
inbound image attachment, not assumed from local code alone.

## Outcome

Fixed and merged 2026-09-19 (`ago-chat#337`, commit `ee85027`): `MaxInboundMessageParser`/`MaxDtos` now
extract an image attachment's `url`; `MaxApiClient.DownloadImageAsync` fetches the bytes; a new
`ReceiveChannelAttachmentHandler` composes the widget's own `CreateAttachmentHandler`/
`ConfirmAttachmentHandler`/`SendVisitorMessageHandler` path so the `23-78` grant, rate limits and
storage budgets apply to a MAX-sourced image for free, with a real visitor-facing refusal message when
ungranted; `MaxInboundAttachmentDispatch` (`Infrastructure.MaxBot`) does the one presigned-URL PUT
Application isn't allowed to do itself (`IFileStorage` is presign-only, `adr/0008`), mirroring
`AttachmentThumbnailGenerator`'s own precedent. 10 new tests, each fails-before/passes-after proven;
independently re-verified twice (once pre-rebase, once after rebasing onto a `main` that had moved -
`25-156` merged in between). The one remaining Done-when box (a real send through the live MAX bot)
needs the live channel this session did not use for verification - left open rather than ticked or
split into a new number, since it is the same live check this item asked for from the start.
