# 26-10 · The design system: tokens, type, and how an identifier is rendered

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, filed ahead of every screen item deliberately. `architecture.md` §"How an
  identifier is rendered" states a convention the console applies at a dozen call sites and asserts in
  its own tests; a second client that truncates differently makes reading an id aloud to a colleague
  impossible, and the cheap moment to prevent that is before the first list row exists.
- **Verified**: 2026-09-21 — `ago-console/src/design/tokens.css` exists and is the palette source
  `26-00`'s mockups were drawn against (`ago-android/docs/README.md`). The eight-character monospace
  rule and the `visitorDisplayPrefix` composite are read from `ago-android/docs/architecture.md`.
- **Depends on**: `26-07`.

## What this item is

One place the app's colours, type, shapes and identifier rendering are defined — so the twenty screens
after it inherit them rather than each deciding. One promise: **the app looks like this product, and
an id looks the same here as it does in the console.**

## Scope

- **A Material 3 `ColorScheme`, typography and shape set transcribed from
  `ago-console/src/design/tokens.css`.** Read once, deliberately, into one file. This is not a second
  design system — `adr/0030` is the console's decision about its own closed set, and this is that
  decision's Android reading.
- **Light and dark**, plus an explicit decision about **Android 12+ dynamic colour**: whether the
  device's wallpaper palette is allowed to override the product's own, and which wins where.
  `scope-inventory.md` §10 names it as sitting beside the three-state system/light/dark choice and
  does not decide it. Decide it here, and record the decision in `ago-android/docs/architecture.md` in
  the same change.
- **`IdentifierText` — the eight-character monospace rule, in exactly one composable.** Never a
  `take(8)` at a call site. `architecture.md`: every id in this product is a GUID, no screen prints
  one in full, and eight hex characters is what the console shows for `visitorId`, `operatorId`,
  `calendarId`, `conversationId`, `siteId` and `customerId` alike.
- **`VisitorDisplayPrefix`** — the composite `{emojiCreature}{emojiFood} {visitorName?}
  {visitorId.take(8)}`, where **each part is genuinely absent rather than blank when unknown** (a
  visitor predating the emoji column renders as the short code alone), and the emoji pair carries its
  own deliberately larger size, as `25-162` already does on the web.
- **Every user-facing string in `strings.xml` from the first screen**, Russian as the default locale.
  A literal inside a composable is the expensive thing to undo later; the absence of a second locale
  is not. No second locale is authored here.

## Out of scope

- **A hand-rolled component library.** `adr/0030`'s hand-rolled-components reasoning was about a
  codebase with no component library available; Compose ships Material 3, and re-deciding that would
  be reading an ADR's conclusion without its premise.
- The tablet breakpoint and `ListDetailPaneScaffold` (`plan.md`: phone first, tablet last).
- Any screen from `scope-inventory.md`.
- A second locale, and any translation workflow.

## Done when

- [ ] Palette, type and shape are defined in one place, and the convention against hardcoding a colour
      at a call site is enforced by a lint rule if one is cheap, or written down explicitly if it is
      not — say which was done.
- [ ] `IdentifierText` has unit tests covering a full GUID truncated to eight characters and a value
      shorter than eight.
- [ ] `VisitorDisplayPrefix` has unit tests covering: both emoji present, no name; name present; **no
      emoji pair at all** (the pre-column visitor, which must render the short code alone and not a
      gap); and a name containing a space.
- [ ] Light and dark both render the placeholder screen correctly on a real device.
- [ ] The dynamic-colour decision is recorded in `ago-android/docs/architecture.md` in this change.
- [ ] No user-facing literal string exists outside `strings.xml`.
