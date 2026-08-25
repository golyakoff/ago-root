# Fix: the one package every host must reference forces OpenTelemetry on every host

- **Stage**: 7
- **Status**: done
- **Depends on**: nothing — `ago-platform` only, plus a pin move in each consuming repository
  afterwards (see "What each consumer needs")

## Goal

`Ago.Platform.Hosting` holds `IProductModule` — the platform/product seam a host cannot exist
without. Its dependency list is therefore a bill every host of every product pays. Today that list
contains five OpenTelemetry packages, one of them prerelease, which a non-web host cannot use.

Numbered Stage 7 rather than Stage 20 because the code being fixed is `7-01`/`7-02`'s — the item that
*found* it is `20-00`, and "How this was found" says so.

## How this was found

Scaffolding the second product (`backlog/20-00-repository-scaffold-and-platform-consumption.md`,
2026-08-25). `Ago.Calendar.Worker` is a plain `Microsoft.NET.Sdk.Worker` generic host whose
`Program.cs` calls only `AddPlatformKernel()` — two singleton registrations, no telemetry at all.

Read out of `project.assets.json` after a clean restore, not inferred:

| Generic host, `AddPlatformKernel()` only | Packages resolved | of them OpenTelemetry |
|---|---|---|
| against `Ago.Platform.Hosting` `0.17.0` | 39 | 8 |
| against `0.18.0` | 30 | 0 |

Isolating the platform package's own contribution — a bare `Microsoft.NET.Sdk` project referencing
nothing but `Ago.Platform.Hosting` — the same pair reads **26 → 5**, and the packed
`Ago.Platform.Hosting.nuspec` goes from **16 dependencies to 3**.

Among the eight was `OpenTelemetry.Exporter.Prometheus.AspNetCore/1.18.0-beta.1`, which has never
shipped a stable release — the csproj already suppressed `NU5104` for it by name.

`ago-chat` never hit this because all three of its hosts are `Microsoft.NET.Sdk.Web`. **One
product's workaround had quietly become the platform's requirement.**

## The mechanism

Two unrelated things shared one package because they arrived at different times.

`IProductModule` is mandatory: `architecture/clean-architecture.md` defines a host as the thin
composition root that loads one module, so referencing this package is what makes a host a host.
`AddPlatformKernel()`/`SystemClock` sit beside it and are equally universal — the Calendar worker's
whole `Program.cs` is that one call.

`AddPlatformObservability` arrived in `7-01` and grew in `7-02`, bringing the OpenTelemetry SDK, two
instrumentation packages, the OTLP exporter and the Prometheus scrape exporter with it. Nothing about
that was wrong at the time; what was wrong is that it landed in the package with no opt-out.

**And the generic host cannot use what it pays for.** `AddPlatformObservability` calls
`AddAspNetCoreInstrumentation()` and `AddPrometheusExporter()`; the half that makes the latter mean
anything is `app.MapPrometheusScrapingEndpoint()` on an `IEndpointRouteBuilder`, which a generic host
does not have. A generic host calling it would start cleanly and export metrics nothing can scrape.

The same mistake was in the prose. `IProductModule`'s XML doc named `Ago.Chat.Api`/`Worker`/
`Webhooks` as though those were *the* hosts, and `AddPlatformObservability`'s said "every host's
`Program.cs` (`Ago.Chat.Api`/`Worker`/`Webhooks`)". True with one product, false with two, and the
same error in prose that the packaging made in metadata.

## Context to read first

`docs/adr/0046-hosting-carries-only-the-product-module-seam.md` — the decision this item implements,
with the two rejected shapes. `docs/architecture/repositories.md` — why the platform is a package at
all ("it forces the platform to have a version, which forces its API to be thought of as an API"; a
dependency list is the part of that API a consumer cannot decline).
`docs/architecture/clean-architecture.md`'s "What qualifies as platform" — the premature-generalisation
caution that governs why the follow-up gap below is left open rather than guessed at.
`docs/adr/0012-multi-repo-with-package-boundary.md` — the standing argument *against* multiplying
platform packages, which this item has to answer rather than ignore.

## Scope

- Split `Ago.Platform.Observability` out of `Ago.Platform.Hosting`: `AddPlatformObservability`,
  `PlatformObservabilityOptions`/`OtelExporterOptions`, the `ActivitySourceWildcard`/`MeterWildcard`
  constants, all five OpenTelemetry `PackageReference`s and the `NU5104` suppression that belongs
  with the prerelease one.
- Rename the extension class to `ObservabilityServiceCollectionExtensions`. Two same-named types in
  one namespace across two referenced assemblies is `CS0433` at every call site; renaming is the fix,
  not a `using` alias.
- Reduce `Ago.Platform.Hosting` to `IProductModule`, `AddPlatformKernel`, `SystemClock` and exactly
  two `PackageReference`s.
- **An arch test that fails on the current shape**, asserted against the project files rather than
  the compiled assemblies — the harm is in the packed `.nuspec`'s dependency list, which is written
  from `PackageReference` whether or not any type is used in IL.
- Fix both XML docs to describe host *shapes* and name no product.
- **A platform change**: `CHANGELOG.md` entry and version bump, or CI republishes the old package and
  nothing downstream sees the fix. Say plainly that it is source-breaking.
- **The proof is a restore graph, not a build.** A throwaway `Microsoft.NET.Sdk.Worker` project
  restored against locally packed packages, `project.assets.json` read before and after.

## Out of scope

- **A generic-host-shaped telemetry entry point.** After this change `Ago.Calendar.Worker` pays
  nothing and still gets nothing — the gap moved, it did not close. Deliberately not built here:
  nothing in that host has any work to instrument yet, and `clean-architecture.md` is explicit that a
  shape guessed from zero callers is a guess. The split is what makes it addable later inside
  `Ago.Platform.Observability` without touching any host that does not want it.
- **The pin moves in `ago-chat` and `ago-calendar`.** Described below, done by whoever sequences the
  cross-repository change (`repositories.md`'s "Order of operations": platform first, then each
  consumer, each its own branch).
- Anything about what `AddPlatformObservability` *does*. Same signature, same `Otel:*` keys, same
  wildcard values, same behaviour — only where it ships from changed.

## What each consumer needs

**Both are source-breaking, and both fail to compile rather than changing behaviour silently.**

`ago-chat` — the larger of the two:

- `Directory.Packages.props`: `Ago.Platform.*` pin to `0.18.0`, plus a new
  `<PackageVersion Include="Ago.Platform.Observability" Version="0.18.0" />`.
- A `<PackageReference Include="Ago.Platform.Observability" />` in each project that wires or names
  telemetry: `Ago.Chat.Api`, `Ago.Chat.Worker`, `Ago.Chat.Webhooks`, and
  `Ago.Chat.Integration.Tests`.
- `using Ago.Platform.Observability;` in the three hosts' `Program.cs` (each calls
  `AddPlatformObservability`), and in `Ago.Chat.Integration.Tests/TracingEndToEndTests.cs`, which
  names `Ago.Platform.Hosting.ServiceCollectionExtensions.ActivitySourceWildcard` by fully-qualified
  name — that becomes
  `Ago.Platform.Observability.ObservabilityServiceCollectionExtensions.ActivitySourceWildcard`.
- Doc-comment references only, no code change: `Ago.Chat.Contracts/ChatMetrics.cs` and
  `ChatTracing.cs` both point at `Ago.Platform.Hosting.AddPlatformObservability` in prose.
- Everything else — every `using Ago.Platform.Hosting;` for `SystemClock`/`AddPlatformKernel`, and
  `Ago.Chat.Module`'s `IProductModule` implementation — is unaffected.
- Note the ordering hazard: `ago-chat` has an open PR moving its pin to `0.17.0`. That should land
  first; this is a second, separate move on top of it, not a rewrite of it.

`ago-calendar` — trivially small, because it never called the method:

- `Directory.Packages.props`: pin `0.16.0` → `0.18.0`. That is the whole change.
- `Ago.Calendar.Worker` needs no `Ago.Platform.Observability` reference and should not take one —
  taking it would reintroduce exactly the cost this item removed, for a method that host cannot use.
- Its scaffold is unmerged, so the pin can simply be corrected in place rather than moved twice.

## Done when

- [x] `Ago.Platform.Hosting` declares two `PackageReference`s and no OpenTelemetry dependency;
      `Ago.Platform.Observability` exists and carries the telemetry wiring.
- [x] An arch test fails when an OpenTelemetry `PackageReference` is added back — proven by adding
      one and reverting it, not by writing the test and trusting it.
- [x] A generic-host restore graph is measured before and after, from `project.assets.json`.
- [x] Both XML docs name host shapes, not one product's hosts.
- [x] `CHANGELOG.md` `0.18.0`, stating the source break and what each consumer must do.
- [x] `repositories.md`, `clean-architecture.md` and `naming-and-structure.md` no longer describe
      `Ago.Platform.Hosting` as the package that carries telemetry.

## Outcome

Option (b) from `adr/0046` — a separate `Ago.Platform.Observability` package. The reasoning that
decided it is worth repeating here, because the obvious option is the one that fails: **splitting only
the module contract into `Ago.Platform.Hosting.Abstractions` (option (a)) does not fix the measured
defect at all.** `AddPlatformKernel()` and `SystemClock` are just as mandatory as `IProductModule`, so
they would stay behind with the OpenTelemetry packages, and the generic host — whose whole `Program.cs`
is `AddPlatformKernel()` — would reference both packages and resolve all eight anyway. Making (a)
work means moving those two across as well, at which point the "abstractions" package holds concrete
registrations and a live clock, what remains behind is only telemetry, and it is (b) with the names
swapped the wrong way round.

Option (c) — one package, gated — cannot be made to work by the mechanism it implies: a
`PackageReference` is not conditional at restore time *for a consumer*, since NuGet dependency groups
vary by target framework and never by consuming host shape. The only consumer-side opt-out is
`ExcludeAssets="all"` declared per host, which is a workaround in every generic host forever and a
runtime failure the moment a code path reaches the excluded assembly — the same defect relocated into
the product repositories.

**Fails-before, passes-after.** `Ago.Platform.Architecture.Tests.HostingPackagingTests` — three facts:
`Ago.Platform.Hosting`'s `PackageReference` set equals a two-entry allowlist, it carries no
OpenTelemetry dependency, and `Ago.Platform.Observability` is the only packable project that does. All
three fail when an `OpenTelemetry.Instrumentation.AspNetCore` reference is added back to
`Ago.Platform.Hosting`; verified by doing exactly that and reverting it. The allowlist is deliberately
short enough to read, so growing it is a visible act in a diff — the durable half of the fix, since
the packaging was never the disease. Not noticing that one package is mandatory for every host was.

**Package:** `CHANGELOG.md` `0.18.0`, marked breaking and source-breaking.

**Verified:** `dotnet restore`, `dotnet format --verify-no-changes`, `build -c Release` (0 warnings),
`test -c Release` — 88 tests green (85 before, plus the three new arch tests). The throwaway restore
probes were deleted after the measurement.

## Open questions

None. The generic-host telemetry entry point named in "Out of scope" is a follow-up, not an open
question — it needs a host with real work to instrument before its shape can be anything but a guess.
