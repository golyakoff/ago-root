# seventy-one orphaned queues are still on the live broker

- **Stage**: 15
- **Status**: ready — **blocked on the deploy**, deliberately.
- **Found**: 2026-09-03 as part of `15-15`; carried out to its own number 2026-09-04 when `15-15`
  closed with the leak fixed and the existing mess untouched (rule 14).

## The measurement, which is still true

```
total queues                        140
deliver-to-connections.<pod>         72
of those with no consumer            71
```

One live `ago-chat-api` pod, seventy-two queues named after pods. Each orphan is bound to the fanout
exchange, so **every node-delivery publish routes into all of them**. They hold no messages today,
because nothing dead-letters into them and no consumer is attached to leave anything behind — but they
are seventy-one destinations a broadcast is copied to on every send, and the count is a running total
of every `ago-chat-api` pod this cluster has ever had.

## Why it is a separate item from `15-15`

`15-15`'s promise — *a pod that goes away leaves no queue behind* — is complete and proven against a
real broker (`QueueLifetime.ProcessScoped`, `adr/0097`, shipped as `Ago.Platform.*` 0.20.0 and pinned
in `ago-chat`). Nothing in it could have removed these: the fix stops the count growing, and the
queues that already exist outlive it exactly as they outlived the pods that made them.

This one is a different promise, needs a deploy `15-15` did not, and can only be verified on the live
cluster. Under rule 15 those are two tickets; under rule 14 the remainder gets a number rather than
staying inside a finished one.

## The order, which is the whole risk

1. **Deploy first.** These were declared by the old code. Cleaning them before the fixed code is
   running only lets the next pod recreate its own, and leaves the count looking fixed for as long as
   nobody restarts anything.
2. **Then remove them**, and only the ones with no consumer — a `deliver-to-connections.<pod>` queue
   belonging to a *live* pod is doing its job, and the pod names are not guessable from outside.
3. **Then restart a pod and look**, which is the only thing that proves step 1 worked rather than that
   step 2 ran.

## What must not happen

**A blind delete by name prefix.** The prefix matches the live pod's queue too. The consumer count is
the discriminator, and it must be read at the moment of deletion rather than from a list taken
earlier — a pod that starts between the listing and the delete would have its queue removed underneath
it.

## Authorised to proceed on the live deployment (author, 2026-09-05)

The author's words: *do this boldly while there are no live clients on the field yet.*

That authorisation is **dated and bounded**, and both halves matter. It rests on a fact that stops
being true the moment a first tenant signs up — which is expected within weeks — so an implementation
reading this later must check whether it still holds rather than inherit it. It covers acting on the
live deployment for this item; it is not a standing licence for the next one.

## Done when

- [ ] The fixed code is running on the cluster, confirmed by the image tag rather than by the deploy
      script's exit code.
- [ ] No consumer-less `deliver-to-connections.*` queue remains, confirmed by looking at the broker.
- [ ] A pod is restarted afterwards and leaves no queue behind — the same measurement that opened
      `15-15`, run again.
- [ ] The removal is written down somewhere a runbook can repeat, because this is a shape that recurs:
      a queue named after something ephemeral, left behind by code that has since been fixed.
