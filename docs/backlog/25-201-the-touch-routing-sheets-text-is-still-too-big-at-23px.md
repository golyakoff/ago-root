# 25-201 · The touch routing sheet's text is still too big at 23px

- **Stage**: 25
- **Status**: done — `ago-widget#122`
- **Found**: 2026-09-21, the author, live on `golyakov.net` (mobile), immediately after `25-200`
  shipped: "иконки отличного размера, а вот шрифт я не угадал - крупновато". Shown a comparison
  Artifact (23px/20px/18px side by side, plus a live slider) to pick from without another round
  trip; picked **16px**, smaller than either of the two options that were offered.

## What is actually true today

`.ago-touch-routing-row` (`ui/styles.css`, set by `25-200`) has `font-size: 23px`. `25-200`'s own
Outcome section already records the reasoning for 23px (15px measured live, ×1.5, 22.5 rounded up) -
that reasoning is not wrong on its own terms, it is simply not the size the author wants once seen
next to the actual icons at their new 30px. This item exists only to change the one declared value;
nothing about `25-200`'s own scope, decoupling, or test approach needs revisiting.

## Scope

- Change `.ago-touch-routing-row`'s `font-size` from `23px` to `16px`. Nothing else - the icon
  sizing (`30px`, `25-200`) is explicitly confirmed good by the author and stays untouched.
- Update `touchRoutingSheetSizing.test.ts`'s own assertion of the exact value to `16px`.
- Update `25-200`'s own backlog file where it states the shipped value, so the record does not read
  as still describing `23px` after this item lands - a one-line correction, not a rewrite of that
  item's own history.

## Out of scope

- Any other row/placement (`AboveComposer`, `BelowLauncher`).
- Icon sizing.

## Done when

- [x] `.ago-touch-routing-row`'s `font-size` is `16px`, a plain whole-number `px` value.
- [x] The regression test's own declared-value assertion is updated to match.
- [x] Verified live (real browser, real built bundle - a screenshot or equivalent) that the row text
      renders at 16px and reads comfortably next to the unchanged 30px icons, with no clipping or
      overlap.
- [x] `25-200`'s own backlog file is corrected to note the value it originally shipped was later
      changed to 16px by this item, so the two files agree on current state.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.

## Outcome

Shipped as `ago-widget#122`. `.ago-touch-routing-row`'s `font-size` changed from `25-200`'s own
`23px` to `16px` - the author's own pick from a live comparison Artifact (23px/20px/18px side by
side, plus a slider to fine-tune) shown specifically to avoid another guess-and-correct round trip.
The icon sizing `25-200` added (`30px`, confirmed correct by the author) is untouched.

`touchRoutingSheetSizing.test.ts`'s declared-value assertion and doc-comment prose updated to match;
fails-before/passes-after reproven independently by the managing session (temporarily reverted the
CSS to `23px` from a backup copy, confirmed the test now correctly fails, restored and reconfirmed
green). `25-200`'s own backlog file carries a one-line correction pointing forward to this item,
leaving that item's own Outcome section as an untouched historical record of what it actually shipped
and measured.

Verified against a local build (`dist/widget.js`) served locally with a stubbed `fetch`/`matchMedia`
in a real (non-jsdom) browser: every row computes `font-size: 16px`, every icon stays unaffected at
`30px × 30px`, no clipping or overlap. `golyakov.net` itself does not show this until deployed
(workers never deploy) - the managing session deploys and confirms live as its own next step.
`npm run typecheck`/`lint` clean, `npm test` 503/503, `npm run ux-gate` 16/16 - independently
re-verified, not only taken on the worker's own report.
