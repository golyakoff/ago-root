# Non-functional requirements and targets

These are **targets to validate**, not measurements. Nothing here may be quoted as an achievement
until Stage 7 produces a report with real numbers on named hardware. A portfolio project that claims
throughput it never measured is worse than one that claims nothing.

## Scale targets (single local cluster, 3 Api replicas, 2 Worker replicas)

| Metric | Target | Why this number |
|---|---|---|
| Concurrent WebSocket connections | 20 000 total | Enough to make per-connection memory and GC pressure visible |
| Sustained message ingest | 3 000 msg/s | Enough that per-row inserts fail and batching has to be real |
| Peak burst ingest | 10 000 msg/s for 30 s | Exercises channel backpressure instead of hiding it |
| Attachment uploads | 50/s | Presign + verify path only; bytes bypass the API entirely |
| Conversations in the waiting queue | 10 000 | Makes assignment contention measurable |

## Latency targets

| Path | p50 | p95 | p99 |
|---|---|---|---|
| Send -> ack (persisted) | 15 ms | 50 ms | 150 ms |
| Send -> delivered to a recipient on another node | 40 ms | 120 ms | 300 ms |
| History page (50 messages, keyset) | 5 ms | 20 ms | 60 ms |
| Widget handshake (cache hit) | 5 ms | 15 ms | 40 ms |
| Waiting -> assigned, queue non-empty | 100 ms | 500 ms | 2 s |

The end-to-end number carries one broker hop plus the outbox dispatch interval by design
(`realtime.md`, `messaging.md`). If it misses, the dispatcher's poll-with-notify latency is the first
suspect, not the database.

## Correctness under stress (binary, not statistical)

These either hold or the build is broken:

- Zero acknowledged-but-lost messages while killing an Api pod and a Worker pod mid-load.
- Zero out-of-order deliveries within a conversation, at any concurrency.
- Zero duplicate persisted messages despite at-least-once delivery and client retries.
- Zero operators above their configured capacity, at any assignment contention.
- Zero unbounded queues: memory stays flat under sustained overload; senders are slowed, not dropped
  silently.

## Resource budgets

- Api pod: 512 MB, 0.5 CPU at target load. Per-connection memory is a tracked metric, since it is
  what decides the connection ceiling.
- Worker pod: 512 MB, 1 CPU.
- Postgres connections: pooled, ceiling well below the server max, with the pool exhaustion path
  tested (it must queue and time out cleanly, not deadlock).

## Availability behaviour

Not an uptime SLA - this is a demo cluster. What matters is the documented degradation path in
`realtime.md`: which dependency failure degrades, which rejects, and which is allowed to lose data
(only Redis, and only ephemeral data).

## Observability requirements

Everything above must be visible without attaching a debugger:

- RED metrics per endpoint, hub method, and consumer.
- Queue depth, channel occupancy, batch size histogram, outbox lag, DLQ count.
- Cache hit ratio per key namespace, breaker state.
- Connection count per node, assignment attempts vs conflicts.
- Traces spanning hub -> handler -> DB -> outbox -> broker -> consumer -> delivery, one trace id
  end to end. This is what makes the p95 numbers explainable instead of merely reportable.
