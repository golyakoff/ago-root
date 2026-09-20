# 25-191 · The below-launcher channel icons show and hide at the wrong times

- **Stage**: 25
- **Status**: done — `ago-widget#113`
- **Found**: 2026-09-21, the author, live on `golyakov.net` - a screenshot showing the MAX and
  Telegram channel-switcher icons floating beside the closed launcher, always visible.

## What was actually true

Two separate, independent issues, both about *when* the channel switcher shows itself - reported
together and fixed together at the author's own request.

### 1. The below-launcher row ignored the panel's own open/closed state

`25-173`'s own "below launcher" placement (`ChannelSwitcherPlacement: "BelowLauncher"`) built its
row of circular channel icons as a sibling of the toggle button, not a child of the panel -
deliberately, so it could render at the launcher's own height whether the panel was open or
closed. That was the item's own explicit design: a **persistent** row, visible at all times.

The author's own correction: the two placements should differ in *where* the switcher sits, not
in *when* it is visible. A visitor who has not opened the chat should see the plain launcher
alone, exactly as the default "above composer" card placement already behaves - the row should
reveal itself when the dialog opens and hide again when it closes, the identical visibility
lifecycle the card gets for free from being a child of the panel.

### 2. The above-composer card had two independent dismissal triggers doing the same thing

`25-149`'s own card (the default "above composer" placement) is dismissed - permanently, for that
visitor identity - by either of two triggers: clicking the card's own "Написать в чат" row, or
sending the visitor's first message (`dispatchSend`). Both call the identical
`dismissChannelSwitcher()`.

The author's own correction: two conditions read as one doing double duty. The one that should
survive is the visitor actually sending a message - choosing to type instead of picking a channel
is not the same fact as having sent something, and should not by itself make the offer disappear
forever.

## Scope

- `buildChannelSwitcherLauncherRow` (`ago-widget/src/ui/widget.ts`): builds the row already hidden
  or shown to match `this.isOpen` at build time (the session promise it awaits can resolve after an
  auto-greeting has already opened the panel). `open()`/`close()`/`openForAutoGreeting()` each
  reveal/hide it at the identical point they already set `this.panel.hidden` - a new
  `setChannelSwitcherLauncherRowVisible` helper, the one place this row's own `hidden` is ever
  written from here on.
- `ui/styles.ts`: `.ago-channel-switcher-launcher[hidden] { display: none; }` - the class's own
  unconditional `display: flex` would otherwise outrank the attribute, the identical reason
  `.ago-panel[hidden]` already needs its own override.
- The "Написать в чат" row's click handler (`loadChannelSwitcherCard`) no longer calls
  `dismissChannelSwitcher()` - it only focuses the composer now. `dispatchSend` remains the one
  and only caller of `dismissChannelSwitcher`.

## Out of scope

- Any change to the card's own layout, wording, or the channel icons themselves.
- The "Написать в чат" row's own continued existence - it still focuses the composer, just no
  longer dismisses; whether that control still earns its own row given the smaller job it now does
  is a design question for later, not this item's to decide.

## Done when

- [x] The below-launcher row is hidden until the panel opens, and hides again when it closes,
      proven by tests covering both transitions.
- [x] Sending a message no longer affects the below-launcher row's own visibility (it was never
      hidden by sends, before or after this item - stated explicitly rather than left implicit).
- [x] Clicking "Написать в чат" no longer dismisses the above-composer card - only sending a
      message does, proven by an updated test.
- [x] Every existing channel-switcher test still passes, updated in place where it asserted the
      old behaviour rather than deleted.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.

## Outcome

Fixed 2026-09-21 (`ago-widget#113`): both corrections landed together, per the author's own
request to fold them into one ticket. `channelSwitcherLauncher.test.ts` gained two new tests for
the open/close visibility transition and an updated one for the no-permanent-dismiss guarantee;
`channelSwitcher.test.ts`'s own write-in-chat test now asserts the card stays visible after that
click, and its cadence test dismisses via an actual send instead. `npm run
typecheck`/`lint`/`test` (480/480) /`ux-gate` (16/16) all green.
