# ADR-0170: A Minimal API DI-registration proof composes through an extracted method, not a live `WebApplicationFactory<Program>` or a second hand-written list

- **Status**: Accepted
- **Date**: 2026-09-14
- **Stage**: 25 (defect follow-through)

## Context

`25-06`: `PreviewOperatorInviteHandler` was mapped as a Minimal API endpoint parameter in `23-70` and
never registered in `ChatModule.cs`. ASP.NET Core's `RequestDelegateFactory` cannot classify an
unregistered service-shaped parameter, and throws hard the moment anything forces
`EndpointDataSource.Endpoints` to build for the whole process - which `UseAuthorization()`'s own
`AuthorizationPolicyCache` constructor does, once, the first time the host starts (not per request,
and not at `Map...()` call time). This crashed `ago-chat-api`'s new replica on the live demo stand.
`OperatorInviteEndpointTests` called the exact broken route and passed, because its own `TestHost`
hand-rebuilds a subset of `Program.cs`'s registrations rather than composing what `Program.cs` really
composes - it never happened to be the first thing in its process to trigger the enumeration, and
would not have caught the bug even if it had, since its subset never included the broken registration
to begin with.

`ago-chat-api`'s `Program.cs` is top-level statements: ~520 lines of `builder.Services.Add...` calls
and `app.MapXxxEndpoints()` calls, with no method a test can call into. `Program.cs` also runs real
infrastructure calls between `builder.Build()` and `app.Run()` - `EnsureSchemaIsCurrentAsync` (a real
Postgres round trip) and an eager `IVisitorSigningKeyRing` resolution - and registers every real
`IHostedService` (`ConnectionHeartbeat`, `NodeDeliveryConsumer`, `MessagePipelineWorkerHost`, ...),
several of which dial Redis or RabbitMQ for real the moment the generic host starts them.

Two existing integration test files (`OperatorInviteEndpointTests`, `ChannelStatusEndpointsTests`)
already establish the alternative this repository had been using: hand-rebuild the slice of
`Program.cs`'s registrations a given test needs, in the test file itself, using real production types.
`25-06`'s own report names this pattern as the actual gap - a hand-rebuilt list can omit exactly the
registration `Program.cs` needs, and nothing catches the omission because nothing compares the two
lists.

## Decision

`Ago.Chat.Api/CompositionRoot.cs` is a new, purely mechanical extraction of `Program.cs`'s own
registration and route-mapping statements into two static methods,
`CompositionRoot.ConfigureServices(WebApplicationBuilder)` and `CompositionRoot.MapEndpoints(WebApplication)`
- byte-for-byte the same statements, in the same order, moved rather than rewritten. `Program.cs` now
calls both; nothing else about its behaviour changes. `Ago.Chat.Integration.Tests/RouteHandlerDiRegistrationTests`
calls the same two methods to build a service collection and a `TestServer`-backed host, so a
registration or a route added to one is automatically exercised by the other - not by a maintained
second list, by construction.

That test asserts two distinct things, because they catch different bug shapes:

1. `services.BuildServiceProvider(new ServiceProviderOptions { ValidateOnBuild = true, ValidateScopes = true })` -
   every registered service's own constructor dependency graph is structurally satisfiable. Verified
   experimentally, not assumed from documentation, that this never invokes a factory delegate or a
   constructor: a throwaway `IServiceCollection` with a singleton registered via a factory that
   increments a counter, built with `ValidateOnBuild = true` against an otherwise-resolvable graph,
   left the counter at zero. This is what makes the check safe to run with no live Postgres/Redis/
   RabbitMQ connection, confirmed per-technology too (`NpgsqlDataSourceBuilder.Build()` never opens a
   socket; `RabbitMqConnection`'s constructor only stores its options; `IConnectionMultiplexer`'s
   `ConnectionMultiplexer.Connect(...)` sits behind a factory delegate ValidateOnBuild never calls).
2. Building the real `WebApplication` and calling `app.StartAsync()` - the exact trigger `25-06`'s own
   crash depended on, reproduced with no HTTP request ever sent. `Program.cs`'s own `IHostedService`
   registrations and the generic host's separate `IStartupValidator` (`.ValidateOnStart()`'s own
   mechanism, found live to be independent of `IHostedService` and not removable by filtering it) are
   both stripped from the collection first - neither can carry a Minimal API endpoint's own
   unregistered-parameter bug, and both would otherwise force a live connection or demand every
   `ValidateOnStart()`-tagged option's real value.

Test 1 alone does not catch `25-06`'s own bug shape: `PreviewOperatorInviteHandler` was never a
constructor dependency of any other registered service, only a route delegate's own parameter, so
`ValidateOnBuild`'s graph walk never reaches it. Test 2 is what actually reproduces the historical
failure - confirmed by literally reverting `25-06`'s fix and watching test 2 fail with the identical
"Parameter | Source ... handler | UNKNOWN" text the incident's own pod log carried, while test 1 stayed
green. A third test asserts the mapped-route count stays above an observed floor, so a future
`CompositionRoot.MapEndpoints` that silently dropped a whole route group fails loudly rather than
passing with quietly-reduced coverage - fault-injected by temporarily raising the floor with every
route still mapped, confirming only that one assertion goes red.

While building this, the same new test caught a live, currently-unfixed instance of `25-06`'s own bug
class: `GetSuspensionStatusForSiteHandler` (`25-70`, merged hours earlier the same night) was mapped in
`SiteSuspensionEndpoints.cs` and never registered in `ChatModule.cs`. Fixed in the same change
(`ChatModule.cs`) as the one-line registration its three sibling suspension handlers already had.

## Consequences

- `Program.cs` is 512 lines shorter and reads as its own real per-host concerns (health checks, the
  schema guard, eager key-ring resolution, forwarded-headers/CORS/auth middleware, SignalR's own hub
  maps) plus two calls into `CompositionRoot`. Nothing in its behaviour changed - confirmed by the full
  existing suite staying green (`3316` tests across `Ago.Chat.Domain.Tests`, `Ago.Chat.Application.Tests`,
  `Ago.Chat.Architecture.Tests`, `Ago.Chat.Integration.Tests`, `Ago.Chat.Concurrency.Tests`) both before
  and after the extraction.
- A future registration or route genuinely cannot be added to `Program.cs` without `RouteHandlerDiRegistrationTests`
  seeing it, because there is only one method that maps it. This is the property `OperatorInviteEndpointTests`/
  `ChannelStatusEndpointsTests` never had, and still do not have - they are unaffected, kept as
  real-HTTP-response-shape tests, not migrated.
- New cost: `CompositionRoot.cs` is a project file that exists for no reason other than testability - a
  second thing to keep in sync with `Program.cs`'s own comments/ordering conventions, mechanically, by
  future edits (add a registration in `Program.cs`'s old spot and it silently lands outside
  `CompositionRoot`, unexercised by this test, exactly the drift this ADR exists to prevent - reviewers
  should watch for a `builder.Services.Add...`/`app.Map...` line added directly to `Program.cs` rather
  than inside `CompositionRoot`).
- The two config values `CompositionRoot.ConfigureServices` demands synchronously
  (`AGO_CHAT_CONNECTION_STRING`, `Auth:Keycloak:Authority`) plus a third found only by running the test
  (`Otel:Exporter:Endpoint`, validated eagerly by `AddPlatformObservability` itself) are now implicitly
  part of this test's own contract - a fourth eager guard added anywhere in the composition will fail
  this test with a clear exception naming the missing key, not silently.
- `Ago.Calendar.Api` gets the equivalent test (`Ago.Calendar.Integration.Tests/RouteHandlerDiRegistrationTests`)
  with no `CompositionRoot`-equivalent at all: its own `Program.cs` already ends in
  `public partial class Program;`, added for an existing `WebApplicationFactory<Program>`-based test
  fixture (`CalendarApiFactory`), so every existing test using it was already triggering the identical
  `AuthorizationPolicyCache` mechanism as an unnamed side effect. The new test only makes that guarantee
  explicit and self-checking; it changed no production code there, and found no live bug.

## Alternatives considered

- **`WebApplicationFactory<Program>` against `ago-chat-api`'s unmodified entry point** (adding only the
  `public partial class Program;` marker `ago-calendar` already carries). Rejected for `ago-chat`
  specifically: everything between `builder.Build()` and `app.Run()` in its `Program.cs` runs
  unconditionally under `WebApplicationFactory` too, and that includes `EnsureSchemaIsCurrentAsync`
  (a real Postgres call) and every real `IHostedService`'s own `StartAsync` (real Redis/RabbitMQ
  dials) - a fast, connection-free check would have needed exactly the same
  `CompositionRoot`-shaped extraction anyway, just reached through a heavier, live-infra-requiring
  door. `ago-calendar`'s own `Program.cs` has neither of those two extra steps, which is the entire
  reason this alternative already works there for free.
- **A second hand-written test-only composition**, mirroring `ChannelStatusEndpointsTests`' own
  pattern but covering every route instead of three. Rejected: a hand-maintained list, however
  complete on the day it is written, has the identical structural failure mode `25-06` already
  demonstrated - a future route or registration can be added to `Program.cs` and not mirrored, and
  nothing forces the mirror. `CompositionRoot` removes the second list rather than completing it.
- **Skipping the `ValidateOnBuild` structural check and keeping only the `TestServer`-based
  reproduction.** Rejected: the two catch different bug shapes (an unregistered constructor dependency
  of a registered service vs. an unregistered Minimal API route parameter), and the structural check's
  own no-live-connection property was worth establishing and keeping on record, not only trusting the
  `TestServer` path's own filtering to be sufficient by inspection.

## Current-state documents this changes

`docs/conventions/testing.md`'s Integration tests section, in the same change - the
`CompositionRoot`/`RouteHandlerDiRegistrationTests` pattern is now the documented shape for proving a
Minimal API host's own DI-registration completeness, for any current or future host in this
repository.
