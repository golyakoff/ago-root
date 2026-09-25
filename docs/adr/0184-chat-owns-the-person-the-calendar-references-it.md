# ADR-0184: chat owns the person; the calendar references it, and keeps no copy

- **Status**: Accepted (author, 2026-09-25) — chose option B over a standalone `user-api` (option C).
  Implementation follows via the 26-13x slices scoped from this decision; the code still carries
  adr/0147's copy until those land.
- **Date**: 2026-09-25
- **Stage**: 26
- **Supersedes**: ADR-0183 (rejected by the author — it kept a per-product copy). **Supersedes** the
  person-replication core of ADR-0147 (the `ContactCollected -> calendar customer` copy and its
  no-auto-merge/backfill machinery; the calendar no longer holds a customer to replicate into). **Extends**
  ADR-0093's identity-unification from the operator to the end-person. Does not weaken ADR-0012 (no new
  platform coupling; chat is a product) or ADR-0065 (the calendar still interprets nothing chat sends — it
  carries an opaque person id).

## Context
adr/0093 unified operator identity (one account-side person, projected per product) and tenancy (account id
= site id = tenant id); it did not reach the end-person. adr/0147 then decided the visitor->customer boundary
as a **copy**: chat publishes `ContactCollected`, the calendar builds its own `Customer`. That copy is the
source of 26-132's data loss and of duplicate people. The author rejected copying person data between
products, and rejected the round-1 hybrid (adr/0183) that kept the copy with a shared key.

Author's requirement: **one source of truth per person.** An operator marks a person "creditworthy" once;
it is visible everywhere; nothing about the person is duplicated across products.

Two forces constrain the answer. **Rule 8** forbids a write decision reading a remote service or a cache:
the calendar already gates booking writes on **verified-phone** and (per 20-04) on **no-show history**, so
those facts must stay in the calendar's own database. And the platform ships as NuGet (adr/0012): the person
cannot live in `Ago.Platform.*`.

A standalone person service (`user-api`) and "chat is the registry" were both weighed. Chat is already the
account's person and cross-channel hub (adr/0065, Stage 14). The suite is unlikely to exceed two products.

## Decision
**Chat owns the Person as the account's single person registry. The calendar holds no person copy — it
references the person by an opaque id and stores only the booking-domain and write-gating facts rule 8
requires it to own.**

1. **Chat's `Visitor` is elevated to the account-scoped `Person`** — one identity for everyone in the
   account, chat-originated or not. It owns the advisory, any-console-settable cross-product attributes:
   display name, contact channels, **creditworthy**, reliability, operator **notes about the person**, and
   **merge** (moved here from the calendar's 23-60).
2. **Every person has one id.** A person chat has seen already has one. A booking with a chat origin reuses
   it. A booking with **no** chat origin (operator-entered, public widget) mints a person id **locally in
   the calendar**, attaches it to the `Event`, and publishes `PersonRegistered{personId, accountId, phone,
   name}`; chat consumes it and creates the Person. **No synchronous cross-service call on any write path.**
3. **The calendar deletes `customers` as a person store.** It keeps `Event.person_id` and a thin
   operational record — **no-show count** and **verified/confirmed-phone** — keyed by person id, because the
   calendar generates these and gates booking writes on them (rule 8). They are surfaced on the person view
   by display, not relocated.
4. **Reads are display-only and console-side.** ago-console reads the Person from chat's API and the
   bookings from the calendar's API and merges them (adr/0093's "one console, each screen talks to the
   owning product"). No server-to-server person read exists.
5. **`ContactCollected -> customer` replication is removed.** A chat contact updates chat's own Person; the
   calendar stops consuming it for customer creation.

## Consequences
**Positive.**
- One person, one id, one home for advisory attributes; "creditworthy set once, visible everywhere" holds by
  construction, with **no copy**.
- 26-132/26-133 dissolve: a chat-origin booking already carries the person id, so name/email are simply read
  from the Person; there is no cross-boundary drop to fix.
- The products stay independent on the write path: a booking completes with chat down (local mint + queued
  event); chat routes messages with the calendar down.
- The external contract (one referenced person id, attributes read for display) is **exactly** what a future
  standalone `user-api` would expose, so B->C is a mechanical extraction if a hub-less third product ever
  appears — this decision does not foreclose it.

**Negative, named rather than implied.**
- **"One source of truth for every attribute" is bounded by rule 8.** No-show and verified-phone stay
  calendar-owned operational facts; they appear on the person view by display-merge, not relocation. Inherent
  to rule 8, identical under a standalone service.
- **Chat carries two roles in one deployable** (support chat + person registry). They already overlap; the
  cost is conceptual, not a runtime coupling on any write path.
- **`Visitor -> Person` is a rename** touching many call sites. Following adr/0093's Site->Account precedent,
  the rename is deferred/optional; the concept is elevated regardless.
- **Calendar person-display depends on chat's Person API being reachable** — a display GET, not a write, not
  rule 8; degrades to "name not shown yet", never to a failed booking.
- **Migration and erasure change shape.** `customers` folds into person references (cheap now — zero
  tenants); person erasure deletes one Person in chat and cascades the calendar's operational record + events
  by id. `personal-data.md` must be rewritten to this two-store, one-identity shape.
- **A brief eventual-consistency window** between a locally-minted person id on a booking and the Person
  appearing in chat. The id is the durable truth; the profile catches up (same at-least-once/idempotent
  posture as the rest of the system).

## Alternatives considered
- **ADR-0183 hybrid (shared key, per-product copy).** Rejected by the author: still copies person data, needs
  backfill-alignment.
- **A standalone `user-api` (option C).** Rejected on YAGNI + rule 8: with <=2-3 products it adds a third
  deployable, database and erasure surface while rule 8 keeps write-gating facts per-product anyway, and it
  forces chat into a person<->channel **copy** to keep message routing local — the copy the author rejected.
  Right only for a multi-product suite with no natural hub, which chat already is. Reachable later without
  changing this decision's contract.
- **adr/0147's copy, kept.** Rejected: the status quo whose duplication and 26-132 loss prompted this.
- **Auto-merge on matching phone.** Still rejected (adr/0147's reasoning stands): a phone is a hint, a wrong
  merge is a disclosure. Merge stays a deliberate operator act, now on the Person registry.
