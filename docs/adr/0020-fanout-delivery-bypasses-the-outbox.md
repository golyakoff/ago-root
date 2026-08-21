# ADR-0020: Node-delivery fan-out publishes directly, bypassing the outbox

- **Status**: Accepted
- **Date**: 2026-08-22
- **Stage**: 3

## Context

`adr/0005` requires a state change and its integration event to commit in one transaction, with
publishing as a separate step performed only by the outbox dispatcher - `IEventPublisher.PublishAsync`'s
own doc comment says exactly this: "Never called from inside a request handler - only the outbox
dispatcher calls this." `3-02` needs a `Worker` consumer that reacts to `MessageAccepted` by resolving
the conversation's participants, looking up their connections in the registry (`3-01`), and publishing
one `NodeDelivery` per node so each `Ago.Chat.Api` node can push to the connections it owns
(`realtime.md`'s Fan-out path). That publish would come from inside a message-consumer handler, not
the outbox dispatcher - on its face, exactly what the existing rule forbids.

## Decision

`NodeFanoutPublisher` (`Ago.Platform.Realtime`) calls `IEventPublisher.PublishAsync` directly. This is
allowed because a `NodeDelivery` is not the kind of event the outbox rule protects: it describes no
committed state change of its own. It is a derived, ephemeral notification computed from an event
(`MessageAccepted`) that already went through the outbox for the write that actually matters. Losing
a `NodeDelivery` publish - a `Worker` crash between resolving connections and publishing, a broker
outage - is the same accepted, documented failure mode as a stale registry entry: the message itself
is durably persisted and already delivered to its own transaction; the recipient still gets it on
reconnect (`3-03`'s resume protocol reads from Postgres, not from this path). Nothing about the outbox
guarantee is actually needed here, because nothing here is a fact anyone needs to survive a crash to
still be true - if this specific push never happens, no data is lost and no invariant breaks.

The generalised rule going forward: **the outbox is mandatory for events describing a state change
someone must not lose; a purely derived, best-effort notification computed from an already-outboxed
event may publish directly.** `IEventPublisher.PublishAsync`'s doc comment is updated to say this,
rather than continuing to claim a single caller that is no longer true.

## Consequences

- A second, narrower category of "publish directly" now exists alongside the outbox path, so a future
  reader of `IEventPublisher` needs to check which category a new caller falls into rather than
  assuming the outbox dispatcher is the only legitimate one. The doc comment update is what keeps this
  from becoming tribal knowledge.
- `NodeDelivery` publishes carry no delivery guarantee beyond RabbitMQ's own at-least-once for whatever
  did get published - a crash before the publish call simply means that specific live push never
  happens, silently, by design. Anything that later needs a *guaranteed* delivery notification (none
  does today) would need the outbox after all, not this path.
- This keeps `Ago.Chat.Worker`'s new fan-out consumer symmetric with `UnreadCounterConsumer`
  (`2-05`) in shape - both react to `MessageAccepted` - while genuinely differing in what they owe:
  `UnreadCounterConsumer` writes a fact that must not be lost (inbox-guarded, `adr/0017`); the fan-out
  consumer relays a fact that already survived elsewhere.

## Alternatives considered

- **Route `NodeDelivery` through the outbox too** (write a row, let the dispatcher publish it).
  Rejected: it would durably persist a fact - "node X should push to these connections" - that is
  stale the instant a connection's registry entry expires or a node dies, which is realtime.md's own
  definition of something that must never be treated as durable state. Persisting it does not make the
  delivery any more reliable, since the underlying connections are themselves advice, not truth - it
  only adds write load and dispatcher latency to a path with nothing to gain from either.
- **A separate, non-outbox `IEphemeralEventPublisher` port**, distinct from `IEventPublisher`, to make
  the two categories impossible to confuse at the type level. Rejected for now: one caller does not
  justify a second port with an identical shape; revisit if a second ephemeral-publish use case shows
  the distinction is worth encoding in types rather than in a doc comment and this ADR.
