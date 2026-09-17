# 25-126 · The booking chip reads as a plain link in a cramped header

- **Stage**: 25
- **Depends on**: nothing
- **Status**: done — `ago-widget#92`. Deployed live (`ago-deploy` pin `c4c3b73`), smoke 42/0.
- **Found**: 2026-09-17, the author screenshotting the live widget: the booking chip ("Запись") sits
  squeezed into the header between the title and the close button, styled by `.ago-module-chip`
  (`ui/styles.ts`) as `border: none; background: transparent; color: inherit` - a real `<button>`
  element (`ui/widget.ts`'s `loadBookingModuleChip`) that visually reads as a plain text link.

## Scope

- Rename the chip's Russian copy from "Запись" to "Записаться" (`modules/booking/chip.ts`'s own
  `COPY.ru.label` - `ariaLabel`/`triggerText` are separate fields, check whether either needs a
  matching change or is intentionally already correct).
- Restyle `.ago-module-chip` as a real, visually prominent button - background color, padding, a
  border-radius, matching this widget's own existing button weight (`.ago-attach`/`.ago-save`/
  `.ago-emoji` are icon-only chrome; look instead at whatever this widget uses for its one existing
  labelled call-to-action, if any, or establish a sensible brand-colored pill button consistent with
  `tokens`/colors already defined in `ui/styles.ts`).
- Reposition it out of the cramped header row (currently inserted via
  `this.closeButton.parentElement?.insertBefore(chip, this.closeButton)`) to somewhere lower and more
  prominent - the author's own screenshot annotation points down and to the right, toward the area
  just above the composer. Use your own judgment for the exact final placement, consistent with this
  widget's existing layout (header stays title+close only; the scrollable thread; the fixed composer
  row) - a full-width or right-aligned banner/button sitting between the thread and the composer is
  one reasonable shape, but is not mandated. Whatever is chosen, it must not overlap or crowd the
  composer's own attach/emoji/save controls, and must remain reachable by keyboard tab order.
- The chip's own hide/reveal timing (grant-gated, per `loadBookingModuleChip`'s own remarks) is
  unchanged - this item only touches its label, styling and position, never when it appears.

## Where this is likely to go wrong

- **This chip is a real, already-wired `<button>`** with a click handler elsewhere in `ui/widget.ts` -
  do not rebuild it as a link or a second element; restyle and reposition the existing one.
- **Keep it inside the widget's own gzip budget** - a styling/position change costs nothing meaningful;
  do not reach for an icon library or new dependency for this.
- **A real-browser (`ux-gate`) check matters here** - this is a pure layout change jsdom cannot prove;
  confirm the chip renders in its new position, at its new size, without overlapping the composer row,
  in both the mobile and desktop `ux-gate` viewports.

## Done when

- [x] The chip reads "Записаться", styled as a real, visually distinct button - a solid accent pill
      matching `.ago-contact-capture-submit`, not a plain link.
- [x] It renders lower and to the right, moved out of the header to sit right above the composer -
      confirmed with real `ux-gate` screenshots in both viewports (375×812, 1280×800), not assumed
      from CSS alone.
- [x] Keyboard tab order still reaches it, and its own click behavior (inserting/sending the trigger
      text) is unchanged - it stays the same already-wired `<button>`, only restyled and repositioned.
