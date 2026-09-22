# 25-222 · Panel, banner and channel icons animate in instead of merely appearing

- **Stage**: 25
- **Status**: done — `ago-widget#<PR>`
- **Found**: 2026-09-22. The author asked for real entrance animations instead of plain
  appear/disappear: the chat panel and the channel-switcher banner should slide up from the bottom,
  and the channel-launcher's round icons should "bubble" in, starting from the one nearest the round
  toggle button and cascading outward. Speed and style were rehearsed live in an Artifact built
  against the widget's own real geometry and colours before writing any of this.

## Chosen values, from the rehearsal

- **Panel / banner slide-up**: `500ms`, `cubic-bezier(.34, 1.56, .64, 1)` (a slight overshoot).
- **Channel-icon bubble-in**: `250ms` per icon, the same `cubic-bezier(.34, 1.56, .64, 1)`, staggered
  `50ms` apart, counting outward from the icon nearest the toggle.

## What is actually true today, and why this needed more than a CSS rule

`.ago-panel`/`.ago-channel-switcher-banner` open by clearing the `hidden` attribute
(`display: none` → `display: flex`) — a boundary a `transition` cannot animate across, since there is
no "from" state on the visible side of it. A `transition: opacity/transform` rule already sat on
`.ago-panel` for this reason and had been dead code for as long as it existed: nothing anywhere ever
changed those properties on the element itself, only `hidden` (confirmed by reading every write to
`.hidden`/`.opacity`/`.style.transform` touching either element). The real mechanism has to be a CSS
`@keyframes` animation, triggered by JS adding a class the instant `hidden` is cleared — replayed on
every open, not merely present once.

## Scope

- **`ui/styles.css`**: two new `@keyframes` (`ago-slide-up`, `ago-bubble-in`), both inside the
  existing `prefers-reduced-motion: no-preference` media block alongside `ago-attract`, and two new
  modifier-class rules (`.ago-panel.ago-entering`/`.ago-channel-switcher-banner.ago-entering`,
  `.ago-channel-switcher-launcher-icon.ago-entering`). The old, inert `.ago-panel { transition: ... }`
  rule is removed rather than left beside the real mechanism.
- **`ui/widget.ts`**: a new `triggerEnterAnimation(el, delayMs)` private method — removes
  `.ago-entering`, sets `animationDelay`, forces a reflow, re-adds the class, so a second open genuinely
  replays the animation rather than relying on a class that was never removed. Guarded by the identical
  `matchMedia("(prefers-reduced-motion: reduce)")` double-check `scheduleAttractAttention` already
  uses for the same media feature.
  - Called on both `this.panel.hidden = false` call sites (`open()`, `openForAutoGreeting()`).
  - Called from `updateChannelSwitcherLauncherVisibility` — the one place both the banner's and the
    launcher row's own `hidden` are ever written — exactly when either transitions from hidden to
    visible (never on a call that changes nothing, and never on the transition to hidden).
  - The launcher row's own icons each get a per-icon `animation-delay`, computed from their position:
    the row's own CSS (`right: calc(100% + gap)`, an ordinary left-to-right flex row) puts the *last*
    DOM child nearest the toggle, not the first — confirmed by reading the CSS rather than assumed —
    so the stagger counts down from the end.

## Out of scope

- Exit/close animations — not asked for; only entrance.
- The touch-routing sheet and its own rows — a different, non-hover surface this item does not touch.

## Done when

- [x] Opening the panel (both the manual open and the auto-greeting self-open) plays the slide-up
      entrance.
- [x] The channel-switcher banner plays the identical slide-up entrance when it reveals on hover.
- [x] The channel-launcher's round icons bubble in on reveal, the one nearest the toggle first, each
      `50ms` after the one before it.
- [x] `prefers-reduced-motion: reduce` skips every one of the above — proven by a real test per
      surface, not by inspection of the CSS alone.
- [x] `npm run typecheck`, `npm run lint`, and the full `vitest` suite green (572/572, six new tests).
