# ADR-0124: Blocking a conversation is one state, and a blocked visitor's inbound message is accepted, stored, and left unprocessed

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 24 (`24-10`)

## Context

`24-06` found a real gap. `16-02` built erasure — "delete my data" — and answered it completely, but
the statutory operation list a processing instruction enumerates includes **blocking** as an operation
distinct from destruction, and this codebase had no state between "processed normally" and "gone".

`24-10` builds that mechanism. Its own Open Questions left two things undecided and said so: whether
"block" is one state or two, and what happens to a message a blocked visitor sends anyway. Both are
product decisions the author had not made. This ADR is the engineering side's reading of both, built
and tested — the same posture `adr/0076` took for the controller/processor split this item sits beside,
and the author's to overturn.

**Why blocking cannot reuse `conversations.erasure_requested_at`.** Erasure is terminal and
one-directional: a flag is set, a job drains the row, and the window is short by design. Blocking must
hold indefinitely, must be reversible, and must coexist with erasure being requested on the same row
for an unrelated reason — a tenant could plausibly want a conversation frozen while a dispute about
whether to also erase it is unresolved. Treating block as a second meaning of the same flag would
conflate two operations the statute itself lists separately.

**Why the write bypasses the `Conversation` aggregate.** `ConversationRepository.GetByIdAsync` loads
the whole aggregate, messages included, on every write path. Routing a block through it would load a
full message history to flip two columns and race the row's `xmin` against every ordinary message send
— the identical reasoning `ConversationConfiguration`'s own remarks already give for why
`erasure_requested_at` is written by raw SQL rather than by a domain method.

## Decision

**1. Block is one state, not two.** `conversations.blocked_at`/`blocked_by`, both `NULL` or both set.
No third rung between "hidden but still processed" and "frozen". The item puts the burden on a second
state to justify itself against a named need, and neither `24-06` nor `24-10` names one. Two states
would double every read-path assertion this item's own Done-when requires enumerating one at a time,
for a distinction no caller in this codebase makes.

Blocked means: hidden from every ordinary operator-facing read — the conversation list, the detail
fetch, message history, `18-07`'s cross-conversation visitor history, full-text search, the operator
queue, four separate analytics and reporting read stores, and the tenant export — not routed by the
automatic assignment engine, and not answered by the offline auto-reply. It is reversible by the same
capability that set it (`Permission.ConversationBlock`, Admin role), and the block and its reversal are
recorded as **separate, independently timestamped acts** in `conversation_block_records` — never one
row updated in place, and never conflated with `erasure_records`.

**2. An inbound message from a blocked visitor is accepted and stored, not refused.** The visitor is
never told they are blocked. Refusing silently loses a real message from a real customer to a real
business, with no trace and no explanation reachable by anyone; refusing visibly would make AGO's own
widget state something about the visitor's data status that the **tenant** is the party who must decide
whether and how to say — contradicting the processor role `adr/0076` assigns AGO for exactly this kind
of visitor-facing communication. Storage-without-processing is also the shape blocking has in the
statutory list it comes from: storage is the one operation blocking explicitly permits.

Concretely, `SendVisitorMessageHandler` is unchanged — `AddVisitorMessage` on a blocked conversation
still succeeds. What changes is everything downstream that would have made an operator, an automatic
process or a report *act* on the arrival: the assignment engine's claim query excludes a blocked
`Waiting` conversation, and the offline auto-reply refuses one with a new
`OfflineAutoReplyOutcome.ConversationBlocked`. Both are needed because blocking does not change
`ConversationState`, so either mechanism would otherwise still treat the conversation as live.

**3. `conversation_block_records` carries a real foreign key with cascade delete**, unlike
`erasure_records` and `access_records`, which deliberately carry none so they survive the very deletion
they are evidence of. A block record describes *current, reversible operational state*; once a
conversation is genuinely erased there is nothing left to have been blocked about. This is the first
place in this stage where `adr/0111`'s no-FK mechanism is deliberately **not** reused, and the reason
is that the two tables answer different kinds of question.

## Consequences

**Positive.** A tenant instructed to suspend processing of one person's data has something to invoke,
distinct from destroying it, matching the operation list `24-06` found unimplemented. The mechanism is
small: two columns, one audit table, two use cases, and a predicate at every read the enumeration found.

**Negative, stated rather than discovered.**

- **Write paths beyond auto-reply and auto-assignment are not frozen.** Closing, assigning,
  transferring, setting an outcome, adding a note, and the realtime push to an operator's already-open
  tab are untouched. In practice a blocked conversation is unreachable by id through every discovery
  path, so this bites only where an operator already held the id — but that is a consequence of the
  read-path work, not a guarantee this decision makes about writes. If it matters, it is a scoped
  follow-up, not a silent gap.
- **`blocked_at IS NULL` is a predicate repeated by hand across roughly a dozen queries.** Nothing
  enforces that a future read remembers it — the same failure mode `24-06` found for blocking's total
  absence, one level down. This is the corner most likely to regress silently, and the reason the
  item's own report enumerates every read path by name rather than asserting the mechanism once.
- **A conversation can be blocked and flagged for erasure at once**, and this decision leaves that as
  unremarkable as it sounds: erasure proceeds on its own schedule, and a completed erasure takes the
  block's audit rows with it.

## Alternatives considered

**A second "hidden but still processed" state** — an operator loses read access while the conversation
keeps being auto-assigned, auto-replied to and counted. Rejected: nothing names the need, and a tenant
invoking blocking wants processing to stop, not merely to stop watching it happen.

**Refusing an inbound message from a blocked visitor**, silently or with an error. Rejected for the
reasons in Decision 2.

**Routing block and unblock through the `Conversation` aggregate**, with domain methods and events.
Rejected on the cost `erasure_requested_at` already rejected it for: loading and saving a whole
aggregate to flip two columns, racing every concurrent send's `xmin`, for no invariant this aggregate
needs to enforce. `BlockedAt`/`BlockedBy` are ordinary mapped properties rather than EF shadow
properties, so a handler that already loads the aggregate for an unrelated check gets `IsBlocked` free
from the same row — but the write itself never goes through `SaveChangesAsync` on this aggregate.

**A per-visitor block as well as per-conversation.** The item named this as "where it makes sense"
rather than a requirement, and nothing needs it. Building it would mean a second flag with its own
read-path sweep, speculative ahead of a named need.
