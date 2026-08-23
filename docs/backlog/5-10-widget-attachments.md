# Widget: attachment upload and view

- **Stage**: 5
- **Status**: done
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

- [x] Manually verified against the local cluster, same hostile demo host page as `5-09`: a visitor
      attaches an image, sees real upload progress, the message sends with the attachment referenced,
      and the operator side (console, `5-08`) receives and can view it - and the reverse direction,
      an operator-sent attachment appears correctly in the widget.

      Verified with a real caveat, not silently glossed over: `5-08`'s console does not exist yet, so
      the operator side was exercised through `dev-harness.html` plus direct REST calls with a real
      Keycloak-issued operator token - the same substitution `5-05`'s own verification used before a
      console existed. The visitor -> operator direction (an image, sent by the widget) was proven
      fully live: real presigned upload against real MinIO, real progress, correct inline `<img>`
      render, correct dedup of the sender's own echo. The operator -> visitor direction (a PDF, sent
      via REST + the harness's operator connection) surfaced a **real, separate bug** in the
      real-time push path - not this item's own code - documented in `messaging.md` and tracked as
      `5-11`; ten operator-sent messages were sent, zero arrived as a live push. Rather than stop
      there, the same messages were proven to arrive **correctly** - correct body, correct
      `contentType`-based rendering (a plain "📎 Download attachment" link for the non-image PDFs,
      matching the spec), correct presigned URLs - via the resume-by-sequence path (`5-09`) that
      `5-11`'s bug does not touch, once the widget reconnected. This proves the widget's own
      attachment-rendering code is correct for an operator-authored message; it does not (yet) prove
      the live-push hop, which is `5-11`'s job to fix and re-verify.
- [x] A forced upload failure (storage unreachable, or a deliberately oversized file) surfaces a visible
      error and never an unhandled exception on the host page. Proven live, twice: a courtesy-rejected
      file type (`window.onerror`/`unhandledrejection` listeners installed first, zero uncaught, a
      visible system note shown) and a forced PUT failure (the presigned-URL step redirected to an
      unreachable host mid-upload - same zero-uncaught result, bubble marked "Couldn't send the
      attachment.").
- [x] Bundle-size budget (`5-09`) is re-measured with this feature included and still enforced in CI -
      confirm the addition did not silently blow past it. **19.9 KB gzipped** (73.7 KB raw), up from
      `5-09`'s 18.4 KB - still well under the 45 KB budget. `ago-widget/README.md` updated with the
      new number.

## A small `ago-chat` addition, and two unrelated live-discovered config gaps

`GET /api/v1/attachments/{id}` gained `contentType` and `thumbnailUrl` (nullable) alongside the
presigned `url` it already returned - the widget has no other way to know whether to render an inline
image or a download link without guessing from the URL's own file extension, and `file-storage.md`'s
own Access-control section already caches this exact read, so the addition is one extra presign inside
an existing cache entry, not a new round trip. `GetAttachmentDownloadUrlHandlerTests` covers both the
with- and without-thumbnail cases.

Two things unrelated to attachments blocked verifying this item locally and were fixed as part of it,
since they made the fan-out path impossible to test at all: `Ago.Chat.Worker` crashed at startup
locally with `Set Redis:ConnectionString` (`4-04`'s presence consumers need `IConnectionRegistry`;
neither `Ago.Chat.Worker/appsettings.Development.json` nor `k8s/base/worker.yaml` were ever updated
when `4-04` shipped) - fixed in both files. `k8s/base/api.yaml`/`worker.yaml` are also both missing
`Storage__S3__*` entirely - **not** fixed here (needs the same secret-naming reasoning `api.yaml`'s
existing Postgres/RabbitMQ env vars already worked out, more than this item's scope justifies), noted
in `file-storage.md` instead.

## Open questions

None going in - scope followed directly from the skill's own already-written "Uploads" section. One
surfaced during the work and is tracked separately, not left blocking here: see `5-11`.
