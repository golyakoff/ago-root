# The operator workspace: a screen someone can work a shift in

- **Stage**: 11 (added 2026-08-24 with `11-05`, when the stage was widened to cover both surfaces)
- **Status**: ready
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

- [ ] The three-region layout works, and `/conversations/:id` still loads a conversation directly.
- [ ] The thread shows grouped, side-distinguished messages with timestamps and day separators
      following `date-and-time.md`, and no `[sequence]` prefix in the visible text.
- [ ] The composer is multiline with Enter/Shift+Enter, and attachments are sent from within it,
      including by drag-and-drop and paste.
- [ ] Unread counts appear in the list and in the document title; the new-assignment behaviour is
      implemented and stated.
- [ ] The list shows elapsed waiting time, ordered oldest first, with waiting rows legibly read-only.
- [ ] The connection indicator shows reconnecting and degraded states honestly.
- [ ] The layout holds on a laptop screen and collapses to one column when narrow.
- [ ] Proven live with two browsers against the local cluster, including a reconnect and a failed send.

## Open questions

None. The one genuinely discretionary choice — how a newly assigned conversation announces itself —
is small enough for the implementing session to decide, provided it states what it chose and why.
