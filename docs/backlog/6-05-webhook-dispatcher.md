# Webhook dispatcher: signed delivery, per-endpoint breaker, per-tenant bulkhead, DLQ

- **Stage**: 6
- **Status**: ready
- **Depends on**: `6-01` (`Ago.Platform.Resilience`), `6-02` (a real `ConversationClosed` to react
  to), `6-03` (endpoints to deliver to, `webhook_deliveries` to write), `6-04` (something real to
  point at while building and testing this), `5-11` (this item adds a *second* topic with two
  `Competing` consumers of its own kind - built on the unfixed shared-queue bug, it would silently
  inherit it on day one)

## Goal

`Ago.Chat.Webhooks` stops being a `dotnet new worker` skeleton and becomes the actual bulkhead
`adr/0013` justified as its own deployable: it consumes `ConversationAssignedToOperator` and
`ConversationClosed`, signs and delivers them to every active endpoint for that conversation's site,
and does so in a way where one tenant's hung CRM never touches another tenant's deliveries or any
other host's own work.

## Context to read first

`resilience.md`'s "Inside the dispatcher" list in full - every bullet there is a Done-when item below,
not aspiration. `adr/0013`'s Decision table (`Ago.Chat.Webhooks` scales with third-party latency,
must not affect the others - the process boundary is what makes the bulkhead honest, this item is
what makes that boundary do real work instead of standing empty). `messaging.md`'s delivery
guarantees (`inbox` idempotency ledger - this consumer needs one too, same as every other). `6-03`'s
own schema and ADR for exactly what to sign and how.

## Scope

- Two `Competing`-mode consumers in `Ago.Chat.Webhooks` (**not** the same queue - `5-11`'s own fix
  must have landed first, or this item inherits that bug on day one for its own two event types)
  reacting to `ConversationAssignedToOperator` and `ConversationClosed`.
- Per event: resolve the conversation's site, look up its active `webhook_endpoints`, build the
  signed payload (`event_type`, the conversation id, timestamps - never a message body, matching this
  project's own "never log/transmit message content beyond what's necessary" instinct elsewhere), and
  attempt delivery to each endpoint independently - one endpoint's failure never blocks another's for
  the same event.
- **Per-endpoint circuit breaker** (`Ago.Platform.Resilience`, `6-01`): keyed by `endpoint_id`, so one
  tenant's dead CRM opens only *that* endpoint's breaker.
- **Per-tenant concurrency cap (bulkhead)**: keyed by `site_id`, so a tenant with many endpoints (or
  a slow one under load) cannot starve delivery threads/connections belonging to every other tenant.
- **Layered timeouts**: connect, response-headers, total - `resilience.md`'s own "a missing total
  timeout is how retries become a queue of hung requests" is the literal failure mode `6-04`'s
  `hangs` personality exists to catch.
- **Bounded retry with exponential backoff and jitter**, then `webhook_deliveries.status = 'dead_lettered'`
  with the full request/response context (`resilience.md`) - not just "it failed," enough for a
  tenant to actually debug their own receiver from `6-03`'s delivery-history API.
- Idempotency: `inbox`-style ledger keyed by `(message_id, endpoint_id)` - a redelivered
  `ConversationClosed` (at-least-once, `messaging.md`) must not double-send to an endpoint that
  already got it.

## Out of scope

- Replay (a tenant asking "resend delivery X") - `6-03`'s own Out-of-scope list didn't promise it
  either; a real, separate feature if ever needed.
- Any change to *which* events exist beyond the two named here - `adr/00XX` (`6-03`) is where a third
  event type would get decided, not silently added inside this item.
- Rate-limiting *inbound* to the dispatcher - nothing calls `Ago.Chat.Webhooks` from outside except
  the broker; `caching.md`'s inbound rate limiting is for `Ago.Chat.Api`'s own public surface, unrelated.

## Done when

- [ ] Against `6-04`'s fake CRM: `succeeds` delivers and is recorded `delivered`; `5xxs` retries the
      configured number of times then dead-letters with the real response captured;
      `hangs` (30s) is cut off by the total timeout, not left to hang the consumer thread; `disappears`
      fails fast (connection refused) and does not retry as aggressively as a transient 5xx would
      (a refused connection is not "try again in 100ms," `resilience.md`'s own retry-predicate
      reasoning already established in `6-01`'s S3 adapter).
- [ ] Breaker proven per-endpoint, not global: two endpoints for the same site, one pointed at
      `5xxs`, one at `succeeds` - the failing one's breaker opens and stops attempting, the succeeding
      one keeps delivering the whole time, proven concurrently, not sequentially.
- [ ] Bulkhead proven per-tenant: many endpoints across two sites, one site's endpoints all `hangs` -
      the *other* site's deliveries are not measurably slowed, proven with real timing, not asserted
      from the config.
- [ ] Idempotency proven: a redelivered `ConversationClosed` (forced via a duplicate outbox row or a
      requeue) does not produce a second delivery to an already-succeeded endpoint.
- [ ] `5-11` (the shared-queue Competing-consumer bug) confirmed fixed and this item's own two
      consumers pass its regression test too, not just inherit the fix by luck.

## Open questions

None - the mechanism is fully specified by `resilience.md`, `adr/0013`, and `6-03`'s own ADR; nothing
here is a design choice left open.
