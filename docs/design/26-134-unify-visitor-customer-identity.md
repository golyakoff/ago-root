# 26-134 · Should visitor/customer identity be one shared resource? — design pass

## Verdict
- **Mis-application of adr/0093's "identity unifies"?** Partially — and the partial part is the bug.
  adr/0093 unified **operators** (one account-side owner, projected per product). adr/0147 then decided the
  visitor→customer boundary as **copy-by-event with no shared person key** — right on the *storage* axis
  (two tables, domains apart), wrong on the *contract* axis (a person replicated as disconnected per-fact
  events that can't be joined back to one human). 26-132's loss is the direct consequence.
- **One owner / platform service?** No. The operator recipe ("one owner + projection") does NOT transfer:
  the end-person has **two legitimate owners** — chat owns name/email/channels/history/handle; the calendar
  owns no-shows, phone-verification, notes, per-tenant lead card, merges, bookings. A customer can exist
  with **no** visitor (operator/widget booking).
- **Recommendation: HYBRID (d)** — keep both tables, unify the **person KEY** in the contract: the chat
  Visitor is the shared anchor, carried opaque across the existing outbox.

## Options (rejected, with why)
- (a) Status quo (copy per fact, manual merge) — 26-132 unfixable without a key.
- (b) Chat owns the person, calendar drops customers — false premise (customers exist w/o visitors);
  calendar owns real domain state chat must not hold; forces a cross-product read (rule 8).
- (c) Shared/platform identity service — fails adr/0012 (no shared data), adr/0093/0027 platform test, rule 8.
- (d) Shared person key + identity facts in the contract; each product keeps its own row — recommended.

## (d) concretely
1. Add VisitorId to ContactCollected (v2) — the mapper already holds detail.VisitorId and drops it. Calendar
   stores it opaque (like Operator.ExternalSubjectId) — never dereferenced (adr/0065 + adr/0012 ok).
2. Re-key the chat-sourced customer by the person: SourceContactId (per-fact id) -> SourceVisitorId; index
   (tenant_id, source_visitor_id). Name+Email+Phone events for one visitor upsert ONE row.
3. Add customers.email (+ contract field) so email has a destination.
4. The chat booking fills display_name/email from the same key instead of DisplayName: null
   (ReplyToModuleTaskHandler.cs:411) — no re-ask (26-133 decision B).
5. origin_conversation_id (26-112 C1) is the same opaque-id treatment, rides along.

Subsumes 26-133; folds the name/email half of 26-132; recorded as ADR-0183 (amends adr/0147 key+payload,
extends adr/0093 to the end-person).

## Named negatives
- ContactCollected widens to carry name/email over the broker — reverses adr/0147's body-free minimalism;
  consent wording (adr/0147 open question / 24-05) must cover name+email — legal review needed before shipping.
- Calendar migration + backfill (email, source_visitor_id, re-keyed index; backfill maps existing
  source_contact_id -> visitor). Cheap now (zero tenants), time-sensitive.
- Erasure spans the keyed pair (personal-data.md records the edge).
- Two-owner asymmetry is permanent (a customer with no visitor is a normal null-key state).

Full evidence (file:line) is in the design-pass report; the decision was drafted as ADR-0183.

---

## Round 2 (author, 2026-09-25) — hybrid REJECTED; choose between two no-copy options
The author rejected the copy/shared-key hybrid (d) and ADR-0183 outright: no duplicating person data
between products, no backfill-alignment. **One source of truth** for a person is required — a cross-product
attribute (e.g. "creditworthy") set once, seen everywhere. Also corrected: a standalone user-service is a
separate service, NOT `Ago.Platform` — adr/0012 does not forbid it (round 1 wrongly conflated the two).
Decisive input: the platform very likely will not grow past the current 2 products (maybe a 3rd, unlikely).

Re-analysis (round 2) chooses between EXACTLY two options and recommends one decisively:
- **(B)** Chat becomes the person registry; the calendar kills its `customers` copy and references chat by a
  user id, reading all person data from chat (handle: booking-only people with no chat visitor; where
  creditworthy/notes/no-shows live; rule 8 on the booking write path; migration).
- **(C)** A new standalone `user-api` service owns the person; both chat and calendar reference/read it
  (handle: rule 8 on both write paths; a 3rd deployable's cost vs the "won't grow" input; migrating both
  visitors and customers).

A later ADR records the chosen shape (supersedes ADR-0183, amends adr/0147/0093).

### Round-2 verdict (2026-09-25) — B, decisively; author accepted
Recommendation and reasoning recorded as **ADR-0184 (Accepted by the author, 2026-09-25)**: option **B**
(chat is the account's single person registry; the calendar kills its `customers` copy and references the
person by an opaque id). C loses on YAGNI + rule 8: with <=2–3 products a standalone `user-api` adds a third
deployable/DB/erasure surface while rule 8 keeps the write-gating facts (no-show, verified-phone) per-product
regardless, and it would force chat into a person<->channel **copy** to keep message routing local — the copy
the author rejected. B and C expose the identical external contract (one referenced person id, attributes read
for display), so B is C with the registry co-located in chat, and B→C stays a mechanical extraction if a
hub-less third product ever appears. The one honest bound stated in the ADR: "one source of truth for *every*
attribute" is limited by rule 8 — no-show and verified-phone remain calendar-owned operational facts, surfaced
on the person view by console-side display-merge, not relocated. **Subsumes 26-132, 26-133, 26-112 C1.**
Implementation scope (slice plan) is being drawn separately before any code starts.
