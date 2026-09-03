# the calendar hosts will not start without broker credentials neither manifest has

- **Stage**: 22
- **Status**: ready
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

- [ ] Both calendar hosts carry `Messaging__RabbitMq__*` naming the **same broker and vhost**
      `ago-chat`'s own Worker publishes to, and both start.
- [ ] The credential question is answered rather than assumed: the same user, or a reader scoped to
      that vhost, with the choice stated.
- [ ] Whatever network policy is needed for the calendar pods to reach the broker exists — `22-05`'s
      author flagged this as out of their lane and it has not been checked.
- [ ] Something fails when the keys go missing again. A pod that will not start is loud; a pod that
      starts and silently never receives a role change is not, and that is the state this item's own
      fix leaves reachable.

## Out of scope

- Proving the projection actually flows end to end in production. Different promise, and it needs a
  real grant to observe; this item is only about the hosts being able to start and connect.

## Context

`22-05` deliberately did not touch `ago-deploy` — it was told not to, and it reported the worker half
of this gap in its own words. The API half is this item's own finding, made while reading the module
rather than the report.
