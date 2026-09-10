# 25-35 · Saving a conversation fails live

- **Stage**: 25
- **Status**: in progress — **the real cause found and fixed, `ago-widget#78`; not yet deployed to
  the demo stand, see below**
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

- [x] The actual failing step is identified from a real caught error, not inferred. — **neither of the
  two candidates this item named. Confirmed 2026-09-10 by reproducing live against the real demo
  origin (`demo-shop1.reserve-me.ru`), devtools open, a real send-then-save round trip.** The caught
  error is a plain `TypeError: Failed to fetch dynamically imported module`, and the network panel
  shows `GET widget-module-save.js → 404` — not a CORS failure at all (a CORS-blocked request never
  reaches a status code; this one gets a real 404). Confirmed the failure is origin-wide-unrelated by
  fetching `widget-module-booking.js` from the identical origin at the identical moment: 200. Root
  cause: `Dockerfile` (`ago-widget`) has a `COPY` line shipping `widget-module-booking.js` into the
  served image but never gained the matching one for `widget-module-save.js` when `23-62` added it —
  `build.mjs` emits the file correctly (confirmed in `dist/`), it simply never reached
  `/usr/share/nginx/html/`.
- [x] The fix lands wherever that step's own cause actually lives. `ago-widget#78` — the missing two
  `COPY` lines, mirroring the booking module's own shape exactly. Fails-before: built the `assets`
  image target without the change (404), then with it (200, file present, byte-identical to `dist/`).
- [ ] Re-verified live: saving a real conversation produces a real downloaded file. **Not yet —
  `ago-widget#78` is merged but the demo stand's own `ago-demo-shop1`/`ago-demo-shop2`/
  `ago-widget-assets` images still predate it.** This box stays open until that deploy happens and a
  real save is re-tested against the live origin, not the merge alone.
