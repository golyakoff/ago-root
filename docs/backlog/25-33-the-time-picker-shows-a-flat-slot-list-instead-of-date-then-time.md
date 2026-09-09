# 25-33 · The time picker shows a flat slot list instead of date, then time

- **Stage**: 25
- **Status**: ready
- **Depends on**: `25-32` (real slots have to reach this step before its own shape is worth
  redesigning)
- **Found**: 2026-09-09, the author's own request, testing the booking flow live

## What is actually true

`ModuleStepFactory.SlotChoice` renders every open slot as one flat numbered list — ten slots
(`SlotPageSize`) at once, each its own line, with no grouping by day. `ui/primitives/render.ts`'s own
comment already names this as a deliberate, acceptable first slice: *"rendering `actions` as a flat
button list is a correct, acceptable slice, and a calendar-grid using `startsAt` is a bonus rather than
a requirement."* The `SlotOption`/`OpenSlotRow` shape already carries `startsAt`, unused for grouping.

## What the author wants instead

- **Pick a date first**, from a calendar of dates that actually have availability — not a flat list of
  every slot across every day at once.
- **Then pick a time**, from the slots that exist within the chosen date.
- **If the calendar has more than one worker**, offer a way to choose a specific one — today's flow
  already has a worker-choice step (`ModuleStepFactory.WorkerChoice`) for the multi-worker case; this
  item is about making that step's existence and framing deliberate and visible in the redesigned flow,
  not about building worker choice from scratch.

## Where this is likely to go wrong

- **The four-primitive vocabulary is closed** (`adr/0065` §4: `choice_list`/`form`/`confirmation_card`/
  `date_time_picker`, no fifth kind). A real date-then-time flow needs to fit inside `date_time_picker`
  itself — most likely two rounds of it (a date-granularity round, then a time-granularity round for the
  chosen date) rather than a new primitive kind. Read `adr/0065` before assuming a new kind is the
  answer; it almost certainly is not.
- **This has to work identically on every channel this module task serves**, not only the widget —
  `ReplyToModuleTaskHandler`'s own remarks say the wire payload is shared across channels
  (`ModuleStepFactory`'s own doc comment: "shared by `StartModuleTaskHandler` and
  `ReplyToModuleTaskHandler`"). A calendar-grid UI is a widget-side rendering choice; the two-step
  date-then-time *shape* has to be expressible as the existing prompt-plus-labelled-choices contract for
  a text channel too.
- **`SlotPageSize` (10) exists for a text channel's own reason** ("a text channel printing a numbered
  list of sixty times is not a menu, it is a wall of text") — a date-first split changes what belongs on
  each screen; revisit that constant's own reasoning rather than assuming it still applies unchanged
  once slots are grouped by day.
- **Do not build this before `25-32` lands.** Redesigning the shape of a step that currently returns no
  slots at all has nothing real to design against.

## Done when

- [ ] A visitor picks a date first, from dates that actually have availability, then picks a time
      within that date.
- [ ] A calendar with more than one worker offers a way to choose one, and the item states where that
      choice sits relative to the date/time picker (before, after, or folded into it).
- [ ] The shape works within the existing four-primitive vocabulary, or the item names exactly why a
      fifth is unavoidable and gets that decision recorded as its own ADR before building it.
