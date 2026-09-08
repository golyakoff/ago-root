# no file over five megabytes is accepted

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing.
- **Decision**: the author's, 2026-09-07 — 5 MB is enough for a photograph or a document.

## Can we refuse files over 5 MB today? Yes, and almost for free

The mechanism is built and proven. `AttachmentOptions.MaxSizeBytes` is a bound option in the
`Attachments` configuration section, and since `5-13` the **exact declared length is signed into the
presigned PUT** — MinIO recomputes the signature over the real `Content-Length` and answers
`403 SignatureDoesNotMatch` before accepting a byte. Two layers, verified against a real MinIO.

So the change is a **number**, not a mechanism:

- the code default is `10 * 1024 * 1024` in `AttachmentOptions`;
- **the demo overlay sets nothing at all** — checked, there is no `Attachments__MaxSizeBytes` anywhere
  in `ago-deploy` — so the deployment runs on that default.

Which means it can be changed by configuration alone on a running deployment, and by editing one
literal for every deployment that never configures it. Do both: the default is what a new environment
gets, and leaving it at 10 while the intent is 5 is how the two drift.

## What is not free, and is the actual content of this item

- **The widget must refuse before uploading**, with a message a person can act on — *«файл больше 5 МБ»*,
  not a failure after a progress bar has run. Today the ceiling is enforced at presign and at storage;
  the client should not discover it last.
- **The gateway body-size policy** (`ago-chat-gateway-body-size`) is a separate number in
  `ago-deploy`, and nothing keeps the two in agreement. They answer different questions and they should
  not contradict.
- **Existing attachments are larger than the new limit** and stay valid. A ceiling applies to what is
  accepted, never retroactively to what was accepted — anything else deletes a customer's file because
  we changed our mind.
- **`file-storage.md` names the old number** and stops being true the moment this lands.

## Where this is likely to go wrong

`AttachmentOptions`' own doc comment says its defaults are *"a starting point, not measured or
load-tested"*. Five megabytes inherits that honestly: it is a judgement about what a photograph or an
invoice needs, not a measurement. Say so where it is written rather than letting the number acquire
authority by being newer.

## Done when

- [x] `AttachmentOptions.MaxSizeBytes` default: 10 MiB to 5 MiB. Two layers, both already proven
      against real MinIO since `5-13`: `CreateAttachmentHandler`'s presign check, and the exact
      declared length signed into the presigned PUT itself. The demo overlay sets no
      `Attachments__MaxSizeBytes`, checked again for this item, so the code default governs it.
- [x] `COURTESY_MAX_SIZE_BYTES` in `ago-widget`'s `attachments.ts`: 10 MiB to 5 MiB, matching the
      server. The pre-upload courtesy check an earlier item already built; a visitor is refused
      before the upload starts, not after a progress bar has run.
- [x] Confirmed rather than assumed: `ago-chat-gateway-body-size` caps at `1m`, smaller than 5 MiB -
      but an attachment PUT goes browser to object storage directly on a presigned URL and never
      crosses this gateway (`adr/0008`), checked against the routing table. The two ceilings answer
      different questions and were never in tension.
- [x] `MaxSizeBytes` is read in exactly one place - `CreateAttachmentHandler`'s presign check on a
      *new* upload, confirmed by grep across `src/`. `ConfirmAttachmentHandler` and every
      download/query path never compare against it, so a `ready` row already above 5 MB is
      structurally untouched.
- [x] Landed with the reasoning, the gateway check, and the not-retroactive guarantee stated
      explicitly rather than left implicit.
