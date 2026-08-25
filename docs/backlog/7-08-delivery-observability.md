# A message that reached nobody looks exactly like one that reached everybody

- **Stage**: 7
- **Status**: ready
- **Depends on**: nothing. Written alongside `7-07`, from the same investigation, and unrelated in
  cause — that one fixed a metric that lied, this one fills the silence next to it.

## Goal

When a message is fanned out, the system records who it was meant for and how many live connections it
actually reached. Today it records neither, and the difference between "delivered to both participants"
and "delivered to nobody" is not visible anywhere.

## How this was found

On 2026-08-25 an operator reported that a message they sent reached the visitor and never appeared in
their own thread. Answering "did the server even try to deliver it to that operator's connection"
should have taken a minute. It took an hour of reading code and querying Redis by hand, because
nothing in the running system could answer it. The cause turned out to be client-side (`5-16`), which
is precisely the point: the fastest way to establish that was to rule out the server, and there was no
way to rule out the server.

## What exists today

- `ResolveMessageDeliveryTargetsHandler` builds the recipient list — the visitor always, the operator
  only if the conversation has one — and calls `INodeFanoutPublisher.PublishAsync`.
- `NodeFanoutPublisher` resolves each recipient's live connections from the registry and groups them by
  node.
- `NodeDeliveryConsumer` dispatches to each connection and **acknowledges every delivery regardless of
  per-connection outcome**. That is correct and deliberate: an unreachable connection is a harmless
  no-op (`realtime.md`: "a stale entry causes a harmless failed delivery"), and nothing here becomes
  correct by being retried.

Correct, and completely silent. No count of recipients resolved, no count of connections found, no
count of dispatches that met a live connection.

## The design question this item has to answer

**Zero deliveries is usually normal.** A visitor who closed the tab has no connections, and fanning out
to nobody is the expected outcome many times a day. So a naive "delivered to zero" counter would be
noise, and an alert on it would be worse than nothing — the failure mode `15-03` explicitly warns
about, where a rule nobody can act on trains its reader to ignore the next one.

What makes the signal useful is dimension, not existence: which principal kind (a visitor with no
connection is ordinary, an operator who is supposed to be online is not), and whether the recipient was
believed present at the time. Getting that distinction right *is* the item; a raw counter is the wrong
answer delivered quickly.

## Context to read first

`ago-platform/src/Ago.Platform.Realtime/NodeFanoutPublisher.cs` and `NodeDeliveryConsumer.cs` — the two
places that know the numbers and currently keep them. `ago-chat/src/Ago.Chat.Application/UseCases/
ResolveMessageDelivery/ResolveMessageDeliveryTargetsHandler.cs` — where the recipient list is decided,
including the conditional operator. `docs/architecture/realtime.md`'s fan-out path — the design being
instrumented, and its statement about harmless failed deliveries, which this item must not contradict.
`docs/backlog/7-02-metrics-instrumentation.md` — the instruments this joins. `docs/backlog/7-07-*` —
the sibling defect, and the reason to check any new instrument against the mechanism that calls it.

## Scope

- Record, at fan-out: recipients resolved, and connections resolved per recipient. On the existing
  span rather than as a new log line — `7-01`'s trace already spans this hop, and an attribute there
  is free to correlate.
- Record, at dispatch: how many dispatches met a live connection. This is the number that was missing.
- Dimension it so an ordinary zero is distinguishable from an interesting one, per the design question
  above. State the choice and its reasoning; this is the part worth arguing about.
- **Check the new instrument against its callers before shipping it**, which is exactly what `7-07`
  did not do: confirm nothing on a refresh, retry or redelivery path inflates it.
- No alert. `15-03` decides later whether any of this deserves one, with real data in hand rather than
  a guess made while adding the instrument.

## Out of scope

- Changing delivery behaviour. The ack-regardless design is right and stays; this is about seeing it.
- A delivery receipt or read confirmation for the product — a feature, not observability, and nobody
  has asked for one.
- Per-message logging. At this volume a log line per fan-out is a way to fill a disk (`15-05`), and the
  trace already carries the correlation.
- The gauge from `7-07`.

## Done when

- [ ] A fan-out's span carries recipients and connections resolved.
- [ ] Dispatches that met a live connection are counted, dimensioned so a routine zero and a suspicious
      zero are distinguishable.
- [ ] The instrument has been checked against every path that calls it, with the result written down.
- [ ] The question that started this — "did the server try to deliver to that connection" — is
      answerable from the running system, demonstrated by answering it.

## Open questions

None. The dimensioning choice is this item's own to make and record.
