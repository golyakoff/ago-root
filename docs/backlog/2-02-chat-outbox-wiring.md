# Ago.Chat: outbox table, MessageAccepted contract, handlers write in the same transaction

- **Stage**: 2
- **Status**: done - built and tested against `2-01`'s code via the `AgoPlatformDevOverride`
  ProjectReference path (`2-01` is not yet merged/packed on `ago-platform`'s `main`, per
  `repositories.md`'s documented dev-override workflow - CI will only go green here once `2-01`
  lands). `Ago.Chat.Domain.Tests` 30/30, `Ago.Chat.Application.Tests` 27/27 (including two new
  fake-outbox tests proving each handler enqueues exactly one `MessageAccepted` envelope keyed by
  conversation id), `Ago.Chat.Architecture.Tests` 13/13, `Ago.Chat.Integration.Tests` 12/12 against a
  real `docker-compose` Postgres (including the two new tests below). `dotnet format
  --verify-no-changes` clean.
- **Depends on**: `2-01-platform-outbox-inbox-and-messaging-port.md`, `1-02-application-use-cases.md`,
  `1-04-postgres-persistence.md`

## Goal

Sending a message durably records the fact that it must be published, in the same database
transaction as the message itself - provable by killing the process the instant after the client is
acked and finding the outbox row still there on restart. No broker involved yet: this item proves the
"never lose an acknowledged write" half of `adr/0005` on its own, independent of whether anything is
actually publishing.

## Context to read first

`docs/architecture/messaging.md` (event contract rules, the `MessageAccepted` row in the topics
table), `docs/architecture/data-model.md` (`outbox` table shape, partial index), `2-01`'s ADR-0017
once written, `docs/conventions/naming-and-structure.md` (`Ago.Chat.Application/Mapping/` - where
domain-event-to-contract mapping lives).

## Scope

- `Ago.Chat.Contracts`: `MessageAccepted` record - `MessageId`, `OccurredAt`, `SiteId`,
  `CorrelationId` (per `messaging.md`'s "every event carries" rule) plus `ConversationId`,
  `AuthorKind`, `Sequence`. No message body - a consumer that needs it reads `GetConversationHistory`;
  the payload stays small (`messaging.md`).
- `Ago.Chat.Application/Mapping/`: the domain event (`MessageAdded` or equivalent already raised by
  `Conversation` in `1-01`) to `MessageAccepted` mapping. This is Application code, not Domain -
  Domain must not know `Ago.Chat.Contracts` exists (`clean-architecture.md`).
- Wire `SendVisitorMessageHandler` and `SendOperatorMessageHandler` (`1-02`) to call `IOutboxWriter`
  with the mapped event, right after the domain call and before the existing
  `conversations.SaveAsync(...)` - so the existing single `SaveChangesAsync` inside it persists both
  the message and the outbox row atomically, with no new transaction code written.
- EF migration adding the `outbox` **and** `inbox` tables (`Stage2AddOutboxAndInbox`, per
  `data-model.md`'s `<Stage><Verb><Subject>` convention), using `2-01`'s combined
  `ApplyOutboxInboxConfiguration()` as a single call rather than splitting it back into two - the
  point of `adr/0017`'s combined helper was one two-line opt-in per product, and fighting that to keep
  `inbox` strictly out of the database until `2-05` would cost more (a second migration, a second call
  site) than it buys (an unused empty table for one stage). `inbox` gets no *writer* until `2-05` -
  that half of the original scope note still holds, only the table's existence moved earlier.
- `AgoChatDbContext`: register `Ago.Platform.Persistence.Postgres`'s shared outbox configuration
  (however `2-01`'s ADR shapes that composition) and register `EfOutboxWriter<AgoChatDbContext>` for
  `IOutboxWriter` in `Ago.Chat.Module`'s DI wiring - this is the one place a concrete `DbContext` type
  is allowed to meet the generic platform writer (`Ago.Chat.Module` is Host-adjacent DI wiring, per
  `clean-architecture.md`).

## Out of scope

- `StartConversation` does not get its own outbox event - `messaging.md`'s topics table names no event
  for it, and inventing one with no consumer would be exactly the premature generalisation
  `CLAUDE.md` warns against. `MessageAccepted` already covers a conversation's first message.
- Actually publishing anything - no broker, no dispatcher. The `outbox` table will accumulate
  unpublished rows after this item lands, which is correct and expected until `2-04`.
- Consumer-side dedup - the `inbox` table exists after this item (see Scope above) but nothing
  writes to it; no consumer exists until `2-05`.

## Done when

- [x] `Ago.Chat.Integration.Tests` (real Postgres, Testcontainers): sending a message writes exactly
      one `messages` row and one `outbox` row with a matching `MessageId`, in one transaction - proven
      by asserting both exist after the handler returns, not by inspecting the transaction API
      directly (`testing.md`: assert observable behaviour, except where the schema *is* the guarantee).
- [x] A test proves a handler exception *before* the domain call leaves neither row persisted (no
      partial write).
- [x] `Ago.Chat.Application.Tests`: the mapping from domain event to `MessageAccepted` is unit-tested
      with fakes, independent of Postgres.
- [x] `Ago.Chat.Architecture.Tests` green - `Ago.Chat.Domain` still references nothing from
      `Ago.Chat.Contracts` or `Ago.Platform.Abstractions` (`MessageAdded` stays a plain
      `IDomainEvent` record; the mapping to `MessageAccepted` lives in `Application`, never `Domain`).
- [x] `docs/architecture/data-model.md` updated to mark `outbox` as real, not just planned shape,
      matching how `1-04` closed out the rest of the schema.

## Open questions

None.
