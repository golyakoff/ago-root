# every API pod restart leaves a durable queue behind, for ever

- **Stage**: 15
- **Status**: done in code (2026-09-04), `ago-platform#45`, `adr/0097` — **two Done-when open**:
  the pin move and the removal of the 71 existing orphans. See Outcome.
- **Found**: 2026-09-03, on the live broker, while proving a different check bites.

## The measurement

```
total queues                        140
deliver-to-connections.<pod>         72
of those with no consumer            71
live ago-chat-api pods                1
```

Seventy-one queues belong to pods that no longer exist. Nothing deletes them, so the count is a
running total of every `ago-chat-api` pod this cluster has ever had.

## Why they survive

`RabbitMqEventConsumer` names a queue `<topic>.<consumerName>` in **competing** mode and declares it
`durable: true, autoDelete: false`. Node-delivery uses competing mode with the **pod name** as the
consumer name — correct, because that is exactly what "deliver to the node holding this connection"
means, and it is why `deliver-to-connections` cannot use the fanout branch's throwaway GUID name.

The consequence was never decided, only inherited: a durable queue named after an ephemeral thing
outlives it by design. Auto-delete is the property that would have matched, and the platform ties
auto-delete to `exclusive`, which node-delivery cannot be.

## Why this is worth an item rather than a note

- Every one of them is **bound to the fanout exchange**, so a published node-delivery message is
  routed into seventy-one dead queues as well as the live one. They hold no messages today, which is
  the only reason this is a queue-count problem rather than a disk-space one.
- It grows without bound and nothing reports it. A restart is routine; seventy-one is what routine
  looks like after a few weeks.
- It makes the broker's own state unreadable. Half of `list_queues` is noise, which is how this
  went unnoticed until something else needed to read that output.

## The decision this needs

The tempting fix — a periodic sweep of consumer-less `deliver-to-connections.*` queues — is a janitor
for a mess rather than a reason not to make it, and it can race a pod that is starting.

The alternative is that these queues stop being durable, which means the platform's
`QueueDeclareAsync` stops tying `autoDelete` to `exclusive`. That is a **platform** change, so
`CLAUDE.md`'s qualifying rules apply and the argument has to be made rather than assumed — though
unlike `5-20`'s rejected widening, this one is about a property the platform already models wrongly
for a real case, not about a shape one product happens to want.

Losing durability here may well be correct: a queue whose only purpose is delivering to one live pod
has nothing to keep once that pod is gone. Say so explicitly if that is the answer, because it is a
delivery-guarantee change and `messaging.md` should carry it.

## Done when

- [x] A pod that goes away leaves no queue behind, proven by killing one and looking. — proven against
      a real broker rather than the live cluster: close the declaring connection, the queue and its
      retry queue are gone. The durable case is proven the other way in the same run, which is the
      half that would have been easy to skip.
- [x] Whatever changed about delivery guarantees is written down in `messaging.md`, not just in code.
      — with `adr/0097`, including the instruction *not* to generalise `ProcessScoped` to `Competing`.
- [ ] The seventy-one existing orphans are gone, and the removal is something a runbook can repeat.
      — **not done, and the order matters**: they were declared by the old code, so cleaning them
      before the fix is deployed only lets new pods recreate them. Deploy first.

## Context

Found while running `22-13`'s new smoke check against the live broker to prove it fails before the
fix. The check needed `rabbitmqctl list_queues`; the orphans were simply the first thing visible in
its output. Nothing about `22-13` causes or fixes this.

## Outcome

Code done 2026-09-04, `ago-platform#45`, released as `0.20.0`. `adr/0097` carries the decision.

**The obvious fix was the trap, and naming it was most of the value.** Making `Competing` queues
auto-delete would have hit `OperatorRemovedFromSite.operator-removed` and every other genuinely
durable subscription, silently dropping messages published while no replica happened to be attached.
Lost work, not an error. So lifetime became a second, explicit axis rather than a change to the
existing one.

**A pre-existing, unrelated test found the part nobody reasoned out.** A first draft tied the
dead-letter queue's exclusivity to the new lifetime too, and
`RabbitMqPublishConsumeTests.Broadcast_TwoConsumers_BothReceiveEveryMessage` failed against a real
broker with `RESOURCE_LOCKED` the moment a second subscription declared the same DLQ name. A DLQ is
legitimately shared by name across independent subscriptions. That is the argument for running the
whole suite rather than the new tests.

**Two things remain, in this order.** The consumers' pin must move to `0.20.0` — cheap this time,
since the six-argument overload is unchanged and no consumer source breaks. Then the deploy. Only
after that do the 71 orphans get removed, because until the new code is running, new pods recreate
them.
