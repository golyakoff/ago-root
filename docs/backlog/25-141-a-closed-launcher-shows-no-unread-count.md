# 25-141 · A closed launcher shows no unread count

- **Stage**: 25
- **Status**: done — `ago-widget#96` (reload persistence split out as `25-143`, per the author's own
  decision on how to build it)
- **Found**: 2026-09-18, live, reported by the author, who tested it as if it already existed: opened
  the widget, sent a message, closed it, had an operator send two replies, and expected a small badge
  with "2" on the closed launcher bubble (the same badge shown on the landing page's own launcher
  mockup, referenced when this feature was first requested on 2026-09-17). **This is not a regression
  - the feature was requested that day but its analysis and ticket were never finished before other
  work took over the session.** Confirmed by reading the code: `ago-widget` has no "badge" or "unread"
  concept anywhere in its UI (`grep -r unread src` finds only the unrelated per-conversation
  `lastKnownSequence` reconciliation cursor in `storage.ts`, not an unread count).
- **Depends on**: none. Touches `ago-widget` only.

## Scope

Covers the scenario the author tested (an incoming message while the panel is closed shows a count on
the launcher, cleared on open) **and** survives a page reload or a closed-then-reopened browser tab,
same browser - confirmed directly by the author (2026-09-18, see `25-142`'s own Outcome) once the
question came up while scoping this item. Cross-device/cross-browser persistence stays out of scope -
not asked for, and would need a server-side "last read" concept rather than anything client-local.

- A count, incremented once per incoming message (`handleIncoming`) with `authorKind !== "Visitor"`
  while `this.isOpen` is `false` - the same "the other side of the conversation" test this file already
  uses in `appendMessageBubble` (`ui/widget.ts:1803`), not narrowed to `Operator` alone: a module step's
  own prompt (`System`) arriving while the panel is closed is just as much something the visitor has
  not read yet.
- Rendered as a small circular badge on `this.toggle` (the launcher button, `ui/widget.ts:407-419`),
  showing the count as long as it is greater than zero, hidden entirely at zero - not a badge showing
  "0".
- Cleared (count reset to zero, badge hidden) the moment the panel opens, by either path: the ordinary
  `open()` and the auto-open reveal `openForAutoGreeting()` - both put the transcript in front of the
  visitor, so both count as "read."
- Persisted via a new `WidgetStorage` key (e.g. `last-read-sequence`, per conversation) - **not** a
  reuse of the existing `lastKnownSequence` cursor, which tracks "received for reconnection" and
  updates the instant a message arrives regardless of whether the panel is open, making it the wrong
  fact for "read." The new cursor advances only when the visitor actually sees the transcript (panel
  opens, either path). On a fresh page load, the initial count comes from comparing this cursor against
  what `connect()`'s own history replay already fetches, rather than a second network round-trip.
  Follows the existing `WIDGET_STORAGE_DISCLOSURE` convention for a new key (see `has-known-contact-
  detail`, added the same way for `25-136`).

## Where this is likely to go wrong

- Don't increment while the panel is open - an incoming message the visitor can already see on screen
  is not unread, regardless of window focus. (Whether *window/tab* focus should matter - a visitor with
  the panel open but the browser tab backgrounded - is out of scope; not requested, not tested.)
- Don't count the visitor's own messages, or the client-only `AutoGreeting` placeholder bubble
  `drawAutoGreeting` draws before its real counterpart arrives (that real counterpart, once it arrives
  via `handleIncoming`, is itself `authorKind === "AutoGreeting"` - decide deliberately whether an
  auto-greeting that materializes while the panel happens to be closed should count; the author's own
  reference screenshot ("как у нас на лендинге") suggests yes, since a visitor who never opened the
  panel at all has unread content the moment any message - including the greeting - exists).
- Keep the badge's own accessible name in sync - the toggle's `aria-label` (`this.strings.openChat`)
  should say how many unread messages exist when the count is nonzero, not leave a sighted-only visual
  badge with no accessible equivalent.

## Done when

- [x] Sending two operator messages while the panel is closed shows "2" on the closed launcher
- [x] Opening the panel (either path) clears the count and hides the badge
- [x] The badge never shows "0" - it is absent, not a visible zero
- [x] The toggle's accessible name reflects the unread count when nonzero
- [~] Reloading the page, or closing and reopening the tab, after unread messages arrived still shows
      the correct count on next load, same browser — **not met here**: doing this without changing
      the widget's lazy-connect timing needs a small new server-side read, split out as `25-143` per
      the author's own decision, so this item's live, same-page-load behavior could land today
- [x] A visitor with no unread messages sees no badge after a reload, same as a fresh visitor (true
      today because the count starts at zero either way - `25-143` is what makes a nonzero case correct)

## Outcome

Landed exactly as scoped for the live, same-page-load case: an in-memory count on `ChatWidget`,
incremented in `handleIncoming` for any non-`Visitor` message while closed, rendered as
`.ago-unread-badge` on the launcher, reset by both `open()` and `openForAutoGreeting()`. New
`openChatWithUnreadCount` locale string (en/ru, with Russian's own count-agreement rule) keeps the
toggle's accessible name in sync. Reload persistence needs a small new server-side read and is split
into `25-143` rather than blocking this item - the architecture question it raised (eager-connect on
every page load vs. a lightweight REST read) was asked directly and answered by the author rather than
guessed at. `ago-widget#96`.
