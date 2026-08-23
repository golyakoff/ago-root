# OpenTelemetry tracing: one trace id, hub to delivery

- **Stage**: 7
- **Status**: ready
- **Depends on**: nothing — instruments already-shipped code (Stages 1-4); the webhook dispatcher
  (`6-05`) is not on the traced path `roadmap.md` names for this item, so it is not a prerequisite

## Goal

After this, sending a message emits one W3C trace spanning `VisitorHub`/`OperatorHub` method entry,
the Application handler, the Postgres write (message + outbox row, one transaction), the outbox
dispatcher's publish, the RabbitMQ consumer that receives it, and the SignalR push to the recipient's
connection — visible in Jaeger as one trace by trace id, not reconstructed by hand from five separate
logs. This is `roadmap.md`'s Stage 7 first deliverable and the literal path named in `nfr.md`'s
Observability requirements: "Traces spanning hub -> handler -> DB -> outbox -> broker -> consumer ->
delivery, one trace id end to end."

## Context to read first

`concurrency.md`'s in-process pipeline diagram and "What we will measure" section; `messaging.md`'s
delivery guarantees; `realtime.md`'s node fan-out steps (this is the last hop the trace must reach);
`nfr.md`'s Observability requirements (the trace bullet this item satisfies) and Latency targets table
— this is what a trace makes *explainable* rather than merely reportable, per `resilience.md`'s "How
this is proven" section. `naming-and-structure.md`'s `ago-platform` layout already earmarks
`Ago.Platform.Hosting/ IProductModule, health checks, OpenTelemetry, config binding` — the shared
bootstrap belongs there, once, not duplicated per host. `CLAUDE.md`'s Stack line already decided the
trace backend: "OpenTelemetry → Prometheus/Grafana/Jaeger" — Jaeger is not an open question here.

## Scope

- `Ago.Platform.Hosting`: an `AddPlatformObservability(...)` extension wiring the OTel SDK's tracing
  provider — ASP.NET Core instrumentation, Npgsql instrumentation, `HttpClient` instrumentation (this
  also means any outbound call `Ago.Chat.Webhooks` later makes, once `6-05` exists, is automatically
  traced with no extra work here — a side effect worth stating, not a reason to build webhook-specific
  spans now). Resource attributes (`service.name`, `service.version`, `deployment.environment`) so all
  three hosts' spans are distinguishable and correlatable in one Jaeger UI. One call from every host's
  `Program.cs` (`Api`, `Worker`, `Webhooks`).
- Manual `ActivitySource`/spans where instrumentation packages can't see: hub method entry
  (`VisitorHub.SendMessage` etc.), the outbox dispatcher's publish step, each broker consumer's
  message-processing span, the node-delivery push to a SignalR connection — named consistently
  (`ago.chat.hub.send_message`, `ago.chat.outbox.dispatch`, …) so a reviewer reading Jaeger's span list
  understands the pipeline without reading source first.
- Trace context propagation through the outbox and the broker: the trace id captured at the write must
  survive the poll-and-publish handoff (a new activity, parented to the original — a link, not a fresh
  root) and RabbitMQ message headers must carry `traceparent` (W3C Trace Context) so the consumer's
  span is a real child, not a same-time coincidence.
- OTLP exporter, endpoint driven by config (`Otel:Exporter:Endpoint`), pointed at Jaeger locally
  (deploying the actual Jaeger container is `7-03`'s job — this item's own tests use an in-memory span
  exporter, not a live Jaeger).
- ADR (`adr/00XX`): the export shape — direct OTLP-to-Jaeger from each host, no collector, vs. an OTel
  Collector in between. State the choice and why (`resilience.md`'s own "no service mesh, keep
  mechanisms visible" instinct argues for the simplest shape that still works standalone; a collector
  earns its place once there's more than one telemetry backend to fan out to, which there isn't yet) —
  a well-understood default, stated and moved past, not surveyed at length.

## Out of scope

- Metrics (RED, queue depth, etc.) — `7-02`.
- Actually deploying Jaeger/Prometheus/Grafana — `7-03`. This item's Done-when is provable against an
  in-memory span exporter in a test, not a running Jaeger.
- Sampling strategy tuning (head vs. tail, ratio) — ships always-on for now (a demo cluster, not
  production volume). If trace volume turns out to matter, that surfaces in `7-06`'s report, not as a
  decision pre-made here.

## Done when

- [ ] An integration test (Testcontainers: Postgres + RabbitMQ, real `Ago.Chat.Api` + `Ago.Chat.Worker`
      hosts) sends one message and asserts every span in an in-memory exporter shares one trace id, in
      the right hub → handler → DB → outbox → broker → consumer → delivery order (by span kind/name,
      not just count).
- [ ] `Ago.Platform.Hosting`'s new extension has its own unit tests (resource attributes set correctly,
      config binding validated at startup like every other options class in this codebase).
- [ ] `adr/00XX` written and accepted.
- [ ] `CHANGELOG.md` entry and version bump in `ago-platform` (new public API in `Ago.Platform.Hosting`).
- [ ] `nfr.md`'s Observability requirements trace bullet can be checked off with a link to the test
      above, not left as an assertion.

## Open questions

None — Jaeger as the trace backend is already decided (`CLAUDE.md`'s Stack section); the
collector-vs-direct question is this item's own ADR to make, following the same "state a well-understood
default and move on" pattern `6-03` used for its signature scheme.
