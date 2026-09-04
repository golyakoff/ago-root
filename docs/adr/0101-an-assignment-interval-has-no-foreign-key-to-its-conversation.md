# ADR-0101: An assignment interval carries no foreign key to its conversation

- **Status**: Accepted
- **Date**: 2026-09-04
- **Stage**: 23

## Context

`23-03` adds `conversation_assignments`: an append-only interval per assignment - which operator held
which conversation, from when to when, and how it came about (`decisions.md` §2's "store ownership
intervals, not counters" amendment). Its own Scope explicitly left one decision to the implementer:
"whether `16-02`'s conversation erasure drains this table."

`ConversationErasureQuery.DeleteConversationAsync` (`Ago.Chat.Worker`) is the answer to a related but
different question. `16-02` is a person's own erasure request, and it does not scrub the `conversations`
row's fields - it deletes the whole row, last, once every message, attachment, note and tag it owns is
confirmed gone. Every table that currently has a foreign key to `conversations` therefore either
cascades with it or must be drained explicitly first (`conversation_notes`, `conversation_tags` are
drained explicitly, for an observable count; `messages`/`attachments` cascade; `23-08` extends the same
job with an explicit drain of the visitor's own `visitor_contact_details`, keyed to the visitor rather
than the conversation).

`decisions.md` §2's own amendment states the consequence directly: *"erasing a conversation need not
take last month's numbers with it."* A `conversation_assignments` row holds an operator id, a
conversation id, two timestamps and a provenance label - `decisions.md` §2's own "timestamps are not
personal data, message content is" distinction applies to every column on it. Nothing on the row is the
kind of thing `16-02` exists to remove.

The two claims are in tension only if the schema does not separate them: EF's default for a required
relationship is a foreign key with cascading delete, the same default every other per-conversation table
in this schema currently takes.

## Decision

**`conversation_assignments.conversation_id` carries no foreign key at all.** It is stored, compared
and indexed like any other `uuid` column, but Postgres enforces no referential-integrity constraint
against `conversations.id`, and nothing in the schema cascades a `conversations` deletion onto this
table.

`site_id` and `operator_id` keep ordinary cascading foreign keys, to `sites` and `operators`
respectively - the same default every other tenant-scoped table in this schema uses. Neither a site nor
an operator is ever hard-deleted by anything this codebase runs today except the demo-tenant sweep
(`adr/0058`), which is a whole-site removal, not a per-person erasure, so the divergence this ADR
creates does not reach that path.

**Guarded, not merely documented.** `tests/Ago.Chat.Integration.Tests/ConversationAssignmentErasureGuardTests.cs`
seeds one conversation with a closed assignment interval, runs a real `ConversationErasureJob` cycle
against it, and asserts the conversation row is gone while the interval row survives and is still
readable. It is a guard rather than a fix - true today by construction, since the table has no FK to
cascade through and `ConversationErasureJob`'s own code never mentions `conversation_assignments` -
written so a future foreign key added "for consistency," or an explicit drain step added by a reviewer
assuming the same symmetry `conversation_notes`/`conversation_tags` use, cannot quietly reverse this
decision with no suite going red. Confirmed to actually catch that regression: a throwaway proof added
the forbidden foreign key (`ON DELETE CASCADE`) via raw SQL for one run, and the identical guard
assertion failed - the interval was cascade-deleted along with its conversation - before the constraint
was dropped again.

## Consequences

**Positive.** A tenant's workload statistics - who held how much, for how long, how it came about -
survive a visitor's own erasure request intact. This is the entire reason the amendment names the
consequence explicitly: `23-17`/`23-18` (an operator's own load and response-time reporting) would
otherwise lose rows out from under a report the moment a customer whose conversation contributed to it
asked to be forgotten, silently and with no error to notice by.

**Negative.** `conversation_assignments.conversation_id` can name a `conversations` row that no longer
exists - a real dangling reference this schema deliberately declines to prevent. Any future reader that
joins the two tables must treat a missing conversation as an expected outcome, not a data-integrity
bug: a query that does `INNER JOIN conversations` and expects every row to match will silently under-
count once an erasure has run. `23-17`/`23-18`'s own implementation has to read this ADR before writing
that join. There is also no database-level guard against a genuine bug that inserts an interval for a
conversation id that was never real in the first place - a mistake a foreign key would have caught at
write time and this schema now only catches by review and by the guard test above.

## Alternatives considered

**Cascade, matching every other per-conversation table.** The consistent choice, and the one that would
need no ADR - it is what EF does by default and what a reviewer would expect walking in. Rejected: it
is precisely wrong for this table, and it would be wrong silently. The failure would not appear until
the first real erasure request against a conversation with assignment history, at which point a
tenant's numbers would have already changed underneath them with nothing in the deploy, the migration,
or the code review to have flagged it.

**Cascade, but have `16-02` copy the row's facts into a separate summary before deleting the
conversation.** Considered and rejected as unnecessary complexity: the row already holds nothing that
needs copying out from under a delete, because it names no content and no visitor. A copy step would be
solving a problem this table does not have, at the cost of a second write path to keep correct.

**`ON DELETE SET NULL` on `conversation_id`.** Rejected outright: the column is not nullable and has no
honest null value - an interval with no conversation is not a smaller fact, it is a different, wrong
one. A dangling reference that is still resolvable to "the conversation that used to be here" is more
useful than a null that resolves to "nothing was ever recorded."

**Explicit drain, the `conversation_notes`/`conversation_tags`/`23-08` shape** - have `16-02`'s job
delete `conversation_assignments` rows itself, observably, before the conversation row goes. Rejected
on the merits, not on cost: those tables hold personal data and *should* disappear with the
conversation. This table holds none, so draining it would be removing data `16-02` has no mandate to
touch, for symmetry with tables it does.
