# the compose area gives the text the whole width

- **Stage**: 23
- **Status**: ready
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

- [ ] The text field occupies the full width of the compose area.
- [ ] Send is a round, icon-only button with an accessible name, and meets the target-size floor.
- [ ] Attach, the reserved emoji place and the reserved save place sit on their own row beneath.
- [ ] The mobile layout is checked, not assumed, and the widget's bundle budget still holds.
