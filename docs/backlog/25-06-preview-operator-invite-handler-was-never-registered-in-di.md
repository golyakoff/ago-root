# 25-06 · `PreviewOperatorInviteHandler` was never registered in DI

- **Status**: done
- **Date found**: 2026-09-09, live on the demo stand
- **Depends on**: none

## What happened

Deploying tonight's work (`23-74`, `23-30`, `23-68`, `23-60`) to the demo cluster, `ago-chat-api`'s new
replica crash-looped on startup — `Startup probe failed`, killed and restarted five times in under
five minutes. The previous replica kept serving throughout (`deploy.sh`'s rollout guard held), so there
was no outage, but the deploy could not complete.

The pod's own log named it precisely:

```
Unhandled exception. System.InvalidOperationException: Failure to infer one or more parameters.
Parameter           | Source
request             | Body (Inferred)
handler             | UNKNOWN
rateLimiter         | Services (Inferred)
rateLimitOptions    | Services (Inferred)
```

`OperatorInviteEndpoints.HandlePreviewAsync` (`POST /api/v1/operator-invites/preview`, `23-70`) takes a
`PreviewOperatorInviteHandler handler` parameter. Its sibling handlers,
`CreateOperatorInviteHandler`/`RedeemOperatorInviteHandler`, are both `services.AddScoped<...>()` in
`ChatModule.cs`; `PreviewOperatorInviteHandler` never was. Minimal API's `RequestDelegateFactory` cannot
classify an unregistered service-shaped parameter as Body, Route or Service, and fails hard the moment
`AuthorizationPolicyCache` enumerates every mapped endpoint — which happens once, lazily, on the first
request anywhere in the process that needs a named authorization policy. That first request crashes the
whole host, not just the one route, taking every `BackgroundService` down with it (the log's own
cascade of `RabbitMQ.Client.Exceptions.OperationInterruptedException` lines are the consequence of the
host stopping, not a second bug).

**Why this went unnoticed since `23-70` merged**: `OperatorInviteEndpointTests` exercises
`/operator-invites/preview` through a real HTTP call and passes — 15/15, confirmed by rerunning it
against the unfixed code before writing this item. That test class builds its own `TestHost`
composition rather than the production `Program.cs`/`ChatModule.cs` wiring, and its calls never
happen to be the *first* request against a named authorization policy in that process, so the lazy,
whole-app endpoint enumeration this bug depends on is never triggered. The gap is real: nothing in this
repository's test suite proves that every type a minimal-API endpoint takes as a parameter is actually
resolvable from the composed DI container the way `Program.cs` builds it.

## What was done

One line: `services.AddScoped<PreviewOperatorInviteHandler>();` in `ChatModule.cs`, next to its two
sibling registrations, plus the missing `using`. Verified live: redeployed the fixed image to the demo
node, the new replica passed its startup probe on the first attempt and serves traffic.

## Done when

- [x] `PreviewOperatorInviteHandler` is registered in `ChatModule.cs`.
- [x] The fix is proven against the live incident, not only a synthetic repro: the same commit's image
      redeployed to `ago-demo` and the previously crash-looping replica came up clean.
- [x] `dotnet build`/`format`/the full local suite stay green (`Ago.Chat.Architecture.Tests` 43/43,
      full solution build 0 warnings/0 errors).

## Left open, deliberately

**No regression test added here.** `OperatorInviteEndpointTests` already calls the broken endpoint and
already passes against the unfixed code — adding another test in that same harness would not have
caught this and would not catch the next one either, because the harness itself is the gap. What would
catch this class of bug is a test that composes the DI container the same way `Program.cs` really does
and asserts every Minimal API handler-shaped parameter across every mapped endpoint resolves — that is
a real piece of test infrastructure, not a one-line addition, and building it under deploy pressure
risks getting the harness wrong in a way nobody checks carefully. Filed separately as `25-07`.
