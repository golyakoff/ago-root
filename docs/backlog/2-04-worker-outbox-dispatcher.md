# Ago.Chat.Worker: the outbox dispatcher, for real

- **Stage**: 2
- **Status**: ready
- **Depends on**: `2-02-chat-outbox-wiring.md`, `2-03-rabbitmq-adapter.md`

## Goal

`Ago.Chat.Worker` stops being a health-check shell. Rows that `2-02` has been quietly accumulating in
`outbox` since it landed start actually reaching RabbitMQ, published exactly once per row from the
dispatcher's perspective (at-least-once overall, per `adr/0005`), safe with multiple `Worker` replicas
running the same loop concurrently.

## Context to read first

`docs/architecture/messaging.md`'s "Outbox dispatcher" section (`SKIP LOCKED`, poll-plus-notify, why
not a naive fixed poll), `docs/architecture/concurrency.md` (`BackgroundService` rules - catches and
continues, `PeriodicTimer` not `System.Timers.Timer`, graceful shutdown sequence), `docs/adr/0005`.

## Scope

- `OutboxDispatcher : BackgroundService` in `Ago.Chat.Worker`: claims a batch of unpublished rows with
  `SELECT ... FOR UPDATE SKIP LOCKED`, publishes each via `IEventPublisher` (`2-03`'s adapter,
  injected - the Worker's DI wiring is the only place a concrete adapter is chosen, same seam as
  `Ago.Chat.Module`), marks `published_at` on success within the same claim.
- **Poll-plus-notify**: a Postgres `LISTEN`/`NOTIFY` channel that `2-02`'s outbox insert path notifies
  on (or a lightweight trigger - implementer's choice, document whichever in the PR), so the dispatcher
  wakes immediately on a new row instead of waiting out its poll interval; the poll interval remains as
  a fallback for missed notifications, not the primary mechanism (`messaging.md` is explicit this is
  the reason for poll-plus-notify over a naive fixed poll).
- A row that fails to publish keeps its `attempts` counter incrementing and is retried on the next
  claim, not permanently skipped - dead-lettering the *outbox* row itself is out of scope here (the
  broker-side DLQ from `2-03` is a different, already-covered failure path; an outbox row that cannot
  even reach the broker is a `resilience.md`-flagged condition worth a metric in Stage 7, not new
  behaviour now).
- Graceful shutdown: `ApplicationStopping` stops claiming new batches, lets an in-flight batch finish
  publishing, then stops - per `concurrency.md`'s shutdown sequence.
- `Ago.Chat.Worker`'s health check gains a real readiness signal (can it reach Postgres and RabbitMQ),
  replacing the trivial always-healthy check from `0-03`.

## Out of scope

- Any consumer - this item is the publish side only. Nothing subscribes to what this dispatcher sends
  until `2-05`.
- Multiple dispatcher replicas under load, proven with numbers - Stage 7. This item proves correctness
  (no double-publish, no lost row) with a small integration test, not throughput.
- Outbox row pruning - not committed to by any stage yet (see `2-01`'s note).

## Done when

- [ ] `Ago.Chat.Integration.Tests`: an outbox row written by `2-02`'s handler path is published to
      RabbitMQ and marked `published_at`, observed end-to-end (real Postgres + real RabbitMQ
      Testcontainers, no mocking the broker).
- [ ] Two dispatcher instances (two `BackgroundService` instances against the same Postgres) racing to
      claim the same batch: a test asserts no row is published twice and no row is left unclaimed -
      `SKIP LOCKED` doing its job under real concurrency, not asserted from reading the SQL.
- [ ] A test kills the RabbitMQ container mid-batch and restarts it; asserts every row eventually
      reaches `published_at` with no duplicate publish and no row stuck unpublished - this is the
      roadmap's literal "kill the dispatcher mid-batch" done-when for Stage 2.
- [ ] LISTEN/NOTIFY wake-up is proven with a test asserting dispatch latency after a fresh insert is
      much closer to zero than the fallback poll interval, not just "it eventually happens."
- [ ] `docs/runbooks/local-dev.md` gains the command to run `Ago.Chat.Worker` locally, verified by
      running it.

## Open questions

None.
