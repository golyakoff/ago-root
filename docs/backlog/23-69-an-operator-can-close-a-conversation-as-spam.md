# an operator can close a conversation as spam

- **Stage**: 23
- **Status**: ready — **and it carries two questions, named below**
- **Depends on**: `24-10` built `ConversationBlock`, which is the neighbour this must not be confused with.
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

## The two questions, and they are the author's

**1. Does marking spam do anything, or only record it?**

If it only records, this is bookkeeping and the operator gets nothing for the click. Options, and they
are genuinely different products:

- **Records only.** Simplest, honest, and the operator's reward is a cleaner report rather than a
  quieter day.
- **Records, and the same visitor's next message does not create a new conversation** for some window.
  That is where the value is — but it means a visitor who was misjudged is silently unable to reach the
  shop, which is the failure mode worth being afraid of.
- **Records, and hands the decision to the tenant** — a report of who was marked, with blocking as a
  separate, deliberate act. Slower, and the only one where a wrong call is caught by somebody other
  than the person who made it.

**2. Is this the same thing as blocking?** `24-10` built `ConversationBlock`. Closing as spam and
blocking a visitor are different acts with very different consequences, and if they end up sharing a
mechanism it should be because somebody decided that, not because both were about unwanted messages.

## Where this is likely to go wrong

- **Spam is a judgement about a person, and it is stored.** `personal-data.md` should say that a
  visitor may be labelled this way and what that means for them.
- **Statistics that count spam must not count it twice** — a conversation closed as spam is still a
  conversation, and `23-18`'s operator numbers will change shape. Decide whether an operator's own
  figures include them.

## Done when

- [ ] An operator can close a conversation as spam, in one act.
- [ ] The tenant can see how many, by whom, and read the conversations themselves.
- [ ] It can be undone, and the undo is recorded.
- [ ] Question 1 is answered in the change rather than settled by what was easiest to build.
- [ ] The relationship to `24-10`'s blocking is stated, whichever way it goes.
