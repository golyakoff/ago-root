# 25-197 · A touch visitor taps straight into chat, with no channel-routing menu

- **Stage**: 25
- **Status**: done — `ago-widget#116`
- **Found**: 2026-09-21, the author, live on `golyakov.net` (mobile) - a screenshot of the real
  `AboveComposer` card (Max/Telegram rows above the composer, inside the already-open panel) with
  the comment "the buttons are still old, no menu item on tap." Root cause is not a stale deploy -
  it is a feature that was designed in a review mockup (an Artifact, approved live) but never
  actually written into `ago-widget`.

## What is actually true today

Both existing channel-switcher placements assume the visitor can already see the switcher before
deciding what to click:

- `AboveComposer` (`25-149`) only appears *inside the already-open panel*, above the composer - a
  visitor has to open the chat first to see it at all.
- `BelowLauncher` (`25-173`/`25-192`) reveals on **hover** - a concept `(hover: none)` devices
  (essentially every touchscreen phone) cannot produce at all, confirmed directly rather than
  assumed (`window.matchMedia`'s own documented boolean).

Neither placement gives a touch visitor a channel choice *before* committing to open the chat
panel. The reference the author pointed at (Jivo's own mobile behaviour, screenshotted live) does:
tapping the launcher opens a routing sheet first - pick a channel, or "Онлайн чат" to proceed into
the actual widget - with "Отмена"/back returning to the closed launcher, no channel opened, no
chat started.

**This was designed and approved as a live HTML/CSS/JS mockup (an Artifact) during this item's own
review, but the mockup is not the feature** - nothing in `ago-widget`'s own source implements any
part of it. The mockup's own final shape (post-review corrections): no callback-request row (this
product has none), the icon inside the "Онлайн чат" row sized and centred correctly, only the four
real channels this codebase ever produces a link for.

## Scope

- A new interaction mode, gated on `window.matchMedia("(hover: none)").matches` at the moment the
  toggle is clicked - **not** a third `ChannelSwitcherPlacement` value the server chooses, since
  the real gap is device capability, not a tenant preference, and it needs to override *either*
  existing placement identically on a touch device (the `AboveComposer` site this item was found
  on needs the identical fix a `BelowLauncher` site does).
- On that device class, clicking the (still-closed) toggle - when `session.channelLinks` is
  non-empty - shows the routing sheet instead of calling `open()` directly. A site with nothing
  connected still opens straight into chat, unchanged - the same "pays nothing" property both
  existing placements already have.
- The sheet: a question header, one row per connected channel (the real brand icon + name, the
  real URL, opened exactly the way `buildChannelSwitcherRow`/`buildChannelSwitcherLauncherIcon`
  already open one - `target="_blank" rel="noopener noreferrer"`, never a JS-driven navigation),
  an "Онлайн чат" row that calls the real `open()`, and an "Отмена" row (with a back affordance)
  that closes the sheet with no other effect.
- Selecting a channel or "Отмена" simply closes the sheet - it does not need to remember anything
  for next time (no dismissed-forever state, matching the "no persisted memory" instinct
  `25-192`'s own row already established for its sibling placement).
- A device that *does* have hover (the common case this session's own testing environment
  actually has, per `(hover: none)` returning `false` there) is entirely unaffected - both existing
  placements keep behaving exactly as `25-192`/`25-149` already ship them.

## Out of scope

- Any change to `AboveComposer`'s or `BelowLauncher`'s own behaviour on a hover-capable device.
- The mockup's own "banners on top" visual redesign (bigger rows, subtitles) - a separate,
  undecided question, not this item's to build.
- `25-195`'s own open question (Avito) - this item ships with whatever four channels the backend
  already returns, unchanged.

## Done when

- [x] On a `(hover: none)` device, tapping the closed toggle with at least one connected channel
      shows the routing sheet - proven by a real test that fakes the media query.
- [x] Selecting a channel row opens its real URL (`target="_blank" rel="noopener noreferrer"`) and
      closes the sheet without opening the chat panel.
- [x] Selecting "Онлайн чат" opens the chat panel for real (`isOpen` becomes `true`, the panel's
      own `hidden` flips) and closes the sheet.
- [x] Selecting "Отмена" (or its back affordance) closes the sheet with no other effect - the
      panel stays closed, nothing opens.
- [x] A site with no connected channels taps straight into chat on a `(hover: none)` device,
      unchanged from today.
- [x] A hover-capable device is provably unaffected - every existing `channelSwitcher.test.ts`/
      `channelSwitcherLauncher.test.ts` test still passes unchanged.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.

## Outcome

Shipped as `ago-widget#116`, `toggleOpen()` gated on
`window.matchMedia?.("(hover: none)")?.matches ?? false` plus `channelLinks.length > 0`, opening a
new `.ago-touch-routing-sheet` bottom sheet instead of the chat panel on that device class. New
`src/ui/touchRoutingSheet.test.ts` (9 tests, all passing) covers every Done-when line above,
including fails-before/passes-after confirmation on the core gate (temporarily forcing the branch
off made 6/9 fail, the 3 absence-of-sheet tests correctly still passed). `npm run
typecheck`/`lint`/`test` (493/493) and `npm run ux-gate` (16/16) all green. Bundle grew from 37.7 KB
to 38.3 KB gzipped, still under the 46 KB budget.

Verified live in a real browser (Chromium mobile emulation, real built `dist/widget.js`, via
`javascript_tool` DOM assertions since simulated pointer clicks were unreliable under mobile touch
emulation in this tool): `hoverNoneMatches: true`, the sheet lists `["MAX", "VK", "Telegram",
"WhatsApp", "Онлайн чат", "Отмена"]` in the fixed `25-194` order, Telegram's row carries the correct
real `href`/`target="_blank"`/`rel="noopener noreferrer"`, "Отмена" closes the sheet with the chat
panel still closed, and "Онлайн чат" closes the sheet and genuinely opens the chat panel.

Filed and closed together, after-the-fact: the code had already merged before this backlog file was
committed or an issue existed for it, which is itself the process gap rule 14/15 exist to catch -
the author caught it live ("а ты что же это - без тикета даже делаешь?").
