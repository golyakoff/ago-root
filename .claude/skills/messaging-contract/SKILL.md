---
name: messaging-contract
description: Add or change an integration event, publisher, or consumer in AGO Platform - contracts, versioning, outbox publishing, idempotent consumption, retries and dead-lettering. Use whenever something must be published to or consumed from the broker.
---

# Adding or changing an integration event

Authoritative sources: `docs/architecture/messaging.md`, `adr/0005`, `adr/0006`.

## 1. Define the contract

In `Ago.Chat.Contracts` (never in Domain, never in Application):

- A `record`, named as a past-tense fact: `MessageAccepted`, `ConversationAssigned`.
- Carries `MessageId` (idempotency key), `OccurredAt` (UTC `DateTimeOffset`), `SiteId`,
  `CorrelationId`, plus identifiers and only the payload a consumer cannot cheaply look up.
- Never contains a domain entity. Mapping domain event to contract happens in Application, so that
  refactoring an aggregate is not a breaking wire change.
- **Never contains a message body, and never contains anything else about a person that the event's
  ids do not already imply.** This is a privacy property, not only a size one (`messaging.md`,
  `personal-data.md`): `outbox.payload` is a table nothing prunes, so whatever a contract carries is
  retained indefinitely. A field that adds personal data to a contract is additive on the wire and
  load-bearing for erasure - say so in the change, and add the row to `personal-data.md` in the same
  commit.

## 2. Version it correctly

Additive only: a new **optional** field is fine. Renaming or removing a field, or changing a type or
meaning, is breaking - publish `V2` alongside `V1` until every consumer has moved. Consumers ignore
unknown fields. Write the version into the envelope, not into a guess based on shape.

## 3. Publish through the outbox

Never publish from a request handler. In the same transaction as the state change, write the outbox
row with `type`, `payload`, and `partition_key`. The dispatcher does the rest.

**Partition key is a design decision, not a formality:** it determines ordering scope. Anything about
one conversation uses `conversation_id`. Getting this wrong silently breaks the ordering guarantee -
and only under load.

## 4. Write the consumer

- Declare the subscription: topic, `Competing` (work split across replicas) or `Broadcast` (every
  node must see it, e.g. cache invalidation), retry policy, DLQ.
- Record `MessageId` in the `inbox` table inside the same transaction as the work. Duplicate means
  skip and ack.
- Be safe to run twice regardless of the inbox: prefer upserts and unique constraints.
- Honour cancellation; ack only after the work is durably done.
- Handle poison messages: N attempts with exponential backoff, then dead-letter with the full
  envelope and the last exception. Add the DLQ alert and a runbook line - a silent DLQ is a data-loss
  channel with extra steps.

## 5. Test it

- Application unit test with a fake publisher: asserts the outbox row and the mapped contract.
- Integration test with a real broker: publish, consume, assert the effect; then deliver the same
  message twice and assert the effect happened once.
- If ordering matters, add the ordering test with the partition key under parallel consumers.

## Checklist

- [ ] Contract is a past-tense fact with idempotency key and UTC timestamp.
- [ ] Change is additive, or a new version exists alongside the old.
- [ ] Published via outbox in the state-change transaction.
- [ ] Partition key chosen deliberately and stated in the response.
- [ ] Consumer is idempotent, cancellable, and dead-letters after bounded retries.
- [ ] Nothing in `messaging.md` is now wrong.
