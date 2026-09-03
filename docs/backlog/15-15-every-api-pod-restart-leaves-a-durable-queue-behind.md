# every API pod restart leaves a durable queue behind, for ever

- **Stage**: 15
- **Status**: ready
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

- [ ] A pod that goes away leaves no queue behind, proven by killing one and looking.
- [ ] Whatever changed about delivery guarantees is written down in `messaging.md`, not just in code.
- [ ] The seventy-one existing orphans are gone, and the removal is something a runbook can repeat.

## Context

Found while running `22-13`'s new smoke check against the live broker to prove it fails before the
fix. The check needed `rabbitmqctl list_queues`; the orphans were simply the first thing visible in
its output. Nothing about `22-13` causes or fixes this.
