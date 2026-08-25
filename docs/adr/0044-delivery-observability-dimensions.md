# ADR-0044: Delivery is dimensioned by recipient kind and presence, and the platform reports facts rather than metrics

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 7 (`7-08`)

## Context

On 2026-08-25 an operator reported that a message they sent reached the visitor and never appeared in
their own thread. Answering "did the server even try to deliver it to that operator's connection"
should have taken a minute. It took an hour, because nothing in the running system could answer it:
the fan-out path recorded no count of recipients resolved, no count of connections found, and no
count of dispatches that met a live connection. The cause turned out to be client-side (`5-16`),
which is exactly the point — the fastest way to establish that was to rule out the server, and there
was no way to rule out the server.

Two forces make this harder than "add a counter":

- **Zero deliveries is usually normal.** A visitor who closed the tab has no connections, and fanning
  out to nobody is the expected outcome many times a day. A raw "delivered to zero" counter would be
  noise, and an alert on it would be worse than nothing — `15-03`'s own failure mode, where a rule
  nobody can act on trains its reader to ignore the next one.
- **The dimension that makes the number useful is a product concept.** "A visitor with no connection
  is ordinary, an operator with none is not" cannot be said in `Ago.Platform.*`, which is not allowed
  to know that visitors or operators exist (`clean-architecture.md`'s qualifying rule). But the
  connection counts only exist inside `Ago.Platform.Realtime.NodeFanoutPublisher`, and the
  per-connection dispatch outcome only exists inside the host's own `ILocalConnectionDispatcher`.

`7-07`, written from the same investigation, is the standing warning next to all of this: the
connections gauge counted `RegisterAsync` calls, and that method is also the heartbeat's TTL refresh,
so an instrument that counted the wrong event looked exactly like one that counted the right event
for as long as the heartbeat had existed. Whatever is added here has to be checkable against every
path that calls it.

## Decision

**1. The platform reports facts; the product names them.**

`INodeFanoutPublisher.PublishAsync` returns a `FanoutResult` — each recipient it was given and how
many live connections the registry had for them — instead of recording a metric itself.
`Ago.Chat.Application.Realtime.FanoutObservability` turns that into
`ago.chat.delivery.recipients`, tagged in chat's own vocabulary.

**2. The delivery instrument is dimensioned by recipient kind × presence, not by a raw count.**

`ago.chat.delivery.recipients` carries three tags: `method` (`MessageReceived` /
`ConversationAssigned`), `recipient_kind` (`visitor` / `operator` / `unknown`), and `presence`
(`connected` / `absent`, meaning "the registry had at least one live connection for them at fan-out
time"). One point per recipient per fan-out. `operator` + `absent` is the interesting series;
`visitor` + `absent` is a normal Tuesday. Both are counted, so the ratio between them is readable
rather than assumed.

**3. The per-connection outcome comes from the dispatcher itself.**

`ILocalConnectionDispatcher.DispatchAsync` returns a `DispatchOutcome` (`Delivered` /
`ConnectionNotLocal`), and `NodeDeliveryConsumer` records `ago.platform.realtime.dispatches`, tagged
`node` and `outcome` (`delivered` / `connection_not_local` / `failed`). Delivery behaviour does not
change: every delivery is still acknowledged regardless of outcome, and an unreachable connection is
still a harmless no-op (`realtime.md`, `adr/0009`).

**4. No alert.** `15-03` decides that later, with real data, rather than as a guess made while adding
the instrument.

## Consequences

- The question that started this is answerable in three reads: was the operator a resolved recipient
  at all (`ago.fanout.recipients` on the trace), was the registry aware of a connection for them
  (`recipient_kind=operator, presence=connected`), and did the node it named still hold that
  connection (`outcome=connection_not_local` for that node). Proven end to end by
  `Ago.Chat.Integration.Tests.DeliveryObservabilityEndToEndTests`, which reproduces the incident's
  own shape and answers it from telemetry alone.
- Two breaking changes to a published package (`0.17.0`): both port signatures gain a return value.
  `PublishAsync`'s is source-compatible for callers that simply `await` it; implementors — mostly
  test doubles — change. This is the cost of putting the number where the decision is made rather
  than inferring it beside the call.
- `Ago.Chat.Application` now calls `System.Diagnostics.Metrics` directly, through
  `Ago.Chat.Contracts.ChatMetrics`. Judged the same call already settled for `ILogger` in that
  project: a cross-cutting diagnostic API with no I/O of its own, inert until a host wires an
  exporter, so rule 2's "every external resource sits behind a port" does not reach it. The
  alternative — a bespoke `IDeliveryMetrics` port — would add an interface, a registration and a fake
  to buy nothing testable that the in-memory OTel reader does not already give.
- One more tag combination to keep bounded. `recipient_kind` is closed by construction
  (`PrincipalKeys.KindOf` returns one of three constants, never a substring of a key), which is what
  keeps a metric from growing a time series per visitor.
- `ConnectionDrainCoordinator` calls the same dispatcher port and deliberately does **not** feed the
  counter, so a rolling deploy's `Reconnect` pushes never look like a burst of message delivery. That
  is asserted by a test, not left to a comment.

## Alternatives considered

- **A raw `deliveries_to_zero` counter.** Fastest to write, and the wrong answer delivered quickly:
  most of its increments are a visitor who closed a tab, so the series is dominated by the ordinary
  case and no threshold on it means anything. Rejected on `15-03`'s grounds before an alert was ever
  written.
- **The platform tags the metric itself, deriving a kind from `PrincipalKey`'s text.** The keys are
  already namespaced (`visitor:{id}` / `operator:{id}`), so the prefix is *there*. Rejected twice
  over: it would make `Ago.Platform.*` depend on a convention it does not own and cannot enforce, and
  a product that failed to namespace would silently turn the whole key into a tag value — one time
  series per visitor, a cardinality failure the platform has no way to bound.
- **The platform passes the kind in, as a caller-supplied label on each recipient.** Keeps the tag
  bounded by the caller, but leaves the platform owning an instrument whose meaning it cannot
  describe, and adds a parameter every caller must fill in for a reason unrelated to delivery.
  Returning the numbers is strictly less coupling for the same information.
- **`NodeDeliveryConsumer` reads `LocalConnectionTracker` itself instead of changing the port.**
  Tempting, because it needs no API change and it is literally `7-07`'s "read the set it describes".
  Rejected: the tracker is a *proxy* for what the dispatcher will decide, correct only for as long as
  every implementation happens to consult it. `7-07`'s actual lesson is that a number must come from
  the mechanism that owns the fact — and here that mechanism is the dispatcher, not the map it
  usually reads.
- **A delivery receipt persisted per message.** A product feature, not observability, with a write
  per recipient per message on the hot path. Nobody has asked for one, and `7-08` explicitly did not.
