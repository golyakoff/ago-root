# 25-150 · The tooltip clipping fix works on every other open

- **Stage**: 25
- **Status**: done — `ago-console#255`
- **Found**: 2026-09-17, live, reported by the author on `Tooltip.tsx`'s own vertical-clipping fix
  (`25-123`, deployed as `e883ba0`): "работает строго через раз" - hover the trigger once, the bubble
  positions correctly; move away, hover again, it overflows; and this alternates indefinitely, not a
  one-shot race.
- **Depends on**: none. Touches `ago-console` only.

## What was actually wrong - two layers, both found by direct reproduction, not code-reading alone

**Layer 1, the shipped bug.** `Tooltip.tsx`'s positioning override lived in a `bubbleStyle` React
state variable, applied via `style={open ? bubbleStyle : undefined}`. Nothing ever reset
`bubbleStyle` on close - the render expression masked it instead. So a bubble reopening measured
itself while *still carrying the previous open cycle's own override* in the same commit the
measurement effect reads from: a stale `max-width` read back as "already narrow enough", clearing the
override outright; the next open then measured the bubble's true, unclamped width and correctly
reintroduced the override; the open after that read the reintroduced override as stale and cleared it
again - alternating forever. Reproduced with a real repeated-hover Playwright script before touching
any code, confirming this is a genuine every-other-open oscillation, not a timing-sensitive one-shot.

**Layer 2, introduced by the first fix attempt, also found live before being trusted.** Resetting the
bubble's own inline style with a raw DOM write (`bubble.style.left = ""`, etc.) at the top of the
effect, *before* measuring, fixed the measurement (every cycle now read the bubble's true size) but
broke the *application*: React's own renderer tracks, per element, the style object it last rendered,
and diffs a new `style` prop against *that memory* - it has no way to know a raw `element.style.x =
...` write happened outside its own reconciliation. Once the fresh computation produced a style with
the same field values as what React remembered already applying (the identical shrink was needed
every cycle, since the layout itself never changes), React saw no value-level change and skipped
writing to the DOM - leaving the bubble stuck *unstyled and overflowing, permanently*, the opposite
failure from the same repeated-hover script.

## Scope - what actually shipped

- `Tooltip.tsx`'s positioning is applied **entirely imperatively**, via direct native DOM property
  assignment (`bubble.style.left = value`), with **no React-managed `style` prop on the bubble
  element at all** - both the reset and the final computed style, every run, unconditionally. This
  removes the possibility of React and the DOM disagreeing about what is currently applied, since
  there is only ever one writer of that element's `style` attribute.
- `bubbleStyle` state and the `CSSProperties` import are removed entirely - nothing to keep in sync
  with the DOM going forward.

## The test, and why its first version would not have caught the bug it was written for

`ux-gate/tooltipPositioning.spec.ts` gained a test that hovers a real trigger eight times in a row,
checking overflow via `measureTooltipTriggerOverflow` (an independent re-implementation of
`findClippingRect`, never trusting the component to grade its own homework) after every open. Two
things had to be gotten right that were not obvious in advance:

- **`expect.poll(...).toBe(0)`**, the pattern this file's own other two tests already use for a
  genuine one-shot async-settling race, empirically **failed to catch this alternation bug even when
  run directly against the confirmed-buggy shipped code** - verified by swapping in
  `origin/main`'s own `Tooltip.tsx` and running the new test against it before writing the fix. A
  single direct read, taken after a real `page.waitForTimeout(150)` settling delay, correctly failed
  before the fix and passed after - used instead, with a comment explaining the deliberate departure
  from this file's own `expect.poll` convention.
- **A real delay is required between "mouse away" and the next `hover()`.** Calling `trigger.hover()`
  on the very next loop iteration after `page.mouse.move(0, 0)`, with nothing between them, let React
  batch the resulting `setOpen(false)` immediately followed by `setOpen(true)` into one net-unchanged
  commit - silently skipping the component's own measurement effect for that "cycle" entirely, which
  made the test pass regardless of whether the underlying bug was fixed. Confirmed live: without the
  explicit `page.waitForTimeout(150)`, the test could not be made to fail against the pre-fix
  component at all.

## Where this is likely to go wrong for whoever touches this file next

- **Never reintroduce a React-managed `style` prop on the bubble element for positioning.** Any future
  addition to this component's own visual state (a new positioning axis, an animation) must extend
  the imperative write, not add a second, React-tracked path alongside it - that reintroduces exactly
  the two-writer disagreement this item closes.
- A regression test for this class of bug (permanently-wrong-but-stable, or alternating-forever) needs
  more than two cycles and more than `expect.poll` to be trusted - both of this file's own findings
  above generalize to any future "does this component's state survive N open/close cycles" test.

## Done when

- [x] Hovering a tooltip trigger eight times in a row, with a real settling delay between each, never
      overflows its own container - the exact live-reported pattern
- [x] The regression test fails against the pre-fix component (verified by swapping it in) and passes
      against the fix
- [x] Full `ux-gate` suite green, no regression on the six other call sites `25-111` already covers
- [x] `npm run typecheck` / `npm run lint` / `npm run test -- --run` all clean
