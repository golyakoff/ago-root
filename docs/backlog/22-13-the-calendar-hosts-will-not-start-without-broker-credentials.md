# the calendar hosts will not start without broker credentials neither manifest has

- **Stage**: 22
- **Status**: done (2026-09-04), `ago-deploy#137`, verified live
- **Found**: 2026-09-03, verifying `22-05` before merge.

## What changed under the deployment

`22-05` gave AGO Calendar its first broker consumer, and registered it in `CalendarModule` — the one
module **every** calendar host loads:

```csharp
services.AddRabbitMqMessaging(configuration);
```

`AddRabbitMqMessaging` binds `Messaging:RabbitMq:*` with `ValidateDataAnnotations().ValidateOnStart()`,
and `RabbitMqOptions` marks `HostName`, `UserName` and `Password` `[Required]` — which, for a string,
fails on empty as well as null.

Neither `k8s/base/calendar-api.yaml` nor `k8s/base/calendar-worker.yaml` sets any of them.

**So the next `apply` starts two pods that cannot boot.** Not the consumer failing quietly — startup
validation, before anything serves.

## The half that is easy to miss

The **API** is the sharper one, and it is the host that never uses the broker at all. It loads the
module, so it inherits the requirement; `Ago.Calendar.Api` resolves neither `IEventConsumer` nor
`IEventPublisher`. Nobody debugging "the booking API will not start" would look for a role-projection
change as the cause.

This is not an argument for registering the broker only in the Worker. The project's own precedent is
the opposite and is stated in `calendar-worker.yaml` itself for `Redis__ConnectionString`: *"a manifest
that only works for the code path currently exercised is a manifest one refactor away from a startup
crash nobody connected to this file."* Both hosts get the configuration.

## Why this was invisible to every test

`CalendarApiFactory` supplies `rabbitmq.invalid` / `unused` / `unused` — deliberately, with its reason
written down: the connection is lazy, so a syntactically valid value that is never dialled satisfies
validation without a broker container. Correct for a test fixture, and it means **a green suite says
nothing about whether the manifests carry the same three keys.** That is the same shape as `20-20`'s
crash-loop, which every check passed straight through.

## Done when

- [x] Both calendar hosts carry `Messaging__RabbitMq__*` naming the **same broker and vhost**
      `ago-chat`'s own Worker publishes to, and both start. — they did **not** before: the redeploy
      carrying `22-05` left `ago-calendar-api` in CrashLoopBackOff and the worker in Error, with
      `OptionsValidationException` naming all three fields. The prediction was observed.
- [x] The credential question is answered rather than assumed. — the same user and vhost as
      `ago-chat`'s Worker, because it must be the same broker the events are published to. A
      reader-scoped user would be better and needs a RabbitMQ user-provisioning step that does not
      exist here; recorded rather than quietly treated as fine.
- [x] Whatever network policy is needed for the calendar pods to reach the broker exists. — it did
      not: `rabbitmq-ingress` listed only the three chat hosts. **Only the worker was added.** The API
      loads the same module and therefore carries the same three settings, but resolves no publisher
      or consumer and never dials — and an ingress allowance added for symmetry is one nobody removes
      later.
- [x] Something fails when the keys go missing again. — `smoke.sh` asserts on the **queue and its
      consumer**, not on pod health, because pod health is exactly what stays green in this failure
      mode. Its fails-before was taken against the live broker before the fix: zero matches.

## Out of scope

- Proving the projection actually flows end to end in production. Different promise, and it needs a
  real grant to observe; this item is only about the hosts being able to start and connect.

## Context

`22-05` deliberately did not touch `ago-deploy` — it was told not to, and it reported the worker half
of this gap in its own words. The API half is this item's own finding, made while reading the module
rather than the report.

## Outcome

Done 2026-09-04, `ago-deploy#137`, verified on the live deployment rather than by the manifest.

```
Calendar role projection
  PASS  the calendar's role-projection queue exists and has 1 consumer(s) attached
```

Full smoke afterwards: **45 passed, 0 failed.**

**What this item did not predict, and the deploy taught.** Merging it changed nothing on its own.
`redeploy.sh` moves images with `kubectl set image` and **applies no manifest at all**, so the new
environment variables never reached the cluster until `apply-demo.sh` ran. `redeploy.md` documents
that as a two-part procedure — set the `newTag` values, commit, then apply — and the first half had
been done without the second.

The failure was safe in the way that matters: the rollout stalled with the previous replica still
serving, so there was **no outage**, and the migration had already completed.

**And it proved `22-05` end to end, which `22-05`'s own tests could not.** No test anywhere in that
item exercised a real broker round trip. Two rows appeared in `role_assignment_projections` within
minutes, each carrying eighteen permissions including `calendar:configure` — written by site
registrations that went through chat's outbox, the broker, and the calendar's consumer, on real
infrastructure.
