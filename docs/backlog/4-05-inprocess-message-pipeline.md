# In-process message pipeline: bounded channel, batch writer, ConversationSequencer

- **Stage**: 4
- **Status**: ready
- **Depends on**: nothing from `4-01`-`4-04` (orthogonal hot path); sequenced last in this stage so
  it does not stack a second large architectural change onto the same files `4-01`-`4-04` are not
  touching but a reviewer would still be tracking two big changes in flight at once

## Goal

`concurrency.md`'s "In-process pipeline (Api)" diagram, built for real: a hub method enqueues onto a
bounded `Channel<InboundMessage>` instead of writing straight to Postgres inline, N pipeline workers
drain it, a batch writer accumulates rows and does one multi-row insert instead of one round trip per
message, and a `ConversationSequencer` guarantees two messages of the same conversation are never
processed concurrently even when multiple pipeline workers are running. The caller (the hub method
that queued the message) still gets its ack back through a `TaskCompletionSource`, so the wire
contract visitors/operators see does not change - only what happens between "hub method called" and
"row committed."

## Context to read first

`concurrency.md`'s "In-process pipeline (Api)" and "Per-conversation ordering under parallel
consumers" sections in full - this item builds exactly what is diagrammed there, including the
`ConcurrentDictionary<ConversationId, Channel>` per-conversation sequencing shape named in point 2.
`SendVisitorMessageHandler`/`SendOperatorMessageHandler` (`Ago.Chat.Application/UseCases/SendMessage/`)
as they stand today - **read these fully before starting**: they currently do rate-limit check,
conversation load, domain mutation, one `SaveChangesAsync`, and the local-echo `SendAsync`, all
inline, synchronously, one message at a time. This item does not remove any of that logic - it changes
*when* the Postgres write happens (batched, off a queue) without changing what is written or the
guarantees around it (`adr/0005`'s outbox-in-the-same-transaction rule still applies to the batch
write, not just to a single-row write). `docs/conventions/testing.md` for what a concurrency test at
this level looks like.

## Scope

- `Channel<InboundMessage>` (`BoundedChannelFullMode.Wait`, capacity from config) that
  `VisitorHub.SendMessageAsync`/`OperatorHub.SendMessageAsync` write to instead of calling
  `SendVisitorMessageHandler`/`SendOperatorMessageHandler` directly and awaiting a database round
  trip inline. The rate-limit check and permission check stay where they are and run *before*
  enqueueing (cheap checks, no reason to hold a queue slot for a request that was always going to be
  rejected) - only the Postgres write and outbox insert move into the pipeline.
- N pipeline workers (`BackgroundService`s, count from config), each reading from the channel.
- `ConversationSequencer`: per-conversation single-flight, exactly as `concurrency.md` describes for
  the broker-consumer case (`3-02`'s per-conversation ordering) but applied here to the in-process
  queue instead - two messages for the same `ConversationId`, even dequeued by different workers,
  must never be written concurrently. Entries evicted on idle (bound memory - a
  `ConcurrentDictionary` that only grows is a bug this project's own conventions call out explicitly).
- Batch writer: accumulates up to `N` rows or `T` milliseconds, whichever comes first
  (`concurrency.md`'s own description), then one multi-row insert. The outbox row for each message
  still commits in the *same* database transaction as that message's insert (`adr/0005` does not
  relax for batching - a batch is still one transaction covering every row plus every row's outbox
  entry, or it is not safe to call this a batch write at all).
- The caller's ack: a `TaskCompletionSource<Result<int>>` (or equivalent) created when the hub method
  enqueues, completed by the pipeline worker once the batch commits (or fails) - the hub method awaits
  it and returns exactly what it returns today, so `VisitorHub`/`OperatorHub`'s public contract is
  unchanged.
- Backpressure (author's decision): a full channel means the hub method's `await
  channel.WriteAsync(...)` blocks up to a configured timeout, then returns a failure `Result` to the
  caller (visitor/operator sees an explicit "try again" outcome, matching this project's existing
  rate-limit-rejection shape, rather than either an unbounded wait or a silent drop) - not an
  unbounded wait, and not an immediate reject with zero grace.
- Config: worker count, channel capacity, batch size/interval - stated as unmeasured starting points
  (`CLAUDE.md`), same as every other tuning knob this stage introduces.

## Out of scope

- Anything about *which* conversation gets an operator - `4-01`-`4-04`, unrelated concern (this item
  is entirely about message ingest throughput and ordering, not assignment).
- Changing the wire contract (method names, return shapes) `VisitorHub`/`OperatorHub` expose - the
  pipeline is invisible from outside the process.
- Batch-size/throughput numbers as a performance claim - Stage 7 measures and reports them
  (`CLAUDE.md`: "do not invent numbers... measure or stay silent"); this item only needs the
  mechanism to exist and be correct under load, not a stated number for how much faster it is.

## Done when

- [ ] `Ago.Chat.Concurrency.Tests`: K messages fired from M threads into one conversation through the
      pipeline - the persisted `sequence` is a gap-free ascending run, repeated under stress
      (`concurrency.md`'s own test description, applied to the new pipeline instead of the broker
      consumer it originally described).
- [ ] A test proving the batch writer actually batches - e.g. asserting fewer round trips / fewer
      transactions than messages sent, under concurrent load, not just correctness of the end state.
- [ ] A backpressure test: filling the bounded channel causes the documented behaviour (block with
      timeout, or reject) rather than unbounded growth or a silent drop.
- [ ] A shutdown test: messages already queued when `ApplicationStopping` fires are drained and
      committed (or the caller's `TaskCompletionSource` is failed cleanly) before the host stops -
      matching `concurrency.md`'s "drain the pipeline channel -> flush the batch writer" shutdown
      step, which this item is what makes real for the first time (today there is no pipeline to
      drain).
- [ ] `docs/architecture/concurrency.md`'s "In-process pipeline (Api)" section gets a "Shipped in
      `4-05`" note with the actual worker count/batch config chosen.

## Open questions

None - the author confirmed block-with-timeout, stated in Scope.
