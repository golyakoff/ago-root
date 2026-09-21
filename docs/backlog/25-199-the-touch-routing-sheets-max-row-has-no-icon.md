# 25-199 · The touch routing sheet's MAX row has no icon

- **Stage**: 25
- **Status**: done — `ago-widget#118`
- **Found**: 2026-09-21, the author, live on `golyakov.net` (mobile), same report as `25-198`: "на
  тапе в меню нет иконки Max" - every other channel row in the routing sheet (`25-197`) shows its
  brand mark; the MAX row does not.

## What is actually true today, and the likely cause

`buildChannelSwitcherRow()` (`ui/widget.ts`) is reused unchanged by both the `AboveComposer` card
and the new touch routing sheet (`25-197`) - it calls `buildBrandIcon(link.kind)` for every row
unconditionally, so nothing in the row-building code itself special-cases MAX or skips its icon.
The `AboveComposer` card renders MAX's icon correctly (confirmed in the author's own earlier
screenshot of that card), so the icon tree itself (`CHANNEL_ICON_TREES.Max`) is not simply broken.

**The one thing that actually is MAX-specific**: `CHANNEL_ICON_TREES.Max` is the *only* brand icon
built from `<defs>` + `<linearGradient>`/`<radialGradient>` elements carrying fixed `id`s (`a`, `b`,
`c`, `d`) referenced via `href="#a"` etc. (`widget.ts` ~L313-383) - every other brand (`Telegram`,
`WhatsApp`, `Vk`) is flat `fill="#hex"` paths with no `id` at all. `loadChannelSwitcherCard()` builds
the `AboveComposer` card - MAX icon included - **the moment the session resolves, regardless of
whether the panel is open** (its own doc comment: "so an auto-opened panel gets it too"), so a
second `buildBrandIcon("Max")` call from the touch sheet, moments later, appends a *second* SVG
carrying the identical `id="a"`/`id="b"`/`id="c"`/`id="d"` into the same shadow root. Two elements
sharing an `id` inside one document (a shadow root is its own `id` scope, but does not stop two
children of it from colliding) is invalid, and which copy's `<defs>` a browser actually resolves
`href="#a"` against is not something either icon's own markup controls - this is a strong
candidate, not yet proven against the live DOM, for why MAX's icon specifically goes missing only in
the second place it is built. Confirm by inspecting the real shadow root before fixing rather than
assuming this is the whole story.

## Scope

- Whatever the confirmed cause turns out to be, `CHANNEL_ICON_TREES.Max`'s row renders its full
  brand mark wherever `buildChannelSwitcherRow`/`buildBrandIcon("Max")` is called - including when
  more than one instance of it exists in the same shadow root at once (the `AboveComposer` card and
  the touch routing sheet, concurrently, is the real case this item exists for). If the `id`
  collision is confirmed, the fix makes each built instance's internal `id`s unique to that instance
  (a per-call suffix is the obvious shape) rather than fixed literals.
- A regression test that builds two MAX rows in the same document and asserts the second one's
  gradient still paints (or, short of a real paint assertion, that its `id`s do not collide) -
  proven failing against today's code before the fix, passing after.

## Out of scope

- `25-198`'s own defect (the card appearing at all on a touch device) - fixing that would make this
  item's own reproduction path (two MAX icons at once) rarer but not impossible (`BelowLauncher` +
  the sheet, or the card on a hover device that later narrows to touch mid-session), so this item
  stands on its own regardless of `25-198`'s outcome.

## Done when

- [x] The real cause is confirmed against a live or test DOM before any fix is written.
- [x] A test proves the MAX icon renders correctly when it is the only instance in the document.
- [x] A test proves the MAX icon renders correctly when a second instance already exists in the same
      document - the actual shape of this bug - fails against today's code, passes after the fix.
- [x] Every other brand icon (`Telegram`/`WhatsApp`/`Vk`) is provably unaffected by the fix.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.

## Outcome

Shipped as `ago-widget#118`. The hypothesis was confirmed exactly: `buildIconTree`/`buildBrandIcon`
now suffix every `id` a tree declares (and every internal `#id` reference) with a per-call instance
counter, so two `buildBrandIcon("Max")` calls landing in the same shadow root never collide.
Telegram/WhatsApp/Vk declare no `id` anywhere in their own trees, so their output is unaffected.

New coverage in `channelSwitcherMaxIcon.test.ts` confirms the collision directly against the built
DOM before the fix (8 id-bearing elements, only 4 distinct values), then proves it resolved.

**A real merge-order defect was caught during landing, not before.** The test's own "two instances"
scenario originally relied on `25-198`'s soon-to-be-removed `AboveComposer`-card-plus-touch-sheet
coexistence - landing both items in either order would have left `npm test` red on whichever file
the other did not touch (confirmed with a real `git merge-tree` + a throwaway worktree before
either PR was pushed, not a guess). Sent back to the same background worker rather than patched
inline, per the author's own instruction that this class of fix goes through a worker with its own
verification; the corrected test reconstructs "card already built, then sheet also built" via a
device whose `matchMedia("(hover: none)")` answer changes between mount and the visitor's tap - a
real, still-live case (`25-199`'s own "Out of scope" line already named it as surviving `25-198`) -
and scopes every row lookup to its own container so the two can never again collapse onto one
element by accident. Re-verified independently by the managing session on the real, already-rebased
`origin/main` tip (which now includes `25-198`): `npm run typecheck`/`lint` clean, `npm test`
500/500, `npm run ux-gate` 16/16.
