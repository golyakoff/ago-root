# 25-44 · `Ago.Calendar.Worker` has no `OutboxDispatcher` at all

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-10, while building `23-88`'s `ago-calendar` half — the new
  `ModuleQuantityImpactComputed` reply staged correctly to the outbox table, proven against a real
  Postgres, and the worker building it went looking for what drains that table to RabbitMQ before
  reporting the item done.

## What is actually true

`Ago.Chat.Worker` has `OutboxDispatcher`, wired and running. `Ago.Calendar.Worker` does not — there is
no dispatcher class anywhere in that host, confirmed by grepping the whole `ago-calendar` repository.
`docs/architecture/messaging.md` already carried an honest hint of this and nobody had followed it up:
`BookingConfirmed`'s own consumer row has said **"None wired yet"** since `20-04`.

The consequence is not cosmetic. Every row `Ago.Calendar.Worker` stages to its own `outbox` table —
`BookingConfirmed` today, `ModuleQuantityImpactComputed` (`23-88`/`adr/0165`) as of this session —
commits correctly inside its own transaction and then **sits there forever**. Nothing publishes it to
the broker, so nothing downstream ever fires: `20-05`'s SMS delivery (itself unbuilt, per the same
"None wired yet" note) would have nothing to consume even once built, and chat's own worker-quota
impact preview (`23-88`) will show "asked, not yet answered" on every real deployment, permanently,
regardless of how correct the `ago-chat`/`ago-calendar` code on both sides of that question is.

## Why this sat unnoticed

`Ago.Calendar.Worker` has real, working hosted services — `ContactCollectedConsumer`, and now (`23-88`)
`ModuleQuantityImpactRequestedConsumer` — so the host is not idle, and nothing about running it looks
broken. A dispatcher's absence produces no error, no failed health check, no stack trace: it produces
silence, in a table nobody was looking at, for events nothing downstream has needed yet. `20-04`'s own
"None wired yet" was written the day `BookingConfirmed` shipped and never revisited once a second
outbox writer (`23-88`) made the gap block a real feature rather than a placeholder for one.

## Scope

- Build `Ago.Calendar.Worker`'s own outbox dispatcher — same shape `Ago.Chat.Worker.OutboxDispatcher`
  already establishes (poll the outbox table, publish unpublished rows to the broker, mark published),
  not a new design.
- Prove it against both real rows this product already stages: `BookingConfirmed` and
  `ModuleQuantityImpactComputed`.
- Update `docs/architecture/messaging.md`'s own "None wired yet" note and the paragraph this session
  added about the missing dispatcher, once it no longer applies.

## Where this is likely to go wrong

- **This is not `23-88`'s own gap to close**, and was correctly left out of that item's own scope —
  `23-88`'s promise is the async question-and-answer mechanism between the two products, which is
  fully built and correctly proven at the outbox-row level; whether a product's own outbox ever
  reaches its own broker is a separate, pre-existing fact about `ago-calendar` that predates `23-88`
  by five stages.
- **Don't scope this narrowly to just the new topic.** `BookingConfirmed` has had the identical problem
  since `20-04`; fixing the dispatcher fixes both at once, and scoping to only the new topic would
  leave a known, already-named gap sitting right next to the one just closed.

## Done when

- [ ] `Ago.Calendar.Worker` runs an outbox dispatcher that publishes staged rows to the broker.
- [ ] A test proves a `BookingConfirmed` row and a `ModuleQuantityImpactComputed` row, both staged via
      the normal code path, are actually delivered — not just committed to Postgres.
- [ ] `docs/architecture/messaging.md`'s "None wired yet" note and this session's "no `OutboxDispatcher`
      yet" paragraph are corrected or removed, matching what is actually true after this lands.
