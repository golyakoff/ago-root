# 26-127 · [android + mockup] Sticky, shrinking current-month header over the day strip

- **Stage**: 26 — visual polish for Записи→Утверждены (and the mockup Artifact).
- **Status**: done — sticky, shrinking month header shipped (ago-android#128); mockup updated
  (ago-android-design bca6e08).
- **Found**: 2026-09-25.

## The interaction

The current month label over the horizontal day strip should be **sticky at the left edge** while that
month's day chips are still (partly) in view — it does not scroll away with the chips. As the user scrolls
left and the **next** month's chips emerge from the right and begin to overlap the current sticky label,
the current label **shrinks** (truncates) until the next month fully overtakes it and itself becomes the
new sticky label in that position. Scroll further and the pattern repeats with the month after. (Same idea
as an index-sticky section header, but horizontal, with a shrink-on-collision handoff between adjacent
months.)

## Scope
- Implement the sticky + shrink-on-collision + handoff over the existing day-strip month labels
  (`26-117`'s `monthLabelSpanWidth` grouping is the starting point) in `ConfirmedBookingsScreen.kt`.
- Keep the muted sub-label style; no OEM/other concerns.
- Reflect the behaviour in the mockup Artifact (at least statically illustrate the sticky + shrinking
  state) so it is the recorded target.

## Done when
- [x] The current month is sticky-left while its days are in view; the next month emerging on the right
      shrinks the current until it hands off and becomes sticky; repeats both directions. — ago-android#128
      (778f98c).
- [x] `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green; counts reported. —
      landed via ago-android#128 through the CI gate.
- [x] Mockup Artifact updated to show the sticky/shrinking state. — ago-android-design bca6e08,
      "illustrate the sticky, shrinking month header on booking.html".
