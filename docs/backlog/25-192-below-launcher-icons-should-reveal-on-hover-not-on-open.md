# 25-192 · The below-launcher channel icons should reveal on hover, not on open

- **Stage**: 25
- **Status**: done — `ago-widget#114`
- **Found**: 2026-09-21, the author, comparing the below-launcher row's current look (plain
  circular icons) against a reference screenshot of a fuller, more expressive channel-switcher
  card (Jivo-style rows with labels and subtitles). The visual comparison prompted a rethink of
  the display *condition* specifically - not, per this item's own scope, the visual redesign.

## What changes

`25-191` (just shipped) tied the below-launcher row's own visibility to the panel's open/closed
state: hidden while closed, visible while open. The author's own correction, one item later:
that is backwards. The right condition is:

- **Chat closed + hovering the toggle** → the row is visible.
- **Chat closed + not hovering** → hidden.
- **Chat open** → always hidden, regardless of hover.
- **Every time the chat closes** (whether this is the first close or the twentieth), hovering the
  toggle again reveals the row - there is no "seen once" state, no per-identity memory, nothing
  persisted. Purely a function of two live facts: is the panel open, and is the toggle currently
  hovered.

This only touches the "below launcher" placement (`ChannelSwitcherPlacement: "BelowLauncher"`).
The default "above composer" card is unaffected - it keeps `25-149`'s own visibility (a child of
the panel, shown once the panel opens, dismissed only by sending a message per `25-191`).

## Scope

- `ago-widget/src/ui/widget.ts`: `this.toggle` gains `mouseenter`/`mouseleave` (or
  `pointerenter`/`pointerleave` - confirm which fires correctly for a Shadow DOM host in this
  project's own target browser matrix before picking) listeners that track hover state and
  re-evaluate the row's own visibility. `open()`/`close()`/`openForAutoGreeting()` keep calling
  into that same re-evaluation point (25-191's own `setChannelSwitcherLauncherRowVisible`,
  generalised to also consider hover) rather than unconditionally revealing/hiding - closing while
  still hovering must show the row immediately, without a fresh `mouseenter`.
- The row's own initial built state: hidden, regardless of `isOpen` - hover is a live signal this
  method cannot know anything about at build time, unlike `25-191`'s own open/closed snapshot.
- No change to the row's own markup, icons, or the above-composer card.

## Out of scope

- Any visual redesign of the row itself (size, adding text labels/subtitles, a callback-request
  entry) - the reference screenshot that prompted this item is about a different placement/design
  entirely and is not this item's to build.
- Touch/mobile behaviour beyond whatever `mouseenter`/`mouseleave` (or its pointer-event
  equivalent) already does there - hover is inherently a desktop-pointer concept; making this
  reachable on touch, if ever wanted, is a separate item.

## Done when

- [x] The row is hidden on load, before any hover and before the panel is ever opened.
- [x] Hovering the toggle while the chat is closed reveals the row; moving the pointer away hides
      it again.
- [x] Opening the chat hides the row even if the toggle is still hovered at that instant, and it
      stays hidden for as long as the chat is open regardless of hover.
- [x] Closing the chat while still hovering the toggle reveals the row immediately, with no
      further pointer movement required.
- [x] Every existing channel-switcher test still passes, updated in place where it asserted
      `25-191`'s own open-tracks-visible behaviour rather than deleted.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.

## Outcome

Fixed 2026-09-21 (`ago-widget#114`): `pointerenter`/`pointerleave` on `this.toggle` (pointer events,
not mouse events - the same call correctly reaches a touch tap too, though this item's own scope
stays desktop-hover) track `isToggleHovered`; a new `updateChannelSwitcherLauncherVisibility`
requires `!this.isOpen && this.isToggleHovered` and is the one place the row's `hidden` is written,
called from both pointer listeners and from `open()`/`close()`/`openForAutoGreeting()`. Verified
live in a review mockup before landing (a separate optical-centering issue on the toggle's own
icon was found in that same review and filed as `25-193`). `channelSwitcherLauncher.test.ts`
rewritten for the new rule (closed+hover required together, reveals on every close not just the
first, hides immediately on open regardless of hover). `npm run
typecheck`/`lint`/`test`(483/483)/`ux-gate`(16/16) all green.
