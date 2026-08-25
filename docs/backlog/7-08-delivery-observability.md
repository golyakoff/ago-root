# A message that reached nobody looks exactly like one that reached everybody

- **Stage**: 7
- **Status**: done
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

- [x] A fan-out's span carries recipients and connections resolved.
- [x] Dispatches that met a live connection are counted, dimensioned so a routine zero and a suspicious
      zero are distinguishable.
- [x] The instrument has been checked against every path that calls it, with the result written down.
- [x] The question that started this — "did the server try to deliver to that connection" — is
      answerable from the running system, demonstrated by answering it.

## Outcome

**The dimensioning choice, and where it lives** — `adr/0044`. Two instruments, split at the
product/platform seam rather than duplicated across it:

| Instrument | Describes | Tags |
|---|---|---|
| `ago.chat.delivery.recipients` (counter) | one point per recipient per fan-out — who the message was *meant* for | `method` (`MessageReceived`/`ConversationAssigned`), `recipient_kind` (`visitor`/`operator`/`unknown`), `presence` (`connected`/`absent`) |
| `ago.platform.realtime.dispatches` (counter) | one point per connection the node was asked to push to — whether the attempt met a connection it still held | `node`, `outcome` (`delivered`/`connection_not_local`/`failed`) |
| span attributes on the existing `"{topic} process"` span | `ago.fanout.recipients`, `ago.fanout.connections`, `ago.fanout.nodes` | — |

`presence` and `recipient_kind` together are what the design question asked for: an *operator* under
`absent` is the interesting series, a visitor under `absent` is a normal Tuesday, and both are
counted so the ratio is readable rather than assumed. `connection_not_local` is the second
interesting case — the registry believed the recipient present and the node it named disagreed. No
alert on either; `15-03` decides that with data.

**The platform reports facts, the product names them.** `INodeFanoutPublisher.PublishAsync` returns a
`FanoutResult` (each recipient, and how many live connections the registry had for them) instead of
recording a metric itself, because "visitor" and "operator" — the whole point of the dimension — are
concepts `Ago.Platform.*` is not allowed to learn, and deriving a tag from `PrincipalKey`'s text
would have handed the platform an instrument whose cardinality it cannot bound (one series per
visitor for any product that failed to namespace its keys).

**The dispatch outcome comes from the code that decides it.** `ILocalConnectionDispatcher.DispatchAsync`
now returns a `DispatchOutcome`. The tempting alternative — have `NodeDeliveryConsumer` read
`LocalConnectionTracker` itself and need no API change — was rejected as a *misreading* of `7-07`:
the tracker is a proxy for what the dispatcher will decide, correct only for as long as every
implementation happens to consult it. `7-07`'s actual lesson is that the number must come from the
mechanism that owns the fact.

**Behaviour is unchanged.** Every delivery is still acknowledged regardless of per-connection
outcome, an unreachable connection is still a harmless no-op, and nothing is retried into
correctness. Only the silence next to it is gone.

**Checked against every caller, per Scope's fourth bullet:**

| Path that could inflate an instrument | Verdict |
|---|---|
| `ConnectionDrainCoordinator.StopAsync` → `DispatchAsync` | The dispatcher port's *other* caller: one `"Reconnect"` push per connection on every graceful shutdown. Deliberately **not** counted — the counter is recorded in `NodeDeliveryConsumer`, not beside the port. Without that, every rolling deploy would look like a burst of message delivery. Asserted by `ADrainsReconnectPushes_DoNotTouchTheDispatchCounter`. |
| A redelivered `NodeDelivery` (broker at-least-once) | Counts again, **deliberately**: the instrument describes dispatch *attempts this node made*, and a redelivery is a second real attempt. What is forbidden is one attempt producing two points; asserted by `ARedeliveredNodeDelivery_CountsOncePerAttempt_NotTwicePerAttempt`. |
| `ConnectionFanoutConsumer` retrying a failed fan-out (`MaxAttempts` > 1) | Re-resolves and re-publishes, so `ago.chat.delivery.recipients` counts the retry too — same reasoning, and the consumer's own doc comment already states re-publishing a fan-out is exactly as harmless as the first publish. |
| The exception path in `NodeDeliveryConsumer`'s per-connection loop | Records exactly one point (`failed`), because the recording sits *after* the try/catch rather than in both branches. Asserted by `ADispatcherThatThrows_IsCountedOnceAsFailed_AndTheRestOfTheBatchStillCounts`. |
| `ConnectionHeartbeat` / `RegisterAsync` — `7-07`'s own culprit | Untouched. Neither new instrument is anywhere near the registry write path. |
| `ResolveConversationAssignmentTargetsHandler` | The second fan-out caller, instrumented too, separated by the `method` tag rather than left silent — an uninstrumented second caller of the same helper is how a metric quietly stops describing its own name. |

**Fails-before, passes-after** — one per instrument, each a *plausible wrong implementation* rather
than a missing one:

| Instrument | Wrong implementation | Result |
|---|---|---|
| `ago.platform.realtime.dispatches` | count every dispatch as `delivered` (ignore the returned outcome) | `AConnectionTheNodeNoLongerHolds_IsCountedApartFromOneItDoes`: `Expected: 1 / Actual: 2` |
| `ago.fanout.connections` | report the recipient count where the connection count was meant | `AFanoutsSpan_CarriesRecipientsConnectionsAndNodes_AsResolvedFromTheRegistry`: `Expected: 3 / Actual: 2` (two recipients, one with two tabs) |
| `ago.chat.delivery.recipients` | tag `presence` from the recipient list instead of from what the registry answered | `HandleAsync_TagsEachRecipientByKindAndByWhetherTheRegistryHadAConnection` **and** `HandleAsync_AnUnassignedConversationWithNobodyConnected_...`: both `Expected: 1 / Actual: 0` |

**The question, answered.** `Ago.Chat.Integration.Tests.DeliveryObservabilityEndToEndTests`
reproduces the incident's own shape against real Postgres/RabbitMQ/Redis — visitor and assigned
operator, the operator's connection registered on node B but node B no longer holding it — and then
answers "did the server try?" **from telemetry alone**, reading nothing out of the fakes: the span
says two recipients and two connections (so the operator was not dropped from the list), the chat
counter says `operator`+`connected` (so the registry believed them present), and the platform counter
says node B reported `connection_not_local` while node A reported `delivered` for the same fan-out.
Everything before that hop worked; the connection is where it stopped. That is the hour of reading
code, replaced by three reads — and repeatable in CI rather than eyeballed once on a live deployment.

**Deliberately not added**, so the absence is a decision and not an oversight:

- No per-message log line — `15-05`'s disk, and the trace already carries the correlation.
- No histogram of connections-per-recipient. The span carries the number per fan-out, which is what a
  trace investigation needs; an aggregate distribution of it has no reader yet.
- No `delivered/total` ratio metric. Two counters divide fine in the query layer; a third instrument
  that can disagree with the first two is a liability, not a convenience.
- No alert or dashboard panel — `15-03` and `7-03` respectively.
- No delivery receipt or read confirmation. A product feature, out of scope, and nobody asked.
- No duplication of `7-02`'s outbox lag / publish failures / capacity-claim counters, `7-07`'s
  connections gauge, or `6-10`'s `capacity_release_deadlocks` — all checked, none touched.
- `messaging.md` is unchanged and was checked: nothing here alters a contract, a delivery semantic or
  a topic.

**Package:** `ago-platform` `CHANGELOG.md` `[0.17.0]` — two `### Changed` (breaking) entries for the
two port signatures and a `### Added` block for `FanoutResult`/`DispatchOutcome`/the new counter and
span attributes. `0.16.0` was deliberately skipped: `5-13` had already claimed it on a pushed branch.
**`ago-chat`'s pin must move to `0.17.0`** — not done on this branch, by instruction, and it must be
done together with `5-13`'s own pin move.

**Verified:** both repositories `dotnet format --verify-no-changes` clean, `build -c Release` with
**0 warnings**, full suites green — `ago-platform` 83 tests (3 architecture, 26 unit, 54
integration), `ago-chat` 563 (99 domain, 17 architecture, 198 application, 21 FakeCrm, 29
concurrency, 199 integration). `ago-chat`'s suite was built and run against a locally packed
`0.17.0`, with the pin and `nuget.config` reverted afterwards — the branch as committed therefore
does not build until the pin moves, which is the deliberate consequence of not bumping it here.

## Open questions

None. The dimensioning choice is this item's own to make and record — made, and recorded in
`adr/0044`.
