# 25-07 · Nothing proves a Minimal API endpoint's handler is actually registered in DI

- **Status**: done — `ago-chat#290`, `ago-calendar#66`. Independently re-verified by the managing
  session before merging (its own `dotnet build`/`test` runs against the worker's own worktrees —
  3316/3316 `ago-chat` tests, 830/830 `ago-calendar` tests, both matching the worker's reported counts
  exactly). `RouteHandlerDiRegistrationTests` lands in both `ago-chat` and `ago-calendar`; `adr/0170`
  records the design and the rejected alternatives. While building it, the same test caught a real,
  live, unfixed instance of `25-06`'s own bug class — `GetSuspensionStatusForSiteHandler` (`25-70`,
  merged hours earlier the same night) was mapped and never registered — fixed in the same change,
  before it could crash the API host's next real restart.
- **Date found**: 2026-09-09, alongside `25-06`
- **Depends on**: none

## Why this exists

`25-06` found `PreviewOperatorInviteHandler` mapped as a Minimal API endpoint parameter but never
registered in `ChatModule.cs` — a defect that crashed the live demo stand's API host the moment
`AuthorizationPolicyCache` enumerated every endpoint, and had been sitting in `main` since `23-70`
merged, undetected. `OperatorInviteEndpointTests` calls the exact broken route and passes, because its
`TestHost` composition is not `Program.cs`'s own composition and never happens to be the first request
against a named authorization policy — the one condition that triggers Minimal API's lazy, whole-app
endpoint-metadata build. `25-06`'s own text names this as a real, unfixed gap in the test suite, not
only in that one handler.

## What this item is

A test — architecture-level, in whichever host-adjacent test project can compose the real
`Program.cs`/`ChatModule.cs` wiring (or close enough that a missing DI registration fails it the same
way it fails production) — that walks every route this host maps and confirms every parameter type
Minimal API would infer as a service actually resolves from the built `IServiceProvider`. It should
fail the way `25-06`'s bug would have failed it, proven by reverting `25-06`'s one-line fix and watching
this new test catch it (a fails-before against the actual historical defect, not an invented one).

## Where this is likely to go wrong

- **Building the real composition root in a test is the whole difficulty.** `Program.cs` wires
  Keycloak, Postgres, RabbitMQ and more — a test that needs all of that running defeats the purpose of
  a fast check that runs before a deploy is attempted. Whether this can validate registrations without
  a live database/broker (e.g., building the `IServiceCollection` and calling `BuildServiceProvider(validateScopes: true)` with fakes standing in for what genuinely needs a connection) is the first thing
  to establish, before writing the check itself.
- **False confidence is worse than no test.** A check that only walks endpoints it already knows how
  to enumerate, or that silently skips a route it cannot classify, would look green while missing
  exactly the next version of this bug. Whatever it builds should assert its own coverage count against
  the real route table, the same way `queue-audit.sh` refuses to answer rather than guess.
- **`ago-calendar` has the identical shape** (`Ago.Calendar.Module`, its own Minimal API routes) and
  should get the same check if the mechanism generalizes, rather than a chat-only fix that leaves the
  sibling product with the identical blind spot.

## Done when

- [x] A test fails against `25-06`'s defect reverted, and passes with it fixed - a real fails-before
      against a real historical bug. Reverted `services.AddScoped<PreviewOperatorInviteHandler>();`
      in `ChatModule.cs`: `RouteHandlerDiRegistrationTests.EveryMappedRouteHandlerParameterResolves_ReproducesThe25_06Crash`
      failed with the identical `handler | UNKNOWN` text `25-06`'s own pod log carried; restored,
      confirmed green. A second, unplanned fails-before landed in the same run: the same test caught a
      live, currently-unfixed instance of this exact bug class in `main` right now —
      `GetSuspensionStatusForSiteHandler` (`25-70`, merged hours earlier) was mapped and never
      registered. Fixed in the same change (one line in `ChatModule.cs`, mirroring its siblings).
- [x] The test runs as part of the ordinary `dotnet test` suite (not a separate manual step), so CI
      catches the next one before a deploy does. `Ago.Chat.Integration.Tests` (1218/1218) and
      `Ago.Calendar.Integration.Tests` (332/332) both green with the new tests included, no separate
      invocation needed.
- [x] Whether `ago-calendar` needs the identical check is decided and stated, not left implicit.
      **Decided: yes, and built in this same change.** `Ago.Calendar.Api`'s own `Program.cs` already
      carries `public partial class Program;` for an existing `WebApplicationFactory<Program>`-based
      test fixture (`CalendarApiFactory`) — every existing test using it was already triggering the
      identical `AuthorizationPolicyCache` mechanism as an unnamed side effect, so the new
      `RouteHandlerDiRegistrationTests` there needed no `CompositionRoot`-style extraction, only an
      explicit, self-checking assertion of a guarantee that was real but previously undocumented. No
      production code changed in `ago-calendar`, and no live bug was found there.
