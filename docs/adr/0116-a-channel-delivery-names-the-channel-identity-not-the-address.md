# ADR-0116: A channel delivery names the channel identity it went through, never the address

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 23 (`23-19`)

## Context

`docs/design/decisions.md` §9 names the fact this item exists for: `DeliverChannelMessageHandler`
already receives the provider's own answer to every outbound channel send, and throws it away. `23-19`
records it, and the row has to identify **where** the message went. Two shapes were available: the raw
`ExternalChannelAddress` — a phone number, a provider chat id — or a reference to the
`ChannelIdentity` row that already holds it. The backlog item deliberately refused to choose, naming
the trade instead: *one of those choices puts a phone number in a second table and the other makes the
record depend on a row that can be unlinked.*

`adr/0112` and `adr/0113`, landed hours earlier in the same stage, settled the general form of this
question: what may an evidentiary row name, and why does the answer differ by purpose. `0112` withholds
its subject entirely, because an erasure receipt naming the erased person keeps the pointer it exists
to remove. `0113` names the resource read, because an access record that does not is answering a
question nobody asked. This row is neither: it must say enough to be useful evidence — *did message X
reach the number on file* — without becoming a second copy of that number.

## Decision

`channel_deliveries.channel_identity_id` references `channel_identities.id`, with a **real, enforced
foreign key**, `ON DELETE CASCADE`. The row never carries `ExternalChannelAddress`. `channel_kind` is
denormalised onto the row directly — it is not personal data, and it is free at write time.

**The reference is safe here for a reason specific to this pair of tables, and it was checked rather
than assumed.** `ChannelIdentity` is never hard-deleted on its own: `Unlink` only sets `Active = false`
and stamps `UnlinkedAt` — the row and its address persist, because *this number stopped being this
visitor* is itself a fact worth keeping. The only path that hard-deletes a `ChannelIdentity` row is
`SiteErasureJob`'s whole-site cascade, and `channel_deliveries.site_id` cascades from `sites` too, so a
site erasure removes both tables' rows in the same statement. The reference never has to outlive the
row it points at.

**`conversation_id` carries no foreign key**, by contrast. A single conversation can be erased
independently of its site (`ConversationErasureJob`), and this record — an outcome and a provider
detail, no message content — is exactly the low-sensitivity evidence `adr/0112` and `adr/0113` argue
should survive that narrower erasure.

Retention is its own window with its own prune job, and `personal-data.md` carries the row.

## Alternatives considered

**Store the raw address, accepting a second copy of the phone number.** Rejected: a delivery row is
written once per outbound message, so this would grow a second, append-only store of the same
identifying value that `channel_identities` already minimises to one row per site and address — the
deletion-journal shape `personal-data.md` rejects for erasure, applied here to routine logging. It
would also widen what a future per-address erasure must reach, buying only self-contained rows, which
the foreign key already provides by join.

**No foreign key at all, mirroring `adr/0112`/`adr/0113` exactly.** This is the tempting one, because
copying the nearest precedent always looks consistent. Rejected because those two give up referential
integrity for a specific purpose — surviving an erasure of their subject that happens *while the table
itself lives on* — and no such case exists here. Giving up the key would trade real integrity and a
join-free read for a guarantee this table never needs.

## Consequences

**Positive.** A tenant reading a delivery record can join to the identity it names, with the database
enforcing that the reference is valid. No new store of a phone number or chat id exists anywhere in
this table. A delivery made before an unlink still resolves to the channel and address it always did —
unlinking changes future routing, not what already happened.

**Negative, and stated rather than discovered.** This decision rests on `ChannelIdentity`'s *current*
lifecycle, not on a law about the domain. **If a future item ever makes a `ChannelIdentity` row
hard-deletable independently of its site, this foreign key stops being safe** and the table needs the
FK-less shape `adr/0112` and `adr/0113` use. That is the first thing to reopen here, and it is written
down because the day it matters, nothing else in the schema will say so.
