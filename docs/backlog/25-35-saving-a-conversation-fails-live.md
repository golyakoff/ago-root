# 25-35 · Saving a conversation fails live

- **Stage**: 25
- **Status**: ready — **one of two candidates ruled out by reading the code (2026-09-09); live
  re-verification against the real deployment still needed, see below**
- **Depends on**: `23-62` built the feature; `25-30` fixed the same *class* of bug (CORS on a
  lazily-loaded module chunk) for `widget-module-booking.js` — check first whether that fix already
  covers `widget-module-save.js` or whether a second, different cause is at play
- **Found**: 2026-09-09, live — the author clicked "Сохранить диалог" on a real conversation and got
  *"Не удалось сохранить диалог. Попробуйте ещё раз."*

## What is actually true

`ChatWidget.saveConversation` (`ui/widget.ts`) dynamically imports `widget-module-save.js`
(`loadModule(this.config.scriptUrl, "widget-module-save.js")`), then calls
`buildConversationArchive`, which walks history via `connection.loadOlderHistory` and resolves any
attachment locations via `fetchAttachmentLocationForExport`. Any failure anywhere in that chain is
caught in one place and shown as the generic `saveConversationFailedNote` — by design
(`embeddable-widget`'s "never break the host page"), but that also means the visible symptom carries
no information about which step actually failed.

**Not yet isolated which step failed for the reported conversation.** Two known, real candidates,
neither confirmed nor ruled out:

1. **The same CORS class `25-30` already fixed for `widget-module-booking.js`.** `widget-module-save.js`
   is dynamically imported exactly the same way, from the same nginx server `25-30` patched. If the
   reported failure happened *before* that fix's rollout reached this conversation's own page load
   (cached script, or tested against a stale demo page), this may already be resolved — check the
   timing and re-test before assuming a second bug.
2. **`25-14`, already filed and still open**: no bucket CORS policy exists for presigned attachment
   `GET`s, so `fetchAttachmentLocationForExport`'s own real-bytes `fetch()` fails cross-origin for any
   conversation that has an attachment. Check whether the reported conversation had one.

## Scope

- Reproduce live (a real conversation, on a real embedding origin — not the console) with the browser's
  own console open, and read the actual caught error `logWidgetError` already logs — this alone should
  settle which of the two candidates above it is, or reveal a third cause neither anticipated.
- Fix whichever cause is confirmed. If it is `25-14`'s own gap, this item can close as a duplicate once
  that one lands; if it is something `25-30` did not cover, scope the real fix here.

## Where this is likely to go wrong

- **Don't guess between the two candidates above — check.** They have different fixes in different
  places (nginx config vs. bucket CORS policy), and applying the wrong one would look like a fix while
  leaving the real cause live.
- **A conversation with no attachments at all is still worth testing separately** from one that has
  one, since the two candidate causes only overlap on the module-loading step, not the attachment step.

## Done when

- [~] The actual failing step is identified from a real caught error, not inferred. — **one candidate
  ruled out by reading the code, not yet confirmed which of the remaining ones it actually is.**
  `25-14` cannot be the cause: `fetchAttachmentLocationForExport`/`fetchAttachmentBytes` both catch
  every failure internally and omit the attachment rather than rethrow, so a CORS-blocked attachment
  fetch cannot produce the generic total-failure `saveConversationFailedNote` this report describes.
  The remaining live candidate is `loadModule`'s dynamic `import()` of `widget-module-save.js` — an ES
  module import is a real CORS-mode fetch, unlike a `<script src>` tag. `25-30`'s nginx fix already
  wildcards `Access-Control-Allow-Origin: *` on every file that server serves, generically, so it
  should already cover this file too; the live report may simply predate that fix reaching the tested
  page (a stale cached script). Needs an actual live re-test to settle, not further reading.
- [ ] The fix lands wherever that step's own cause actually lives.
- [ ] Re-verified live: saving a real conversation produces a real downloaded file.
