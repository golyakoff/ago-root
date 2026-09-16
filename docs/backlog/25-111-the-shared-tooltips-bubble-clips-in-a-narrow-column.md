# 25-111 · The shared Tooltip's bubble clips in a narrow column

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: 2026-09-16, the author hovering the "(?)" trigger next to "ПОСЕТИТЕЛЬ" in the
  conversation page's right-hand visitor panel: the bubble renders overlapping the panel's own text,
  clipped at the panel's right edge, unreadable past the first few words.

## What is actually true today

`src/components/Tooltip.tsx` (`25-54`) is a shared component with seven call sites across three
panels, and its own doc comment names exactly this failure mode as the one thing it deliberately does
not attempt, and names what would justify revisiting it:

> What this does not attempt: viewport-collision detection (the bubble always opens below,
> left-aligned to the trigger) and multi-line reflow beyond a fixed `max-width`. Every call site this
> item adds lives inside the three-panel workspace's own bounded columns, never near a viewport edge
> in the console's supported widths - a positioning library would be solving a problem this
> application does not have yet... **The trigger to revisit this is a real report of a clipped
> bubble, not a hunch.**

This is that report. The right-hand visitor panel (`VisitorPanel`, one of the seven call sites named
in the component's own doc comment) is narrower than the workspace columns `25-54` verified against,
and a bubble opening "below, left-aligned to the trigger" with a fixed `max-width` runs off the
panel's own right edge there - not near a *viewport* edge, but near a *column* edge, which the
component's own reasoning did not distinguish.

## Scope

- `Tooltip`'s bubble must not clip inside any of its seven existing call sites, `VisitorPanel`'s
  narrow column included - reposition (right-align when a left-aligned bubble would overflow its
  container, or clamp `max-width` to the available space) rather than widen the panel itself, which is
  not this item's concern.
- Stay inside this component's own established constraints (hand-rolled, no positioning-library
  dependency, per its own doc comment's reasoning against one) unless investigation shows the fix
  genuinely needs one - state that explicitly rather than reaching for a library by default.
- Every one of the seven existing call sites (`ConversationList` x2, `ConversationPage`, `Thread`,
  `ConversationNotesPanel`, `ConversationOutcomePanel`, `VisitorPanel`) keeps working exactly as
  before wherever it already had room - this item fixes the narrow-column case, it does not redesign
  the component's default behaviour for every site that already renders correctly.

## Where this is likely to go wrong

- **Don't fix it by widening `VisitorPanel`** - that treats this component's own general positioning
  gap as a one-screen layout problem, and the next narrow column will hit the identical bug.
- **Keyboard/touch behaviour must survive whatever positioning logic is added** - the component's own
  hover/focus/Escape/`role="tooltip"` accessibility work (its own extensive doc comment) is not this
  item's to touch; only where the bubble renders, never how it opens or closes.
- **Test against the real narrow column**, not a synthetic one sized to make the fix easy - `VisitorPanel`
  at the console's actual supported widths is the failing case; verify against it directly.

## Done when

- [ ] The bubble in `VisitorPanel`'s "(?)" trigger renders fully readable, no clipping, no overlap
      with surrounding text, at the console's real supported widths.
- [ ] A fails-before test/screenshot proving the clip happens against the code before the fix and is
      gone after (this component has no existing test that would have caught a rendering-position
      regression - state whether one exists after this item, and at what level).
- [ ] The other six call sites are re-verified unaffected by whatever positioning change was made.
