# 25-123 · The tooltip bubble has no vertical clipping fix

- **Stage**: 25
- **Depends on**: nothing (extends `25-111`'s own fix to the other axis)
- **Status**: done — `ago-console#252`. Deployed live (`ago-deploy` pin `0b8ffb1`), smoke 45/45.
- **Found**: 2026-09-17, the author reporting "tooltips intermittently break the layout, going outside
  their bounds" with a screenshot of `Thread.tsx`'s delivery-scope tooltip bubble clipped at the bottom.

## What is actually true today

`25-111` gave `Tooltip.tsx` real clipping-aware positioning, but only on the **horizontal** axis:
`findClippingRect` returns `{ left, right }`, and the `useLayoutEffect` measures `spaceLeft`/`spaceRight`
against the trigger to decide whether the bubble stays left-aligned (the CSS default,
`.ago-tooltip__bubble`'s own `left: 0`) or flips to right-aligned, shrinking `max-width` as a last
resort. There is no equivalent for **vertical** space at all - `components.css`'s own
`top: calc(100% + var(--ago-space-2))` is unconditional, and the bubble always opens downward,
regardless of how much room actually exists below the trigger inside the nearest clipping ancestor.

`ux-gate/lib/tooltipOverflow.ts` (the Playwright-side measurement, deliberately a separate
implementation from the component's own, per its own doc comment - "to prove what the browser
actually painted, independently of whether the component's own arithmetic agrees with itself") mirrors
this gap exactly: it returns `overflowLeftPx`/`overflowRightPx` only, nothing for top/bottom.

**Why this reproduces "intermittently", specifically**: `Thread.tsx`'s own delivery-scope tooltip
(`strings.threadDeliveryScopeNote`) sits at the very top of the scrollable `.ago-thread` message list
(`<div className="ago-thread__delivery-tooltip">`, immediately before the `<ol>`). `findClippingRect`
treats any ancestor with `overflow-y` not `visible` as the clip boundary regardless of whether that
ancestor is *currently* scrolling - a short conversation (few messages) can render that scrollable
region shorter than the bubble's own height, so the bubble opening downward from a trigger near its
very top clips against the region's own bottom edge. A long conversation's identical tooltip has room
and never clips - which is exactly "works most of the time, breaks for some conversations" rather than
a flat, always-reproducible break. `ux-gate/tooltipPositioning.spec.ts`'s own doc comment already
half-anticipated this ("Thread's delivery-scope tooltip... may or may not be among them" - conditional
on fixture state) without ever actually reproducing the clipped case.

## Scope

- Mirror `25-111`'s own horizontal shape onto the vertical axis, in the same file, the same way:
  - `findClippingRect` also returns `top`/`bottom`.
  - The `useLayoutEffect` measures `spaceBelow`/`spaceAbove` the same way it measures
    `spaceRight`/`spaceLeft`, and flips the bubble to open **above** the trigger
    (`top: "auto", bottom: "calc(100% + var(--ago-space-2))"`, mirroring the CSS default's own gap
    value) when there is not enough room below, picking whichever side has more room when neither
    fully fits - the identical `alignRight = spaceLeft > spaceRight` shape, applied to `alignAbove`.
  - No vertical analogue of the horizontal case's `max-width` shrink is expected - shrinking a bubble's
    *height* does not reflow its text into fewer lines the way shrinking width does, so there is no
    equivalent last resort worth building; say explicitly in the code why one was not added, rather
    than leaving the asymmetry unexplained.
- `ux-gate/lib/tooltipOverflow.ts`'s measurement gains the equivalent `overflowTopPx`/`overflowBottomPx`
  (or fold into one `overflowPx` the way the horizontal case already does - implementer's call, state
  which and why).
- A real, fails-before-passes-after Playwright test reproducing genuine vertical clipping - needs a
  fixture where a tooltip trigger sits near the top of a short scrollable container (`Thread.tsx`'s own
  delivery-scope tooltip against a conversation fixture with few enough messages that `.ago-thread`'s
  own rendered height is shorter than the bubble). Check `ux-gate/fixtures/` for what already exists
  before inventing a new fixture from scratch.

## Where this is likely to go wrong

- **Do not just add a fixed `min-height` or always-open-above rule.** That fixes this one call site by
  accident and breaks whichever call site currently relies on opening downward with room to spare
  (`ux-gate/tooltipPositioning.spec.ts`'s own second test already checks every trigger on one screen -
  rerun it, do not just add a new test and call it done).
- **Reread `Tooltip.tsx`'s own doc comment on why the measurement is synchronous inside
  `useLayoutEffect`, not deferred** - the same subtlety (two separate React commits: `hidden` coming
  off, then `setBubbleStyle` landing) applies identically to whatever new state this item adds; do not
  introduce a second, separately-timed piece of state for the vertical dimension where one combined
  `nextStyle` object (already the existing shape) works.
- **`ux-gate/lib/tooltipOverflow.ts` is a deliberate duplicate of the component's own arithmetic, not an
  import of it** - keep that split; the whole point is that this test never trusts the component to
  grade its own homework.

## Done when

- [x] A tooltip trigger near the bottom of a scrollable ancestor's own bounds opens its bubble upward
      instead of clipping downward, proven by a real Playwright reproduction (fails before, passes
      after) - `Thread`'s own delivery-scope tooltip against a short conversation plus a genuine
      "load older messages" state.
- [x] Every existing tooltip call site the current `ux-gate/tooltipPositioning.spec.ts` already checks
      still reports zero overflow - rerun (66 passed, 0 failed across the full `ux-gate` suite), not
      just left green by omission.
- [x] The asymmetry (no vertical "shrink" analogue to the horizontal `max-width` shrink) is stated in
      code at the exact point it would otherwise be reached for.
