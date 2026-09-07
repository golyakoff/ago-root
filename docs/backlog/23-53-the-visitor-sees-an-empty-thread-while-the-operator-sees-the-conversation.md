# the visitor sees an empty thread while the operator sees the whole conversation

- **Stage**: 23
- **Status**: done — `ago-widget#60`, `ago-chat#212`, `adr/0141`.
- **Found**: 2026-09-07, by the author, using the widget on their own site.
- **Decision**: the author's, 2026-09-07 — show the visitor their own history. The two questions the
  implementation must settle are below; neither is a reason not to build it.

## What happens

The author wrote to their own site's widget, answered from the operator console, and wrote again — all
one conversation, one session, the operator's screen showing every message.

**Reopening the widget shows the visitor an empty thread.**

Not a stale one, not a partial one — nothing. The session is alive enough to *write into the same
conversation*, and shows none of it back.

## Why this is worse than it looks

- **It reads as data loss.** A person who wrote a paragraph and comes back to a blank panel does not
  think *"my history is not loaded"*, they think *"my message is gone"* — and writes it again, to an
  operator who now has it twice.
- **It contradicts what the widget already does.** The session survives, the conversation survives,
  the operator's replies arrive in it. Everything is there except the one view the visitor has.
- **It is the ordinary case, not an edge.** Any visitor who closes a tab and comes back hits it.

## The two things the implementation must settle — not objections

**1. A shared device sees more than it does today.** The visitor token lives in the browser. Right
now, whoever sits down next can *continue* the conversation but cannot *read* it. Showing history adds
reading: a second person at the same machine sees what the first wrote and what the operator replied.

That is a real, if small, new exposure, and it deserves a deliberate answer rather than being
discovered. Cheapest honest options: show it, because continuing the conversation already implies
access to it; or bound it by the session rather than by the conversation's whole life.

**2. A conversation holds more than the visitor's own messages.** Operator notes, system events, and
whatever `14-06`'s structured content carries are all in there. **The read must return what was
addressed to the visitor, not everything the conversation contains** — and that is the single place
this item can go wrong invisibly, because an over-broad read looks identical to a correct one until
somebody reads a note they should not have.

## Scope

- The visitor's own conversation history, in the widget, on reopen — scoped by the visitor's own
  signed token, never by anything the caller supplies.
- **Only what was addressed to the visitor.** Asserted by a test that puts an operator note and a
  system event in the same conversation and proves neither comes back.
- A cross-visitor test in the shape every other isolation test here takes: one visitor never reads
  another's thread, and a visitor of one site never reads a conversation of another.
- Whatever erasure already promises stays true — a message erased under `16-*` does not reappear
  because a new read path was added.

## Out of scope

- Notifying the visitor of anything while the widget is closed. That is `14-*`'s territory.
- Changing what the operator sees.
- History across devices. The token is per-browser and this item does not change that.

## Done when

- [x] Reopening the widget shows the visitor the conversation they are already in.
- [x] An operator note and a system event in the same conversation are proven not to reach the visitor.
      The two halves are not equally strong and the test says so: the note is a real fault injection
      (unioning its row in reddens the test), the system event holds by construction — nothing writes
      `ConversationAssigned` to any table the query reads, so there is no row to inject.
- [x] A visitor cannot read another visitor's conversation, or one belonging to another site.
      Was already true before this item and is now asserted rather than inferred: the read is scoped by
      the signed token's own `VisitorId` claim, which is why the server needed no change.
- [x] The shared-device question is answered in the change, in one sentence, rather than left implicit.
      Answered in `connection.ts`, `adr/0141` and `personal-data.md`: a second person at the device can
      now read what they could already continue by writing into it.
