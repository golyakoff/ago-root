# ADR-0183: a visitor and a customer are one person, joined by a shared key, not one row

- **Status**: Rejected (author, 2026-09-25) — rejected the copy/shared-key hybrid outright: no duplicating
  person data between products, no backfill-alignment. One source of truth for a person is required (a
  cross-product attribute like "creditworthy" set once, seen everywhere). Superseded by the `26-134` round-2
  decision (chat-as-person-registry vs a standalone user-api) — a later ADR will record the chosen shape.
- **Date**: 2026-09-25
- **Stage**: 26
- **Amends**: ADR-0147 (its idempotency key and event payload; its publish/consume/backfill/no-auto-merge
  machinery stand). **Extends** ADR-0093's identity-unification to the end-person. Does not weaken ADR-0065
  (the calendar interprets nothing chat sends) or ADR-0012 (no shared data).

## Context
adr/0093 unified **operators** (one account-side person, projected per product; calendar dropped its
operators table, 22-05). adr/0147 decided how a chat contact reaches the calendar: chat publishes
ContactCollected, the calendar copies it into its own Customer, neither reads the other — applying adr/0093's
domains-apart half but not its identity-unifies half (framed as "a contact should also be a customer", a
copy). The event carries a per-fact id (ContactDetailId) and no person key; the calendar keys its
chat-sourced customer on that per-fact id (source_contact_id).

Three failures (26-132): the chat booking books DisplayName: null (ReplyToModuleTaskHandler.cs:411); a Name
detail is a different row/id than the Phone detail, so it can't fill the phone-keyed customer (and email has
no column); one person who chats and books is multiple rows needing manual merge. The two entities
legitimately hold different domain facts, and a customer can exist with no visitor — so the fix is not to
merge them.

## Decision
A person is one identity across products, carried as a shared opaque key; each product keeps its own row.
1. The chat Visitor is the shared anchor. ContactCollected gains VisitorId (v2); the calendar stores it
   opaque, never dereferenced (like Operator.ExternalSubjectId).
2. The chat-sourced customer is keyed by the person: SourceContactId -> SourceVisitorId; index
   (tenant_id, source_visitor_id). Name+Email+Phone events for one visitor upsert one row.
3. The calendar persists name and email: consumer stops discarding Name/Email; customers gains email;
   display_name/email filled from the collected identity (operator-entered name never overwritten - COALESCE).
4. The chat booking fills name/email from the same key instead of null - no booking-flow name step, no
   re-ask (26-133 decision B).
5. Unchanged: two schemas/databases, one product per repo; calendar owns no-shows/verification/notes/merges/
   bookings; chat owns name/email/channels/conversation; publish/consume/backfill + no-auto-merge-on-phone
   stand - a shared phone still never merges two people; a shared visitor id is proof of one and does.

## Consequences
Positive: where a chat person exists, chat-person == calendar-customer by construction; 26-132 can't recur;
26-133 becomes this ADR's implementation; 26-112's origin_conversation_id rides the same treatment; products
stay independent (calendar interprets nothing, starts when chat is down, needs no chat reference).
Negative (named): the event payload widens to carry name/email over the broker (reverses adr/0147's
body-free minimalism; consent wording, adr/0147's open question / 24-05, must cover name+email - legal
review); a calendar migration + backfill (email, source_visitor_id, re-keyed index; cheap now,
time-sensitive); erasure spans the keyed pair (personal-data.md records the edge); the two-owner asymmetry is
permanent (a customer with no visitor is a normal null-key state).

## Alternatives considered
- Status quo (copy per fact) - 26-132 unfixable without the key.
- Chat owns the person, calendar drops customers - customers exist without visitors; calendar owns real
  domain state; forces a cross-product read (rule 8).
- Shared/platform identity service - adr/0012 (no shared data), adr/0093/0027 platform test, rule 8.
- Merge on a matching phone - unchanged rejection (a phone is a hint; a shared visitor id is the proof).
