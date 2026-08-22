# Widget: attachment upload and view

- **Stage**: 5
- **Status**: ready
- **Depends on**: `5-03-attachments-upload-and-download.md`, `5-04-attachment-thumbnails-and-orphan-
  sweep.md`, `5-09-widget-bootstrap-and-messaging.md`

## Goal

The last piece of Stage 5's own done-when bar: "a plain HTML page with one script tag holds a real
conversation **with file exchange**." A visitor can attach a file to a message and see attachments the
operator sends back.

## Context to read first

`.claude/skills/embeddable-widget/SKILL.md`'s "Uploads" section - "presigned direct upload only, ask
the API for a slot, PUT to storage, confirm. Show progress from the PUT, enforce the size ceiling
client-side as a courtesy while assuming the server enforces it for real." `5-03`'s exact
presign/confirm/download endpoint shapes. `file-storage.md`'s CSP/`Content-Disposition` note - the
widget must not render a downloaded attachment in a way that could execute it in the host page's
origin, same constraint `5-08`'s console view is under, independently enforced here since neither
runtime shares code with the other.

## Scope

- Attach button in the send box: file picker, client-side size-ceiling check (courtesy only), calls
  `5-03`'s presign endpoint, PUTs directly to the returned URL with real upload progress, confirms, then
  sends the message referencing the now-`ready` attachment.
- Inline preview using `5-04`'s thumbnail for images; a plain download link (opening `5-03`'s presigned
  GET, never proxied through the widget's own code) for anything else.
- Failure paths surfaced without breaking the rest of the widget - an upload that fails presign,
  confirm, or the PUT itself degrades to a visible error in the send box, never a thrown exception
  escaping to the host page (the skill's "never break the host page" rule, applied to this feature
  specifically).

## Out of scope

- `attachment:delete` from the widget - that is an admin/operator moderation action (`5-08`), a visitor
  has no reason to need it.
- Any change to `5-09`'s connection/reconnect/messaging protocol layer - this item only adds a second
  kind of thing a message can carry.

## Done when

- [ ] Manually verified against the local cluster, same hostile demo host page as `5-09`: a visitor
      attaches an image, sees real upload progress, the message sends with the attachment referenced,
      and the operator side (console, `5-08`) receives and can view it - and the reverse direction,
      an operator-sent attachment appears correctly in the widget.
- [ ] A forced upload failure (storage unreachable, or a deliberately oversized file) surfaces a visible
      error and never an unhandled exception on the host page.
- [ ] Bundle-size budget (`5-09`) is re-measured with this feature included and still enforced in CI -
      confirm the addition did not silently blow past it.

## Open questions

None - scope follows directly from the skill's own already-written "Uploads" section.
