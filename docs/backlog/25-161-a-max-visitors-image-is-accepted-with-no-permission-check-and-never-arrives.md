# 25-161 · A MAX visitor's image is accepted with no permission check, and never arrives either way

- **Stage**: 25
- **Status**: ready — reported live 2026-09-19, root cause **not yet diagnosed by this session**,
  deliberately - see "How this item is meant to be worked" below.
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

- [ ] The real root cause of both symptoms is written down in this file, with the actual code path
      named - not a guess
- [ ] A MAX visitor with no attachment-upload grant is refused with a clear, visitor-facing message
      when they try to send a file, proven by a test
- [ ] A MAX visitor's image, sent after a grant, is confirmed to arrive as a real attachment on the
      operator's side, proven by a test - and, if reachable, by a real send through the live MAX bot
- [ ] Every existing widget-channel attachment/grant test still passes unchanged
