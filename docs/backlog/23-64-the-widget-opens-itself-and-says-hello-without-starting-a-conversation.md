# the widget opens itself and says hello, without starting a conversation

- **Stage**: 23
- **Status**: done — `ago-chat#244`, `ago-console#188`, `ago-widget#74`
- **Depends on**: `23-63` shares the settings screen but not the promise. `adr/0148` is the decision.
- **Decision**: the author's, 2026-09-07, including the constraint that makes the item interesting.

## Goal

A visitor who would have written, and did not, is invited — and a visitor who ignores the invitation
costs the tenant nothing at all.

## The constraint, which is the whole design

The author's own words: this must **not create a real conversation and must not assign one to an
operator** unless the visitor actually writes. *«Иначе будет множество лишних срабатываний.»*

That is right, and it is not merely a saving. A conversation that exists because a timer fired is a
row in the queue, an unread badge, a number in a report and possibly a notification — all describing
something that never happened. **A greeting nobody answered is not a conversation, and the system
should not learn otherwise.**

So the greeting is **drawn, not sent**. It appears in the panel; it is not a message, has no author,
is not stored, and does not exist server-side. `adr/0148` records the shape and what it costs.

## Scope

- **A checkbox «Раскрывать виджет автоматически»** in the widget settings, off by default, with a
  delay chosen from a closed list: **15, 30, 45, 60, 90, 120 seconds, default 30.** A select, not a
  free number — the author fixed the list, and a closed set is one fewer thing to validate.
- **The greeting text is the tenant's**, written in the same screen. There is no default sentence we
  supply: a greeting in our words on somebody else's shop is the same mistake `16-04` already forbids
  for consent text.
- **Opening is once.** A visitor who closed the panel, or who was already shown it, is not shown it
  again — decide the window and state it; the visitor's own session already has a lifetime and reusing
  it is the obvious answer.
- **Focus is not stolen.** The panel may open; the caret may not jump into it. Somebody typing in the
  host page's own form must not lose a keystroke.
- **Nothing reaches the server until the visitor writes.** No conversation, no assignment, no unread,
  no analytics row that implies contact.

## The two questions, answered by the author, 2026-09-09

**1. What happens to the greeting when the visitor does write?**

**Materialise it retroactively** as the conversation's first message, authored as the automatic
greeting rather than as a person — downloadable and visible to the operator like any other message.
The transcript reads correctly, forever, and the record matches what the visitor actually saw. This
was the item's own first-listed option; the other two (a side note, or nothing at all) are rejected.

**2. Whose name is on it?**

**The operator's name** — the author's original request, *«первого текста со стороны оператора»*,
stands as written. This is a deliberate departure from this item's own recommendation and from
`23-56`'s default (a machine's replies otherwise carry a tenant-editable name, «Электронный
помощник», precisely so a visitor is not told they are talking to a person who is not there). Record
this explicitly as the exception when it is built — the next reader of `23-56` should not conclude
the rule was simply missed here.

## Where this is likely to go wrong

- **Mobile.** A panel that opens itself over somebody's phone screen is far more intrusive than one
  that opens on a desktop. Decide whether the behaviour differs there, and do not discover it in
  production.
- **The drawn message must not survive a reload as a ghost.** It is not stored, so a returning visitor
  should see either a real conversation or nothing — never a greeting that appears to have been said
  twice.
- **`23-53` is the cautionary tale.** A visitor's transcript is rendered from what the server returns;
  a client-only message sitting in that list is exactly the kind of thing that produces an empty or
  duplicated view later. Keep it out of the rendered history's own data path.

## Out of scope

- The launcher animation, which is `23-63`.
- Any rule about *when* it is worth greeting — behaviour, pages visited, returning visitors. A timer is
  the whole trigger here.

## Done when

- [x] A tenant can turn auto-opening on, choose a delay from the six, and write the greeting text.
- [x] The panel opens after the delay and shows the greeting, with no default text of ours.
- [x] Nothing exists server-side until the visitor writes — no conversation, no assignment, no unread —
      asserted by a test rather than by inspection. The widget defers connecting the hub at all until
      the visitor's first real send, so a connect-without-send leaves nothing behind.
- [x] The greeting materialises retroactively as the conversation's first message when the visitor
      writes, downloadable and visible to the operator like any other message — inside the same
      transaction and outbox write as that first message, so a greeting can never exist without it.
- [x] **Attribution, settled with a stated departure from a literal reading of the decision above.**
      A new `MessageAuthorKind.AutoGreeting` carries the *same visual treatment* as an operator message
      — but is not literally "the operator's own name," because no operator is assigned to a
      conversation at the moment it materialises, and fabricating one would misattribute a specific
      person to something they never said. It is also deliberately not `System` (reserved for `23-56`'s
      future tenant-editable machine name, which the author explicitly did not want here). Recorded
      here, as the item itself asked, so the next reader does not conclude either rule was missed.
- [x] Focus is not taken from the host page; auto-open never fires on a coarse-pointer device (a
      self-opening panel is a proportionally larger interruption on a phone) — the mobile decision the
      item asked for, made and stated rather than discovered live.
