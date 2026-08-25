# The operator workspace: a screen someone can work a shift in

- **Stage**: 11 (added 2026-08-24 with `11-05`, when the stage was widened to cover both surfaces)
- **Status**: done — implemented, then verified live as a real signed-in operator, including the
  reconnect and the blocked send. One sub-check (a two-way exchange in a *newly assigned*
  conversation) is blocked by `6-09` and accumulated local test data rather than by anything in this
  item; see the last Done-when entry.
- **Depends on**: `11-05-console-design-foundation.md` — this item lays out and rebuilds the working
  screen out of that item's components and tokens; doing it first would mean designing the layout twice

## Goal

An operator handling several conversations at once can see what needs attention, answer without
losing their place, and tell at a glance which visitor has been waiting longest — in one screen rather
than by navigating between a list page and a conversation page. Today the queue is two `<h2>` lists
and each conversation is a separate full-page route whose thread renders as
`[{sequence}] {authorKind}: {body}` in a `<ul>`, with no timestamps at all and a single-line `<input>`
as the composer.

## Context to read first

`ago-console/src/pages/QueuePage.tsx` in full — especially its doc comment on the two different
freshness guarantees (assigned-to-me is live via `onConversationAssigned`; waiting is a 15-second
poll, deliberately) and on why there is no claim button: `4-02`'s engine is the only thing that moves
a conversation between the lists, so a clickable waiting row would have nothing correct to do. Both
decisions survive this item unchanged, and the redesign must not quietly imply otherwise.
`ago-console/src/pages/ConversationPage.tsx` — the thread, the attachment flow (`5-08`), the
failed-send retry path, and `loadOlderHistory`'s keyset paging. `docs/conventions/date-and-time.md` —
the rendering rule this item finally has to apply properly: render in the user's IANA zone when
supplied, otherwise UTC *labelled as UTC*, and never order by a clock. The queue currently renders
`toLocaleTimeString()` with no date at all, so a conversation waiting since yesterday looks minutes
old. `ago-console/src/realtime/protocol/*` and `docs/backlog/3-03-reconnect-resume-protocol.md` — the
connection states this item has to show honestly. `docs/architecture/realtime.md`'s degradation path —
what "degraded" actually means, so the indicator does not invent states the system does not have.

## Scope

- **A three-region layout**: the conversation list (assigned to me, and waiting), the active thread,
  and a visitor context panel. `/conversations/:id` stays a real route so a conversation is still
  linkable and reloadable — the layout changes, the routing contract does not.
- **A thread that reads as a conversation**: visually distinguished sides, consecutive messages from
  the same author grouped, a timestamp per message and a day separator, per `date-and-time.md`. The
  raw `[sequence]` prefix leaves the visible text — keep it available where it helps debugging (a
  `title`, or a dev-only affordance), because it is genuinely useful and genuinely not for operators.
- **A real composer**: multiline, Enter sends and Shift+Enter inserts a newline, send disabled while
  empty, and the attachment flow folded into it — drag-and-drop and paste alongside the existing file
  input, upload progress and the pending attachment shown in the composer rather than in a separate
  block above the form. `5-08`'s upload/confirm/delete behaviour is reused as-is, not reimplemented.
- **Attention and unread**: real unread badges in the list (the data already exists as
  `operatorUnreadCount`), an unread count in the document title so a backgrounded tab still tells the
  truth, and one explicitly chosen, explicitly stated behaviour for how a newly assigned conversation
  announces itself. Whatever is chosen is named in the item's own write-up — a silent arrival and a
  deliberate one are both defensible, an accidental one is not.
- **Waiting time, not arrival time**: how long each conversation has been waiting, oldest first, with
  assigned and waiting visually distinct. The read-only nature of the waiting list stays, and the
  layout must make that legible rather than making rows look clickable.
- **A visitor context panel built from what actually exists today**: visitor identifier, online/offline
  presence, when the conversation started, which site. That is thin, and this item says so plainly
  instead of padding it — anything more (visitor's page URL, referrer, prior conversations) is a
  backend change and belongs in its own item, not invented here.
- **A connection indicator** with the states the protocol really has, including reconnecting and
  degraded, replacing `Operator hub: {connectionState}` printed as text.
- **A responsive floor**: correct on a laptop screen, degrading to a single column when narrow. Not a
  mobile app, and not a tablet-first layout.
- **Verified live with two browsers**, holding real conversations through the redesigned screen — the
  same bar `5-07` set for itself, and the only way any of the above is actually proven.

## Out of scope

Everything below is real operator-productivity work for a commercial support product, and none of it
belongs in a stage about appearance. Named here so it is not lost, and so this item does not quietly
grow into all of it: canned responses and macros, search across conversations, transferring a
conversation to another operator, internal notes and tags, a keyboard-shortcut system beyond
Enter/Shift+Enter/Escape, desktop notifications and sound, and interface i18n. These want a stage of
their own in `roadmap.md`'s reserved 16-19 range, scoped when they are actually next rather than now.

Also out of scope:
- Changing the assignment model — no claim button, no manual pull from the waiting list (`4-02`,
  `QueuePage`'s own doc comment). Wanting one is a product decision, not a layout consequence.
- Broadcasting "a new conversation started waiting" to every operator of a site. Nothing publishes it
  today, and the 15-second poll is a stated, deliberate limitation; replacing it is a backend item.
- The admin/supervisor view (`5-08`) beyond what `11-05`'s retrofit already gives it.
- Any change to the widget's own conversation UI.

## Done when

- [x] The three-region layout works, and `/conversations/:id` still loads a conversation directly.
      `WorkspaceLayout` is a layout route holding the conversation list; `ConversationPage` and
      `NoConversationSelected` fill the other two regions through its `<Outlet />`. The routing
      contract is unchanged.
- [x] The thread shows grouped, side-distinguished messages with timestamps and day separators
      following `date-and-time.md`, and no `[sequence]` prefix in the visible text - it moved to each
      bubble's `title` and to a dev-build-only chip. `threadModel.ts` (grouping, day boundaries in the
      rendering zone, ordering by `sequence`) and `time/format.ts` are unit-tested, including across a
      real spring-forward in Europe/Berlin.
- [x] The composer is multiline with Enter/Shift+Enter (and Escape to clear), and attachments are
      sent from within it, including by drag-and-drop and paste. `5-08`'s create -> presigned PUT ->
      confirm sequence is called, not reimplemented. `Textarea` - one of `adr/0030`'s eleven, shipped
      unused - is its consumer at last.
- [x] Unread counts appear in the list and in the document title; the new-assignment behaviour is
      implemented and stated (below).
- [x] The list shows elapsed waiting time, ordered oldest first, with waiting rows legibly read-only
      (an `<li>` with no anchor, no hover response, a dashed sunken surface).
- [x] The connection indicator shows reconnecting and degraded states honestly - "degraded" being the
      server's own `"Reconnect"` drain hint, which `5-07` wired up and nothing consumed until now.
- [x] The layout holds on a laptop screen and collapses to one column when narrow. Measured in a
      browser at 1280px (three columns), 1100px (two, with the visitor panel as a strip) and 700px
      (one, rail hidden, back link shown, no horizontal scroll at any width).
- [x] **Proven live against the local cluster, signed in as a real operator, including a reconnect
      and a blocked send.** The implementing session could not do this (the console is behind a
      Keycloak password form and it was not permitted to enter credentials) and said so rather than
      claiming it; the managing session then ran it as `demo-operator` against the compose stack with
      the API and Worker running. Actually observed:
      - The workspace loaded with **50 real assigned conversations**, the hub badge reading `Live`,
        unread badges rendering per row (`2 unread messages`, `1 unread message`), elapsed time
        rendering as `Open 2d 17h` / `Open 1d 18h` — the defect this item set out to fix (a bare
        `toLocaleTimeString()` making a day-old conversation look minutes old) is genuinely gone.
      - The document title carried the unread count as `(195) AGO Chat operator console`.
      - **Reconnect**: killing the API mid-session moved the badge to `Reconnecting` with an honest
        explanation ("The connection dropped and is being retried with backoff…"), and an open
        conversation replaced its thread with "Waiting for the operator hub before this thread can
        load or send." rather than rendering an empty or stale thread.
      - **Blocked send**: in that state `Send` was `disabled` while the composer stayed usable and
        kept its `Enter to send, Shift+Enter for a new line` hint — the send path refuses rather than
        failing silently.
      - Restarting the API and reloading returned the badge to `Live` with all 50 conversations. Note
        the automatic reconnect had by then exhausted its own retry window (`3-03`'s backoff policy —
        the API was down about two minutes), which is exactly the case the indicator's own copy
        already tells the operator to reload for. Not a defect in this item.
      - A real visitor message sent from the widget demo reached Postgres with
        `operator_unread_count = 1`, so the widget → API → outbox → Worker path was genuinely live
        throughout.
      **One check genuinely not completed**: a two-way exchange in a *newly assigned* conversation.
      The local database has 60 conversations stuck in `Waiting` and both seeded operators sitting at
      `active_chats = capacity`, so the assignment engine correctly refuses to assign anything new —
      that is [`6-09`](6-09-release-operator-capacity-on-close.md) (capacity is never released on
      close), a known open defect unrelated to this item, plus accumulated test data. Resetting
      `active_chats` by hand did not help, since the engine takes the oldest waiting conversation
      first and this one was newest of sixty. Worth redoing once `6-09` lands against a clean database.

## How a new assignment announces itself

The item's one discretionary choice, decided as: **announced in place, never acted on for the
operator.** When `4-02`'s engine assigns a conversation while the console is open, the row appears in
"Assigned to me" carrying a `New` badge that persists until it is opened, the unread count and the
document title go up, and a polite live region says so once and retires itself after twenty seconds.
Nothing else happens - the open conversation stays open, focus stays where it was, and the draft in
the composer is untouched.

Auto-opening the new conversation was rejected because an operator mid-sentence to one visitor would
be teleported to another, losing their place in exactly the way this item exists to prevent. A wholly
silent arrival was rejected because an assignment nobody notices is a visitor waiting on an operator
who does not know they exist. The system decides *who* and the operator decides *when*.

## What this item found, and handed to a backend item — now closed

**`operatorUnreadCount` was monotonic - nothing in `ago-chat` ever cleared it.**
`Conversation.IncrementUnreadCount` (`2-05`) only incremented, and there was no mark-read command,
endpoint or handler anywhere. A badge built from that field alone would never have gone away, so this
item layered a session-local read state over it (`workspace/attention.ts`): a conversation opened in
this session counted as read, and its badge showed only what had arrived since - which the console
could know honestly, because `11-06` added `OperatorConnection.onAnyMessage` so it sees pushes for
every assigned conversation, not only the one on screen. The limitation that left, stated rather than
hidden at the time: after a hard reload, a conversation already read showed the server's total again
and over-reported.

**`5-15` closed it.** `POST /api/v1/conversations/{id}/read` clears the count server-side, up to the
sequence the operator actually has, so `operatorUnreadCount` now means what the badge claims and
survives a reload because it is a column. `attention.ts` kept only what a snapshot genuinely cannot
know - arrivals and clears since the last queue fetch, plus the session-local "New" marker - and the
reload limitation above no longer exists.

## Open questions

None. The one genuinely discretionary choice - how a newly assigned conversation announces itself -
was decided by the implementing session and is written up above.
