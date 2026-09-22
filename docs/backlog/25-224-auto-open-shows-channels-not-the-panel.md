# 25-224 · "Раскрывать виджет автоматически" invites a channel choice, not the chat panel

- **Stage**: 25
- **Status**: done — merged as `ago-widget#135`. Verified against real code: `openForAutoGreeting`
  renamed `triggerAutoOpen`, sets a new separate `autoRevealed` flag rather than faking a hover;
  `updateChannelSwitcherLauncherVisibility`'s `hidden` expression is exactly
  `this.isOpen || !(this.isHoverRegionActive || this.autoRevealed)`; a real `pointerenter` clears
  `autoRevealed` (graduating the reveal into ordinary hover dismissal).
- **Found**: 2026-09-22. The author's own words: *"надо поменять смысл настройки 'Раскрывать виджет
  автоматически' - теперь у нас должно автоматические показываться не окно диалога - а каналы для
  выбора - где общаемся."* Auto-open must reveal the channel picker (whichever placement the site is
  configured for — Console → "Каналы" → "Виджет на сайте" → "Каналы" → "Показывать каналы": "Круглые
  значки под окном диалога" or "Баннеры над окном диалога") instead of opening the full chat panel.

## What is actually true today, confirmed against real code

`scheduleAutoOpen`/`openForAutoGreeting` (`ui/widget.ts`) currently: wait `widgetAutoOpenDelaySeconds`,
then (gated on not-already-shown, not-a-touch-device, not-already-open) reveal `.ago-panel`, draw
`widgetAutoOpenGreetingText` inside it as the first message, and enable the composer without connecting
the hub. This is the behaviour the author is asking to replace.

The channel-switcher's own reveal (`updateChannelSwitcherLauncherVisibility`) is a **separate**
mechanism today, driven entirely by hover: `hidden = this.isOpen || !this.isHoverRegionActive`, where
`isHoverRegionActive` is written only by real `pointerenter`/`pointerleave` events on the toggle or the
row/banner itself (`enterHoverRegion`/`scheduleHoverRegionLeave`, `25-203`). Nothing today can reveal it
except a real hover.

**A real ordering hazard, found while reading this, that the fix has to handle correctly**:
`loadChannelSwitcher()` (which builds `channelSwitcherLauncherRow`/`channelSwitcherBanner`) is invoked
fire-and-forget (`guardAsync(() => this.loadChannelSwitcher())`), not awaited, from the same place
`scheduleAutoOpen` is called. The auto-open timer and the channel-switcher build are two independent
async chains off the same handshake resolution — there is no guarantee the channel-switcher already
exists by the time the auto-open timer could theoretically fire. Confirm this is actually reachable
(read `widgetAutoOpenDelaySeconds`'s real minimum/default against how long `loadChannelSwitcher`
realistically takes to resolve) and handle it explicitly rather than assuming it never happens.

## The proposed shape — implement this unless you find a real problem, and say why

1. **`openForAutoGreeting` (rename it if a clearer name serves better — your call, but say what you
   chose and why) no longer opens `.ago-panel`.** Instead, once its existing gates pass (not shown yet,
   not touch, not already open), it reveals whichever channel-switcher element this site actually built
   — `channelSwitcherLauncherRow` or `channelSwitcherBanner` — using the identical reveal mechanism
   `updateChannelSwitcherLauncherVisibility` already uses (so it gets the same `25-222` entrance
   animation for free), driven by a **new, separate flag** rather than by faking a real hover:

   ```ts
   private autoRevealed = false;
   ```

   `updateChannelSwitcherLauncherVisibility`'s own `hidden` expression becomes
   `this.isOpen || !(this.isHoverRegionActive || this.autoRevealed)` — a second, deliberately separate
   reason to be visible, the same "second flag, not a repurposed one" shape this codebase already uses
   for `RoutingSuppressedAt` vs `IsBlocked` on the backend (do not set `isHoverRegionActive = true` to
   fake this — a real hover and an automatic reveal are different facts, and conflating them would make
   a later hover-driven code path (the grace-period leave timer, `25-203`) reason about a state it did
   not actually observe).

2. **Dismissal — proposed default, not fully decided; implement this unless it's genuinely wrong**:
   `autoRevealed` stays `true` (keeping the channel-switcher visible) until one of: the visitor opens
   the panel for real (`this.isOpen` already wins unconditionally in the `hidden` expression, so no
   extra code needed there); the visitor clicks a channel link (navigates away — moot, nothing to
   dismiss); or the visitor genuinely hovers the toggle/row/banner for real and then leaves it (a real
   `pointerenter` followed by the existing grace-period `pointerleave` handling) — at that point, clear
   `autoRevealed` alongside whatever already clears `isHoverRegionActive`, so a real interaction
   "graduates" the reveal into ordinary hover behaviour and its later dismissal works exactly like any
   other hover-triggered one. No new timer, no auto-hide-after-N-seconds — the visitor gets an
   unhurried, indefinite window until they either act on it or genuinely interact with it and then move
   away.

3. **A site with no channel-switcher built at all (no `channelLinks`, or the handshake resolves to
   neither placement) — proposed default**: auto-open **falls back to the old behaviour** (open the
   panel, draw `widgetAutoOpenGreetingText`) rather than doing nothing. The whole point of auto-open is
   inviting the visitor into a conversation; a shop with nothing else to offer should still get that
   invitation, just through the one channel it actually has (the embedded chat itself).

4. **The ordering hazard from above**: if the auto-open timer fires before `loadChannelSwitcher()` has
   finished (`channelSwitcherLauncherRow`/`channelSwitcherBanner` both still `null`), decide and
   implement a real handling — e.g. treat it identically to "no channel-switcher configured" (fall back
   to the panel, per point 3) rather than silently doing nothing, unless you find the race is
   provably unreachable in practice (state the reasoning either way).

5. **`widgetAutoOpenGreetingText`'s remaining role**: still used by the fallback path (point 3); no
   longer materialises anywhere when a channel-switcher exists and gets shown instead. State this
   plainly in your report — it is a real, user-facing consequence of this change (a tenant who
   configured a greeting text *and* connected channels will stop seeing that text on auto-open) worth
   the author's own awareness even though it is not this item's place to redesign the settings screen
   around it.

## Out of scope

- Any change to the Console's own settings screen or field labels/descriptions for "Раскрывать виджет
  автоматически"/the greeting text field — this item changes what the feature *does*, not how it is
  configured or described in the UI (a follow-up item if the description text needs to change to match).
- The channel-switcher's own placement/config (`widgetChannelSwitcherPlacement`) — read, never changed.
- `25-223`'s own bug (the bubble-stagger order) — a different item; this one only needs the reveal to
  happen, not to re-verify its animation direction.

## Verify for real

- The existing `describe("the widget auto-open panel", ...)` block in `widget.test.ts` (roughly 15
  tests) currently asserts the old panel-opening behaviour throughout — rewrite it to assert the new
  one: the channel-switcher reveals (for a site with one configured), the panel does not open, the
  fallback path still opens the panel (for a site with no channel-switcher), and the existing one-shot/
  touch-device/already-open gates still hold under the new reveal target.
- A real test for the ordering hazard (point 4) — construct the race deliberately (a handshake stub that
  resolves the channel-switcher build after the auto-open delay) and assert the chosen fallback
  actually happens, not merely reasoned about.
- `npm run typecheck`, `npm run lint`, and the full `vitest` suite green.

## Done when

- [x] Auto-open reveals the configured channel-switcher instead of the chat panel, for a site that
      has one (`triggerAutoOpen`, confirmed against real code).
- [x] A site with no channel-switcher still gets the old panel-opening fallback.
- [x] The reveal uses a new, separate `autoRevealed` flag, not a faked hover state; a real subsequent
      hover clears it and takes over dismissal.
- [x] The ordering hazard is handled.
- [x] The auto-open test suite was rewritten.
- [x] `npm run typecheck`, `npm run lint`, and the full `vitest` suite green.
