# 25-104 · The console cannot set — or preserve — the attachment-upload default

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: `npm run
  typecheck`/`lint` clean, full console suite re-run at 1459/1459, exact match to the worker's own
  claim.
- **Depends on**: nothing
- **Found**: 2026-09-15, the author testing attachments live: "не вижу в консоли разрешения слать
  файлы" (no setting in the console to permit sending files).

## What is actually true

`WidgetConfig.AllowAttachmentUploadsByDefault` (`ago-chat/src/Ago.Chat.Domain/WidgetConfig.cs`) is a
real, site-level, off-by-default setting that seeds a new conversation's own per-conversation upload
grant at `StartConversationHandler` time. The backend is complete end to end —
`GetWidgetConfigHandler`, `UpdateWidgetConfigHandler`, `WidgetConfigDto` and
`WidgetConfigEndpoints.cs` all already read and write it.

**The console never exposes it.** `src/api/widgetConfigApi.ts`'s own `WidgetConfigDto` interface has
no `allowAttachmentUploadsByDefault` field at all, and `WidgetConfigPage.tsx`'s form has no panel for
it — this is the gap the author's own report names directly.

**A second, more serious bug sits underneath the missing screen.** The PUT request body
`WidgetConfigPage.tsx` builds never includes `allowAttachmentUploadsByDefault`, and the server's own
`UpdateWidgetConfigRequest.AllowAttachmentUploadsByDefault` is a **non-nullable `bool` defaulting to
`false`**. So today, **every time a tenant saves any other widget setting through the console, this
flag is silently reset to `false`** for that site — even if it had ever been turned on some other way
(directly against the API, or once this item adds a console control for it). A missing screen is a
gap a tenant can work around by asking; a silent reset on an unrelated save is a trap that undoes the
workaround.

Per-conversation, the operator-facing control already exists and already works —
`AttachmentUploadGrantToggle.tsx`, gated on `Permission.ConversationAttachmentUploadGrant`, wired into
`ConversationPage.tsx`. This item is about the site-level *default*, which has no console surface of
its own at all.

## Scope

- Add `allowAttachmentUploadsByDefault` to `WidgetConfigDto` (`widgetConfigApi.ts`) and to
  `WidgetConfigPage.tsx`'s own form — a real toggle, in a place that fits the page's existing layout
  (an "Attachments" panel, or beside whatever section reads closest to it today — state which and
  why).
- **Fix the PUT body first, or in the same change** — it must always include this field's current
  value (read-then-write, the same discipline every other field on this form already has), not omit
  it and let the server's own default silently win. This is the fix that stops today's active data
  loss, independent of whether the toggle itself is pretty.
- Off is still the state a fresh site lands in, always — this item does not change the default's own
  default.

## Out of scope

- Anything about the per-conversation grant/`AttachmentUploadGrantToggle.tsx` — already built,
  already working, a separate control for a separate question.
- The widget's own paperclip visibility — already fixed (`23-78`), confirmed live on the currently
  deployed build.
- Whether a presigned upload actually reaches storage once granted — `25-103`, a separate,
  infrastructure-level gap.

## Done when

- [x] A tenant, through whichever permission already gates `WidgetConfigPage.tsx`, can turn the
      site-level attachment default on and off from the console — a new "Attachments" panel, kept
      separate from the page's other four panels since it answers its own distinct question
      (`25-24`'s own precedent for what earns a panel of its own). The console reads the real current
      value from `GET`, never an assumed one.
- [x] Saving any other widget setting from the console no longer resets this flag. The field was
      given the identical four-part lifecycle (state, load-from-GET, include-in-PUT, resync-from-PUT)
      every other boolean on this form already has — proven by a test that sets it on, saves through
      an unrelated field, and asserts it is still on afterward; fails-before confirmed by reverting
      the PUT-body inclusion and watching that exact test fail.
