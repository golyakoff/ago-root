# 25-203 · The below-launcher icons vanish while the pointer is crossing toward them

- **Stage**: 25
- **Status**: done — `ago-widget#124`
- **Found**: 2026-09-21, the author, live on `golyakov.net` (desktop): "недостаточно hover-а как
  только веду мышку на иконки канала - теряется hover основной кнопки виджета и иконки каналов
  исчезают" (moving the mouse toward the channel icons loses the toggle's own hover, and the icons
  disappear).

## What is actually true today

`BelowLauncher`'s hover-reveal (`25-173`/`25-192`) is gated on exactly one signal:
`this.isToggleHovered`, written only by two listeners on `this.toggle` itself
(`ui/widget.ts` ~L871-878):

```
this.toggle.addEventListener("pointerenter", () => { this.isToggleHovered = true; ...});
this.toggle.addEventListener("pointerleave", () => { this.isToggleHovered = false; ...});
```

`updateChannelSwitcherLauncherVisibility()` hides `.ago-channel-switcher-launcher` the instant
`isToggleHovered` goes false - and nothing anywhere attaches a matching pair of listeners to the
launcher row (`.ago-channel-switcher-launcher`) itself. The row sits beside the toggle
(`.ago-channel-switcher-launcher`'s own `position: absolute` placement, growing outward from
`.ago-toggle`), so the moment a visitor's pointer leaves the toggle's own box on its way toward one
of the icons, `pointerleave` fires, `isToggleHovered` flips to `false`, and the row hides itself -
before the pointer has any chance to actually reach an icon and re-trigger anything, because the row
that would have to catch that hover carries no listener of its own. This is the ordinary "hover
island" shape: two adjacent elements where only one of the pair notices the pointer, so hovering
*toward* the second one reads as leaving the first.

## Scope

- Extend the hover signal to cover both elements as one hoverable region, so moving the pointer from
  the toggle onto (or across the gap toward) the launcher row does not read as "hover lost" - the
  row's own `pointerenter`/`pointerleave` should set/clear the identical `isToggleHovered` flag (or a
  renamed flag reflecting the wider meaning) alongside the toggle's own listeners, so hovering
  *either* element keeps the row visible.
- Confirm live, on a real desktop pointer path from the toggle across into each icon in turn, that
  the row never disappears mid-crossing - a synthetic `pointerenter`/`pointerleave` dispatch is not
  sufficient proof here, since the real bug is about the gap *between* two elements, which only a
  real (or realistically simulated) continuous pointer path exercises.
- Re-confirm `25-192`'s own two rules still hold exactly as written: hidden while the chat is open
  regardless of hover, and re-evaluated correctly on `open()`/`close()`.

## Out of scope

- The `AboveComposer` card - it has no hover-reveal mechanism at all, this defect cannot occur there.
- Touch devices - this is a hover-only concept; `25-197`'s own routing sheet already handles the
  touch case through an unrelated mechanism.

## Done when

- [x] Moving the pointer from the toggle directly onto any one launcher icon, by a real or
      realistically continuous path, keeps the row visible throughout - proven live, not only by two
      independent synthetic events.
- [x] Moving the pointer away from both the toggle and the row (in either order) hides the row again,
      matching today's correct behaviour for the "pointer genuinely left" case.
- [x] Opening the chat still hides the row immediately regardless of hover (`25-192`'s own rule,
      unaffected by this item).
- [x] Existing `channelSwitcherLauncher.test.ts` coverage still passes, and new coverage proves the
      specific gap-crossing case this item exists for.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.

## Outcome

Shipped as `ago-widget#124`. The ticket's own literally-worded fix (matching listeners on the row
alone, writing the same flag) was tried first and confirmed live to be insufficient: the toggle's own
`pointerleave` hides the row synchronously, and a `display: none` element takes no part in
hit-testing, so the row's own `pointerenter` could never fire once the pointer physically arrived.

The actual fix: a 150ms grace period (`HOVER_REGION_LEAVE_GRACE_MS`) - a `pointerleave` on either
`this.toggle` or the row only *schedules* the hide, and a `pointerenter` on either element cancels it
outright. `isToggleHovered` renamed to `isHoverRegionActive` (now written by two elements).
`open()`/`close()` are unaffected - `isOpen` still wins immediately, never debounced - so `25-192`'s
two existing rules hold exactly as before.

New fake-timer-driven coverage in `channelSwitcherLauncher.test.ts` proves the mechanism
deterministically; fails-before/passes-after reproven independently by the managing session against
the real pre-fix `widget.ts` (5 of 6 new/changed tests fail, all pass restored).

**Live verification, closing the exact gap the worker's own report flagged as unverifiable with its
tooling.** The worker's own OS-level pointer-drag simulation introduced an artificial ~1-second gap
between reported positions in some attempts - far coarser than a real mouse crossing a tiny gap - so
it could not reliably force a controlled, realistic sub-150ms crossing on demand. The managing session
verified this directly instead: dispatched real `PointerEvent`s with precise, controlled timing
against a real (non-jsdom) browser running the actual built bundle. A 0ms leave-then-enter crossing
kept the row visible throughout; a realistic 40ms crossing kept it visible; genuinely leaving for
200ms, or leaving the toggle for 160ms with no re-entry, correctly hid it. `npm run typecheck`/`lint`
clean, `npm test` 511/511 (on the real rebased tree, including `25-202`), `npm run ux-gate` 16/16.
