# 25-27 · The consent checkbox label names a document but cannot open it

- **Stage**: 25
- **Status**: done — `ago-widget#76`
- **Depends on**: `24-05` built the checkbox; `23-37` built the public `/policies/:documentKey` page
  this item points the link at
- **Found**: 2026-09-09, the author's own request

## What is actually true

`ago-widget/src/ui/contactCapture.ts`'s `buildConsentLabel` renders a consent checkbox's label as
plain `textContent` — the tenant's own document title (e.g. "Согласие на обработку персональных
данных"), with no link at all. A visitor sees the name of a document they are being asked to accept
and has no way to read it before checking the box. The identical shape exists for both purposes this
control renders (`contact`/`marketing`) — whichever tenant's document is shown, it is unreadable from
the widget.

The read path already exists elsewhere: `DocumentsPage.tsx` (`ago-console`) already links a document's
current version to `/policies/${encodeURIComponent(documentKey)}`, a real public page `23-37` built.
The widget just never uses it.

## Scope

- The document-title portion of the checkbox label becomes a real link — underlined, visibly a link,
  not a color change alone — to `/policies/<documentKey>` (or wherever the actual public policy route
  resolves for a given site/tenant; check `23-37`'s own routing, since the widget runs on the tenant's
  own origin and the policy page is served from `office.reserve-me.ru`, not the tenant's site, so the
  link needs an absolute URL).
- The link opens **in a new tab/window** (`target="_blank" rel="noreferrer"`, the same pattern
  `DocumentsPage.tsx`'s own "read as visitor" link already uses) — clicking it must not navigate the
  visitor away from the conversation they were about to continue.
- Applies to both consent purposes the widget ever shows (`contact`, `marketing`) — "если это ссылка
  от тенанта — то же самое" is the author's own instruction: whichever tenant's document is being
  named, it gets the identical treatment.
- The checkbox itself, its required/optional behavior, and everything else about `24-05`'s consent gate
  is unchanged — this item only makes the label's document name a working link.

## Where this is likely to go wrong

- **The widget runs embedded on the tenant's own site**, not on `office.reserve-me.ru` — the link must
  be an absolute URL to the policy page's real host, not a relative path that would resolve against the
  tenant's own origin instead.
- **The checkbox's own click target must not shrink or become ambiguous.** Making part of the label a
  link changes what a click on that specific text does (opens the policy) versus a click elsewhere in
  the label (toggles the checkbox) — verify both interactions still work as a visitor would expect,
  and that clicking the link text does not also toggle the checkbox underneath it.
- **Bundle budget.** This is the widget's own bundle — a link element and an absolute URL construction
  should cost nothing meaningful, but the build's own size check is how that gets proven, not assumed.

## Done when

- [x] The consent checkbox's document-title text is an underlined, visibly-a-link element pointing to
      that document's real public policy page.
- [x] The link opens in a new tab, and does not navigate the visitor's own conversation away.
- [x] Both consent purposes (contact, marketing) get the identical treatment.
- [x] Clicking the link does not also toggle the checkbox; clicking the checkbox is unaffected by the
      link now being present.

## Outcome

`ago-widget#76`. A new `WidgetConfig.policyBaseUrl`, baked at build time like `apiBaseUrl` but with
no inference from it (the console and the API are unrelated hosts by design), gives `buildConsentLabel`
an absolute URL to `/policies/:documentKey`. The link's own `click` handler calls `stopPropagation` —
that is what keeps the checkbox's own click target unambiguous, verified by a dedicated test in both
directions. Bundle cost: +0.3 KB gzipped (33.3 → 33.6 KB), well inside the 45 KB budget.
