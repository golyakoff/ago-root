# the tenant can remove a message from the team chat

- **Stage**: 23
- **Status**: done (2026-09-06). A tombstone, `site:manage_operators` checked live, its own
  cascading record, and its own realtime channel. `adr/0133`.
- **Depends on**: `23-32` — hard. There is nothing to moderate until the room exists.
- **Decision**: the author's, 2026-09-06 — filed separately and deliberately after the chat itself

## Goal

The person answerable for the business can take something out of the team's room without asking us.

## Why this is its own number

`23-32` is useful the day it lands with no moderation at all, and moderation is meaningless without a
room. Two promises, each landing green on its own — `CLAUDE.md` rule 15's own test. Folding them
together would also mean one review carrying two arguments: how a chat works, and who may erase what
somebody else wrote.

## What makes this harder than a delete button

**A removal is itself a fact somebody may need to account for.** A message that vanishes silently is
indistinguishable from one that was never sent, and the person who wrote it is a colleague, not a
visitor — they will notice, and they will ask. This is the same shape `adr/0118` settled for a forced
revoke: the power exists, it is asymmetric, and **exercising it leaves a record**.

The open half is what the *room* shows. A tombstone («сообщение удалено») is honest and can be
uncomfortable; silent removal is comfortable and is a small lie. That is a product decision, not an
engineering one.

## Scope

- The account owner can remove a message from the team chat.
- **The removal is recorded** — who removed what, when — on `module_revoke_overrides`' own shape:
  its own small table, no aggregate, and it outlives the message it describes.
- An ordinary operator cannot remove anybody's message, including their own, unless this item decides
  otherwise (see the open question).

## Out of scope

- Editing a message. Removal and rewriting are different powers and rewriting is the more dangerous one.
- Bans, mutes, or anything that stops a person writing. That is a seat question, and seats already
  have their own machinery.

## Done when

- [x] The owner can remove a message; an operator cannot remove another's.
- [x] Every removal leaves a record naming who did it and when, and that record survives the message.
- [x] `personal-data.md` records the removal log as data about the **operator**, the way
      `contact_reveals` and `access_records` already are.

## Open questions

- **What the room shows in its place** — a tombstone or nothing at all. The argument is above and the
  call is the author's.
- **May a person delete their own message?** Almost every chat allows it and it is a different power
  from moderation — it needs no record of who did it, because the answer is always "they did".
