# 25-223 · The channel-launcher's "bubble in" stagger plays far-to-near, not near-to-far

- **Stage**: 25
- **Status**: done — merged as `ago-widget#134`. The worker's live reproduction found the geometry check
  in this file was right and the author's own report was half-right: only `.ago-position-left` was
  actually backwards. Verified against real code: `isPositionLeft ? index : icons.length - 1 - index` —
  position-aware, not a single unconditional formula.
- **Found**: 2026-09-22, live, by the author, immediately after `25-222` shipped: on hovering the
  widget's toggle button, the round channel icons bubble in **farthest-from-the-toggle first, nearest
  last** — backwards from what `25-222` asked for ("appearing as bubbles starting from the one nearest
  to the round button"). The author confirmed this is wrong **for both widget positions** — the default
  (toggle bottom-right, `.ago-root` with no modifier class) and the mirrored one
  (`.ago-root.ago-position-left`) — and specified the fix must count "only among the visible buttons."

## What this investigation found, and the contradiction in it — resolve this empirically, not by trusting either side blindly

`25-222`'s own implementation (`updateChannelSwitcherLauncherVisibility`, `ui/widget.ts`) computes each
icon's stagger delay as `icons.length - 1 - index`, where `icons` is
`querySelectorAll(".ago-channel-switcher-launcher-icon")` in DOM order — built on the stated assumption
that **the row's last DOM child sits nearest the toggle**, reasoned from `.ago-channel-switcher-
launcher`'s own CSS (`right: calc(100% + gap)` for the default position, an ordinary left-to-right flex
row).

**A live geometry check this session (real `styles.css`, a real shadow root, `getBoundingClientRect`
on both variants) confirms half of that reasoning and contradicts the rest**:

- Default position (no `.ago-position-left`): confirmed — the **last** DOM child measures nearest the
  toggle, the **first** measures farthest. `25-222`'s formula (`length - 1 - index`, last child gets
  the smallest delay) should therefore already play nearest-first *for this position* — yet the author
  reports the opposite, live, in a real browser.
- `.ago-position-left`: the measurement flips — the **first** DOM child measures nearest, the **last**
  farthest. `25-222`'s formula is unconditional (no `.ago-position-left` branch at all), so it plays the
  **first** child (actually nearest) with the **largest** delay — genuinely backwards for this position,
  consistent with the report.

**The contradiction on the default position is the real puzzle here**, and this investigation could not
resolve it from static geometry and reading source alone — something about the *live, animated* reveal
(timing, event ordering, a stale measurement, or a wrong assumption about which element the author was
actually watching) disagrees with what a pure `getBoundingClientRect` snapshot shows. Do not implement a
fix by trusting either the geometry check above or the original `25-222` reasoning at face value —
**reproduce the actual bug live** (a real widget instance, hover the toggle, watch or capture the
animation order with your own eyes or an instrumented test that reads `getAnimations()`/`animationDelay`
against real element positions at the moment the animation actually starts) for **both** positions
before writing the fix, and say plainly what you found and why the static check above was or wasn't
telling the whole story.

## "Only among the visible buttons"

Read carefully before assuming what this means: today, `buildChannelSwitcherLauncherRow` builds exactly
one icon per entry in `session.channelLinks`, with **no truncation or overflow mechanism** — every built
icon is a visible icon (confirmed: no "max icon count" feature exists anywhere in this codebase;
`channelSwitcherMaxIcon.test.ts`'s own name refers to the **Max** messenger brand's icon, unrelated).
If your own reading of the current code confirms this — every icon `buildChannelSwitcherLauncherRow`
appends is always visible, none hidden — then this phrase is the author being precise/defensive rather
than pointing at a real, separate mechanism, and the fix only needs to get the order right among
whatever icons exist. If you find a real hidden-icon case this description missed, say so and handle it
explicitly instead.

## Scope

- Fix the stagger direction so the animation plays **nearest-to-farthest from the toggle, first-to-last
  in time**, correctly for **both** `.ago-root` (default) and `.ago-root.ago-position-left` — derive
  "nearest" from real, position-aware geometry (or the DOM-order rule proven correct by your own live
  reproduction above), not a single unconditional formula assumed to generalise.
- A real, live-reproducing test (or the closest equivalent this project's jsdom-based suite can express)
  that would have caught this — `channelSwitcherLauncher.test.ts` already has two tests from `25-222`
  asserting `animationDelay` values by DOM index; if those tests are passing today while the live bug
  exists, that is itself a finding worth reporting (the test may be asserting the wrong thing, or
  passing against an assumption the real browser doesn't share) — fix or replace them so they actually
  prove the right thing for both positions.

## Out of scope

- The slide-up entrance for `.ago-panel`/`.ago-channel-switcher-banner` (`25-222`'s other half) —
  unaffected, not reported as wrong.
- Any real max-icon-count/truncation feature — not asked for, and not confirmed to exist.

## Done when

- [x] Live reproduction performed (real browser, real shadow root) — found only `.ago-position-left`
      was actually backwards; the default position's own static geometry check was correct.
- [x] The round channel icons bubble in nearest-to-farthest in both widget positions
      (`isPositionLeft ? index : icons.length - 1 - index`).
- [x] Tests rewritten to prove the right thing for both positions.
- [x] `npm run typecheck`, `npm run lint`, and the full `vitest` suite green.
