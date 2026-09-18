# 25-141 · A closed launcher shows no unread count

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-18, live, reported by the author, who tested it as if it already existed: opened
  the widget, sent a message, closed it, had an operator send two replies, and expected a small badge
  with "2" on the closed launcher bubble (the same badge shown on the landing page's own launcher
  mockup, referenced when this feature was first requested on 2026-09-17). **This is not a regression
  - the feature was requested that day but its analysis and ticket were never finished before other
  work took over the session.** Confirmed by reading the code: `ago-widget` has no "badge" or "unread"
  concept anywhere in its UI (`grep -r unread src` finds only the unrelated per-conversation
  `lastKnownSequence` reconciliation cursor in `storage.ts`, not an unread count).
- **Depends on**: none. Touches `ago-widget` only.

## Scope (deliberately narrower than the original request - see `25-142` for what this defers)

Covers exactly the scenario the author tested: **while the panel is closed, in the same page load**,
an incoming message increments a small count badge on the launcher button; opening the panel clears
it. It does **not** cover a badge surviving a page reload or a closed-then-reopened browser tab - that
needs knowing how many messages arrived while nothing was running at all, which is a materially
different mechanism (deriving unread count from the reconciliation cursor against the server's latest
sequence, on reconnect) and its own design question, filed separately as `25-142` so this item can
land and be tested today without waiting on that answer.

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
- In-memory for this page load only, matching the scope above. No new `WidgetStorage` key, no
  reconciliation-cursor arithmetic - this is deliberately the simplest version that satisfies what was
  actually tested.

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

- [ ] Sending two operator messages while the panel is closed shows "2" on the closed launcher
- [ ] Opening the panel (either path) clears the count and hides the badge
- [ ] The badge never shows "0" - it is absent, not a visible zero
- [ ] The toggle's accessible name reflects the unread count when nonzero
- [ ] `25-142` is filed (done - see that item) so the reload-persistence question this defers is not
      lost
