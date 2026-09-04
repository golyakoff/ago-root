# eight integration tests sleep 500 ms instead of waiting, and one waits less than it must outlast

- **Stage**: 15
- **Status**: done (2026-09-04), `ago-chat#167`. The first attempt (`#165`) waited for the queue to
  exist — step 1 of the four `SubscribeAsync` performs — and was corrected to wait for a consumer to
  attach, step 4. `15-18` carries the ninth file this item's grep missed
- **Found**: 2026-09-04, by a CI failure on `ago-chat#162` — a pull request that touches none of this.

## What failed

```
WebhookDispatchSharedQueueRegressionTests.BothConsumerTypes_EachReceiveEveryMessage_NeitherSplitsWithTheOther
Webhook-dispatch consumer only received 0/6 messages -
  the shared-queue bug would show up as a split total less than 6.
```

Then, on a **re-run of the same commit**, it failed again — this time **5/6**. Locally it passes every
time, in about two seconds. One failure in the previous twenty-five CI runs.

Two different numbers, two different defects.

## `0/6` — publishing before the subscription exists

```csharp
await Task.Delay(TimeSpan.FromMilliseconds(500)); // both subscriptions to actually land
```

A fixed sleep, then publish. If the subscriptions have not landed, the messages reach an exchange with
no queue bound to it and **RabbitMQ discards them silently**. The twenty-second wait that follows then
observes zero, for ever, because nothing was ever queued.

The same sleep, mostly citing each other, is in **eight files**: `ConnectionFanoutEndToEndTests`,
`ConversationAssignmentFanoutEndToEndTests`, `DeliveryObservabilityEndToEndTests`,
`OfflineAutoReplyDeliveryEndToEndTests`, `OfflineAutoReplyEndToEndTests`, `TracingEndToEndTests`,
`WebhookDispatchIdempotencyTests`, `WebhookDispatchSharedQueueRegressionTests`.

## `5/6` — a wait shorter than the recovery it must outlast

`WebhookDispatchTestHarness`'s defaults, against a **real** signed HTTP call to a **real** FakeCrm
process, six times over:

```
ConnectTimeout / ResponseHeadersTimeout   1 s
pipeline Timeout                          2 s
CircuitBreaker  MinimumThroughput 2, FailureRatio 0.5
BreakDuration                            30 s

the test waits                           20 s
```

One call missing a one-second timeout is enough: with a minimum throughput of two and a failure ratio
of one half, the breaker **opens for thirty seconds**, and the test waits twenty. After that the
remaining messages *cannot* arrive inside the window. **Not a race that sometimes resolves — a
guaranteed failure for that run.**

Nothing anywhere says those two numbers are related.

## And the message points at the wrong thing, twice

*"the shared-queue bug would show up as a split total less than 6"* describes **neither** observed
failure. That test exists for `5-11`, where two consumer types split one queue — which would read as
three and three. Receiving nothing is a lost publish; receiving five is an open circuit. The
assertion sends whoever reads it looking for a bug that is not there — the same class of mistake
`11-17` fixed in the console the same day.

## Done when

- [ ] No integration test publishes on the strength of a fixed sleep — each waits for its subscription
      to be observable, and that wait fails with a message saying the subscription never landed.
- [ ] No test's success depends on a wait shorter than a recovery window its own configuration can
      open, and the relationship between the two numbers is stated where they are set.
- [ ] Receiving nothing, receiving some, and receiving a split read as three different findings.
- [ ] Whatever replaces the sleep is used by all eight. This failed because the pattern was copied,
      and a fix in one place would be copied just as unevenly.

## Worth knowing before starting

The failure cannot be reproduced locally — it needs a loaded runner. So the fix cannot be proven by
making the original failure happen; it has to be proven by showing the *condition* now waited for is
observable, and that the wait fails informatively when it is not met.

`15-15` added `RabbitMqTestHelpers.QueueExistsAsync` to `ago-platform` for this kind of check,
including the detail that a 405 `RESOURCE_LOCKED` means *exists but owned*, not absent.
