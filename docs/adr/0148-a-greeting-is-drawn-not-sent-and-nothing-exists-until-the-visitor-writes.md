# ADR-0148: a greeting is drawn, not sent, and nothing exists until the visitor writes

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-64`)

## Context

The author asked, 2026-09-07, for the widget to open itself after a delay and show a first line from
the shop's side — and attached the constraint that makes it worth an ADR: it must **not create a real
conversation and must not assign one to an operator** unless the visitor actually writes.
*«Иначе будет множество лишних срабатываний.»*

Every message in this system today exists because somebody sent it. A conversation exists because
somebody started one. Those two facts are load-bearing well beyond the widget: a conversation is a row
in the operator's queue, an unread count, a line in `23-18`'s analytics, an assignment, and — once
`14-04` and `23-39` land — something a machine may answer. A timer that manufactures conversations
manufactures all of it.

## Decision

**The greeting is drawn in the panel and does not exist anywhere else.** It is not a message: no
author, no identifier, no row, no event, nothing sent to the server, nothing returned by the history
read. The widget renders it locally from the tenant's configured text.

**Nothing reaches the server until the visitor writes.** Auto-opening produces no conversation, no
assignment, no unread and no analytics row implying contact. A visitor who ignores the panel or closes
it leaves exactly the trace they would have left without this feature: none.

**The drawn greeting is kept out of the rendered history's own data path.** It is not appended to the
list the server's history populates. `23-53` is the reason this is stated rather than assumed: a
visitor's transcript is rendered from what the server returns, and a client-only entry living in that
list is precisely how an empty or duplicated view is produced later.

## Why not the alternatives

**Create the conversation and send a real greeting.** Rejected, and it is what most products do. It
makes every timer expiry a real conversation, so the queue fills with rooms nobody entered, the unread
count stops meaning anything, and an operator's day is spent closing them. It also silently changes
what the tenant's own numbers mean.

**Create the conversation lazily but send the greeting as a real message the moment it is drawn.**
Rejected: it is the same thing with an extra step. A message needs a conversation to belong to.

**Persist the greeting as a pending message and promote it if the visitor answers.** Rejected for now,
and it is the closest rival. It would make the transcript correct without creating a queue entry — but
it is a new lifecycle for a message, with a cleanup story for the ones nobody answers, and the whole
point of this decision is to avoid manufacturing rows. `23-64`'s own first question keeps the door open
to a narrower version of this: materialising the greeting **at the moment the visitor writes**, when a
conversation is being created anyway.

## Consequences

**Positive.** A feature whose whole risk is noise adds none: nothing is created, nothing is counted,
nothing is assigned, and a visitor who ignores it is indistinguishable from one who was never greeted.
It also costs no server work at all — the entire feature is configuration plus rendering.

**Negative, and stated rather than implied.**

- **The transcript may not explain itself.** If the greeting is never materialised, the operator sees a
  visitor's first message answering a question that is not in the record. `23-64` names this as the
  author's question and does not settle it here.
- **A drawn greeting is not part of any record.** A visitor who later asks what they were shown cannot
  be answered from the data — only from the tenant's configuration as it stands today, which may have
  changed. That is a real limit of a thing that was never stored.
- **The widget now renders something that is not a message**, in a list that otherwise contains only
  messages. That is a seam, and seams attract bugs; it is why the decision insists the two stay in
  separate data paths rather than being merged for convenience.
- **Attribution is now a live question**, because `23-56` decided a machine's replies carry a
  tenant-editable name rather than a person's. A greeting shown as if from a named operator would
  contradict that decision at the first thing a visitor ever sees.
