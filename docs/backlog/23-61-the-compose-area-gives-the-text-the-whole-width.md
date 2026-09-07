# the compose area gives the text the whole width

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing
- **Decision**: the author's, 2026-09-07, describing the layout they want.

## What is actually true today

`.ago-composer` is a single flex row: the input, the send button and the attach button share one line.
So the field a visitor actually types into is the narrowest part of the widget, and it gets narrower
every time a control is added beside it — which is exactly what the next few items do.

## Scope

- **The text field takes the full width of the area**, on its own row.
- **Send becomes a small round icon-only button.** No label. It needs an accessible name regardless —
  an icon-only control with no `aria-label` is invisible to a screen reader, and the ux-gate already
  checks for that class of defect.
- **A second row underneath carries the controls**: attach a file (which exists today and moves), a
  reserved place for emoji, and a place for «Сохранить диалог» (`23-62`).
- **The emoji place is reserved, not built** — the same shape `23-31` used for the console's navigation.
  A reserved place that does nothing must look reserved rather than broken, and must not be reachable
  by keyboard as though it were a control.

## Where this is likely to go wrong

- **The widget is not one size.** It is embedded on a stranger's site and has a mobile layout; a two-row
  composer eats vertical space, which is scarcest exactly there. Check the small viewport first rather
  than last.
- **The send button is the one control that must never become hard to hit.** A small round button is a
  target-size question: WCAG 2.5.8's 24px floor is the same rule that caught a checkbox in `23-35`.
- **Shadow DOM.** The widget's styles are its own; nothing here may leak into or inherit from the host
  page. That is the whole point of the boundary and it is easy to break with a new layout.

## Out of scope

- An emoji picker. This reserves its place; choosing and building one is a separate item.
- «Сохранить диалог» itself, which is `23-62`. This item leaves the place for it.
- The message list above the composer.

## Done when

- [x] The text field occupies the full width of the compose area.
      `ago-widget` `c66527e`.
- [x] Send is a round, icon-only button with an accessible name, and meets the target-size floor.
- [x] Attach, the reserved emoji place and the reserved save place sit on their own row beneath.
- [x] The mobile layout is checked, not assumed, and the widget's bundle budget still holds.
      **Mobile was checked and the check found something.** Building the second row cost `.ago-attach`
      the full-height hit area it had been getting free from a taller sibling, collapsing it to 20px —
      under WCAG 2.5.8's 24px floor, with nothing on the element itself having changed. An explicit
      2rem box replaces that accident.
      **The bundle budget holds: 30.8 KB gzipped against 45 KB**, measured on `main` after this landed.
      **Corrected 2026-09-07.** This box was first marked `[~]` saying no figure was recorded and that
      this repository has no size budget check to record one against. The second half was simply wrong:
      `build.mjs` declares `GZIP_BUDGET_BYTES = 45 * 1024` and calls `process.exit(1)` when the real
      `dist/widget.js` exceeds it, and CI runs `npm run build` on every push. So the budget is enforced
      by the build itself — which means this item passing CI *was* the proof, and a stronger one than a
      number written down afterwards. I looked in `package.json`, the Vite config and the CI workflow,
      found only a prose mention, and concluded there was no check instead of reading the build script.
