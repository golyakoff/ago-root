# an operator can close a conversation as spam

- **Stage**: 23
- **Status**: ready — **both open questions answered by the author, 2026-09-09, recorded below**
- **Depends on**: `24-10` built `ConversationBlock` — and, per the author's own answer below, this item
  reuses that same mechanism rather than a neighbour to it.
- **Decision**: the author's, 2026-09-07, including the reason abuse is not the objection.

## What is actually true today

Conversations are routed to whichever operator is free. There is no way to say *this one was not a
customer*. An operator who gets a stream of junk closes it like any other conversation, and nothing
distinguishes it afterwards — not in the numbers, not in the queue, not for the next message from the
same visitor.

## Why abuse is not the argument against it

The author's own reasoning, and it is the right one: **the tenant can see both the statistics and the
closed conversations themselves, and take it up with the operator.** An operator marking real customers
as spam is not hiding — they are leaving a record with their name on it.

That has a consequence for the build rather than being a reassurance: the feature is only defensible
**if the record is actually there and actually reachable.** Three properties are therefore scope, not
polish:

- **Attributed.** Who closed it as spam, and when.
- **Visible.** A tenant can see how much of it there is, and read the conversations themselves.
- **Reversible.** A mistake can be undone, and the undo is recorded too. An irreversible judgement made
  in one click by a tired person is a worse tool than no tool.

## The two questions, and they are the author's — both answered 2026-09-09

**1. Does marking spam do anything, or only record it? Decided: it auto-mutes the visitor for a
window of time.** Marking a conversation as spam both records the judgement and suspends that
visitor for a stated duration — the middle of the three options this item named, taken deliberately:
records-only was rejected as giving the operator nothing for the click; hands-to-tenant was rejected
as slower with no stated advantage the author asked for. The failure mode this option itself named
("a visitor who was misjudged is silently unable to reach the shop") is real and accepted — mitigated
by the record being attributed, visible and reversible (this item's own three scope properties above),
not by avoiding the mute.

**2. Is this the same thing as blocking? Decided: yes, the same mechanism.** Marking spam applies
`24-10`'s own `ConversationBlock` to the visitor, rather than a parallel mechanism. `24-10` built a
manually-reversed, indefinite block with no expiry concept — this item's own "for a window of time"
answer to question 1 means `ConversationBlock` needs a stated, automatic expiry added as part of this
item's own scope, not assumed to already exist. Read `24-10`'s actual shipped code
(`ago-chat`, `docs/backlog/24-10-*.md`) before building — it explicitly left a console screen for its
own number and named `blocked_at IS NULL` as a repeated, hand-written predicate across roughly a dozen
queries; both are directly relevant to building spam-marking on top of it correctly rather than
re-discovering either.

## Where this is likely to go wrong

- **Spam is a judgement about a person, and it is stored.** `personal-data.md` should say that a
  visitor may be labelled this way and what that means for them.
- **Statistics that count spam must not count it twice** — a conversation closed as spam is still a
  conversation, and `23-18`'s operator numbers will change shape. Decide whether an operator's own
  figures include them.

## Done when

- [ ] An operator can close a conversation as spam, in one act, which applies `ConversationBlock` to
      the visitor with a stated expiry (not indefinite) — the author's own decided shape.
- [ ] The tenant can see how many, by whom, and read the conversations themselves.
- [ ] It can be undone before the expiry, and the undo is recorded; after the expiry, the block lifts
      on its own.
- [x] Question 1 is answered — auto-mute for a stated window, recorded above.
- [x] Question 2 is answered — the same mechanism as `24-10`'s blocking, recorded above.
