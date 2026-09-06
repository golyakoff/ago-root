# ADR-0133: A team message removal is a tombstone, gated on `site:manage_operators`, and its own small record cascades with the room rather than outliving it

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 23 (`23-33`)

## Context

`23-32` shipped the team chat's own room with deliberately no moderation at all - "the room is useful
the day it lands with no moderation, and moderation is meaningless without a room" (`23-33`'s own "Why
this is its own number"). `23-33` is the second half: the account owner can remove a message. The
item's own brief names the two things a delete button is not: **the removal is itself a fact somebody
may need to account for** ("a message that vanishes silently is indistinguishable from one that was
never sent... they will notice, and they will ask"), and it names `adr/0118`'s forced-revoke record as
the shape to follow - "the power exists, it is asymmetric, and exercising it leaves a record."

Three things the backlog item left open, deliberately, for whoever implemented it to decide and state
loudly rather than default silently:

1. **Hard delete or tombstone.** `23-32`'s own `ITeamMessageReadStore.GetDeltaAsync` reconnect
   catch-up walks the room's `sequence` column as a contiguous counter; a physically deleted row
   punches a hole in it.
2. **Who may remove.** `23-32` gave the room's own send path no permission gate at all - every
   operator may post, unconditionally - and used `Permission.SiteManageOperators` only to decide the
   admin *label*, never an authorization outcome. Removal is the first genuine capability this room
   has ever needed.
3. **Whether a person may remove their own message without a record** - the item's own second Open
   Question, explicitly left to the author's later call rather than assumed either way.

## Decision

**A removal is a tombstone, never a physical `DELETE`.** `TeamMessage` gains `RemovedAt`
(`DateTimeOffset?`, `private set`) and a `Remove(DateTimeOffset)` method that sets it once and throws
on a second call - the same defensive-invariant shape `Attachment.MarkDeleted` already takes, with the
identical idempotency split: the caller (`RemoveTeamMessageHandler`) checks `RemovedAt is not null`
*before* calling `Remove`, and returns success without calling it again, the same "tolerate
already-gone" shape `DeleteAttachmentHandler` already uses for a retried delete. The row, and its
`sequence`, are never deleted.

**The original text is not scrubbed from the row.** `TeamMessage.Body` is untouched by removal - the
account owner's power here is to stop the room from *serving* the content, not to destroy AGO's own
copy of it. `TeamMessageReadStore` is where redaction actually happens: its `ToItem` projection
returns `Body: null` whenever `RemovedAt` is set, for all three of its own queries
(`GetHistoryAsync`/`GetDeltaAsync`/`GetBySequenceAsync`), so a removed message's text never crosses out
of `Ago.Chat.Infrastructure.Postgres` at all - not even as far as `Ago.Chat.Application`, let alone the
wire. `personal-data.md`'s own `team_messages` row already retains this table forever with none of
`messages.body`'s per-tier tiering machinery (`adr/0031`) to safely strip content with; building a
scrub path for one column, for one action, in one table, is exactly the machinery this item's own
scope never asked for. The client renders a fixed placeholder ("Сообщение удалено") whenever
`removedAt` is set and is contractually forbidden from treating a `null` `Body` any other way
(`TeamMessageDto`'s own remarks).

**Gated on `Permission.SiteManageOperators`, checked fresh against the remover on every call - never
the message's own stored `AuthorIsAdmin` label.** `RemoveTeamMessageHandler` calls
`IPermissionChecker.HasPermissionAsync` itself; it does not read the label `SendTeamMessageHandler`
stamped on the message at send time, which answers "was the author the tenant's admin the day they
sent this," a different question from "does the caller hold that power right now." Reusing the
*permission* rather than minting a new `team_chat:moderate` one: `SendTeamMessageHandler`'s own remarks
already establish that this codebase treats `SiteManageOperators` as the precise definition of "the
account owner" (grant permissions, configure the site, erase it), and the backlog item's own Scope
names the actor by that exact description. A new permission would answer a question this codebase has
already answered.

**An ordinary operator may not remove their own message either - Open Question two is decided against
self-delete, in this item.** Scope's own literal text - "An ordinary operator cannot remove anybody's
message, including their own" - is the reading taken, not the "almost every chat allows it"
alternative the item's own Open Questions section raises for the future. The two are genuinely
different powers with different accountability shapes (the item's own words: self-delete "needs no
record of who did it, because the answer is always 'they did'"), and building both in one item would
be two promises under CLAUDE.md rule 15 - this item ships only the one its own Scope actually
describes; self-delete is left for its own future item if wanted.

**The accountability record is its own small table, `team_message_removals` - one row per removal: who
removed which message, when.** Written through EF (`TeamChatRepository.RemoveAsync`), not raw Npgsql
the way `adr/0118`'s `module_revoke_overrides` is - see the next paragraph for why the two tables,
alike in shape, diverge on both the writer and the foreign keys.

**A real foreign key to `sites` and to `team_messages`, both `ON DELETE CASCADE` - the opposite call
from `module_revoke_overrides`' own no-FK choice, made deliberately rather than copied.** That table's
own no-FK reasoning is specific to *why* it exists: a tenant whose purchase was overridden, and who
later closes their account, is exactly the tenant most likely to ask "who took this away from me" -
a cascading FK would erase the answer with the account it was about. `team_message_removals` answers a
different question, asked by a different party: an internal moderation log, visible only to the
tenant's own team, about content that belongs entirely to that team's own room. `23-32`'s own
Done-when - "erasing the site erases the room" - reaches this table too: a removal record that
survived the site's own erasure would be the one fragment of the room left standing, itself an
unreachable piece of an operator's personal data with nothing left to attach it to. Within ordinary
operation (the tenant still exists, one message among many was removed) the record does survive the
message it describes, exactly as the backlog item's own Done-when asks - the tombstone design above
means `team_messages` rows are never deleted independently of the site, so this FK only ever fires
alongside that same site-wide cascade.

**Written inside the same `SaveChangesAsync` that tombstones the message and stages the outbox row -
CLAUDE.md rule 4, and a stronger consistency guarantee than `module_revoke_overrides` itself needs.**
That table's own write is a synchronous audit entry with no integration event of its own, so a second,
separate raw-Npgsql statement costs it nothing extra to run after its own EF write. This item's own
record must accompany a genuinely new event - `TeamMessageRemoved`, the outbox row that drives the
realtime tombstone push - so it rides the one transaction EF already owns rather than opening a second
one two independent writes would need to coordinate.

**A distinct outbox event and a distinct SignalR push method, `TeamMessageRemoved`, never a second
`TeamMessagePosted`.** The console's own transport-level dedup (`SeenMessageIds`, keyed by message id)
exists specifically to collapse an operator's own local echo of a *new* post against its fan-out copy;
a removal push names an id already seen once for its original post, so routing it through
`TeamMessageReceived` would be silently dropped forever by that exact mechanism. A new Worker consumer
(`TeamMessageRemovedFanoutConsumer`) and a new Application handler
(`ResolveTeamMessageRemovalDeliveryTargetsHandler`) mirror `TeamChatFanoutConsumer`/
`ResolveTeamMessageDeliveryTargetsHandler` almost exactly - same recipients (every operator of the
site, including the remover), same re-read-the-row-before-pushing discipline - differing only in the
push's own method name, kept as two small classes rather than one parameterized by a method string, the
same "no generalisation ahead of a second, genuinely different need" restraint `TeamMessage`'s own
domain remarks already state for declining a shared aggregate base.

## Alternatives considered

**Hard-deleting the row.** Rejected: `23-32`'s own reconnect-delta query treats `sequence` as a
contiguous counter a resuming client can trust; a hole in it is exactly the failure mode that query's
own design exists to avoid, and nothing about `23-33`'s own scope needs the row gone rather than
merely hidden.

**Scrubbing `Body` at rest on removal (overwriting the column, or making `TeamMessage.Body` nullable
to support it).** Rejected for two reasons together: it would have required the domain's own
`MessageBody` value object to grow a null case it has never needed elsewhere in this codebase, and
nothing in this item's scope - accountability, not data minimization - asked for the original text to
become genuinely unrecoverable. `personal-data.md`'s own team-chat row already accepts indefinite
retention of this table without per-tier tiering; adding a bespoke scrub path for one column to avoid
a retention question nobody raised would be exactly the machinery `TeamMessageConfiguration`'s own
remarks warn against building ahead of a real number.

**A dedicated `team_chat:moderate` permission**, matching adr/0016's own granular-permission
convention (a supervisor who may close conversations but not reassign them). Rejected here
specifically: `SiteManageOperators` already *is* this codebase's definition of "the account owner"
(`SendTeamMessageHandler`'s own remarks), and the backlog item's own Scope names the actor by exactly
that description. A new permission would be a second, competing answer to a question this codebase has
already answered - the same reasoning that handler's own remarks give for not inventing a first-
operator-only `IsAccountOwner` flag either.

**Allowing self-delete without a record**, the "almost every chat allows it" reading the backlog
item's own Open Questions raises. Rejected for this item specifically, not as a permanent judgement:
Scope's own literal text says otherwise, and the two powers have genuinely different accountability
shapes - bundling them would be two promises under CLAUDE.md rule 15, not one. Left as a clearly
separable future item if the product ever wants it.

**No FK on `team_message_removals.site_id`/`team_message_id`, copying `module_revoke_overrides`
verbatim.** Rejected: that table's own no-FK choice is not a generic "accountability records never
cascade" rule - it is specific to surviving a tenant's own account closure for a question the tenant
might ask *after* losing the ability to look. This table's own subject (the room) is erased alongside
it by `23-32`'s own design; a removal record that outlived the room would be a data-minimization
failure, not a feature.

**Raw Npgsql for `TeamChatRepository.RemoveAsync`, matching `ModuleRevokeOverrideRepository`'s own
shape.** Rejected: unlike that table's synchronous, event-less write, this write must commit
atomically with the `TeamMessageRemoved` outbox row (CLAUDE.md rule 4) - EF's own change-tracked
`SaveChangesAsync`, already open for the tombstone mutation, is what makes that one transaction rather
than two to coordinate.

## Consequences

**Positive.** A colleague who wrote a message that later disappears sees an honest tombstone, not a
gap that reads as a bug or a memory they can no longer trust. The permission that gates removal is a
real, freshly-checked capability, not a label reused past its own meaning. The accountability record
survives exactly as long as the room it describes does - present for every ordinary dispute, gone
precisely when the room itself is.

**Negative, and stated rather than discovered.** The original text of a removed message remains
queryable at rest by anyone with direct database access (AGO's own staff), even though no product
surface this item builds ever serves it again - a real, accepted gap between "removed" and "destroyed"
that a future item would need to close explicitly if that distinction ever matters. `TeamMessageDto`'s
own nullable `Body` is a wire-contract change every future team-chat client must respect; a client that
ignored `removedAt` and rendered a `null` `Body` as empty string rather than a tombstone would silently
misrepresent a moderated message as a blank one.

**No console screen surfaces `team_message_removals` itself** - the same "reserved for a future
support screen, no migration of its own needed" posture `module_revoke_overrides` took in `23-13`,
restated here for the identical reason: nothing in this item's scope asks who removed what to be
visible anywhere but the database.
