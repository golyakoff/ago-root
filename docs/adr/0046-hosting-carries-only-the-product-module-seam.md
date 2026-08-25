# ADR-0046: `Ago.Platform.Hosting` carries only the module seam; telemetry ships as `Ago.Platform.Observability`

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 7 (the code changed) / 20 (the item that found it)

## Context

`Ago.Platform.Hosting` holds two unrelated things that arrived at different times.

The first is `IProductModule` — **the platform/product seam**. A host cannot exist without it: a host
is defined as the thin composition root that loads exactly one module
(`architecture/clean-architecture.md`). Every host of every product in every product repository must
reference this package. It is the one package with no opt-out.

The second is `AddPlatformObservability` (`7-01`, `7-02`), which brought five OpenTelemetry
`PackageReference`s with it — including `OpenTelemetry.Exporter.Prometheus.AspNetCore`, which has
never shipped a stable release and whose `NU5104` warning the csproj already suppressed by name.

Those two things sitting in one package was invisible for as long as AGO Chat was the only product,
because all three of its hosts (`Api`, `Worker`, `Webhooks`) are `Microsoft.NET.Sdk.Web`. Scaffolding
the second product (`backlog/20-00`) made it visible immediately. `Ago.Calendar.Worker` is a plain
`Microsoft.NET.Sdk.Worker` generic host whose `Program.cs` calls only `AddPlatformKernel()` — two
singleton registrations, no telemetry. Its restore graph nevertheless resolved **eight OpenTelemetry
packages**, the prerelease Prometheus exporter among them, read out of `project.assets.json` after a
clean restore rather than inferred.

And it could not have used them if it wanted to. `AddPlatformObservability` calls
`AddAspNetCoreInstrumentation()` and `AddPrometheusExporter()`; the scrape endpoint that makes the
latter mean anything is `app.MapPrometheusScrapingEndpoint()` on an `IEndpointRouteBuilder`, which a
generic host does not have. A generic host that called it would start cleanly and export metrics
nothing could ever scrape.

**One product's workaround had quietly become the platform's requirement.** That sentence is the
whole finding. It is a sharper failure than a merely fat package, because
`architecture/repositories.md`'s stated reason for the package boundary is that "it forces the
platform to have a version, which forces its API to be thought of as an API" — and a package's
dependency list *is* part of its API, the part a consumer cannot decline.

## Decision

**`Ago.Platform.Hosting` is reduced to what a host of any shape genuinely cannot do without**:
`IProductModule`, `AddPlatformKernel()`, and `SystemClock`. Its declared dependencies are exactly
two — `Microsoft.Extensions.Configuration.Abstractions` and
`Microsoft.Extensions.DependencyInjection.Abstractions`.

**Telemetry wiring moves to a new package, `Ago.Platform.Observability`**, which carries
`AddPlatformObservability`, `PlatformObservabilityOptions`/`OtelExporterOptions`, the
`ActivitySourceWildcard`/`MeterWildcard` constants, all five OpenTelemetry `PackageReference`s and
the `NU5104` suppression that belongs with the prerelease one. Hosts that serve HTTP reference it;
generic hosts do not.

The extension class is renamed `ServiceCollectionExtensions` → `ObservabilityServiceCollectionExtensions`.
`Ago.Platform.Hosting` keeps a class by the former name, and in .NET two same-named types in the same
namespace from two referenced assemblies is `CS0433` at every call site. The rename removes the
collision; a `using` alias would only paper over it per file, which this project has already decided
against once.

**Nothing else about the method changes** — same signature, same `Otel:*` configuration keys, same
wildcard values, same behaviour. This is a packaging decision, not a redesign.

Two arch tests make it non-regressable, asserted against the **project files** rather than the
compiled assemblies: `Ago.Platform.Hosting`'s `PackageReference` set must equal a two-entry
allowlist, and `Ago.Platform.Observability` must be the only packable project carrying an
OpenTelemetry dependency. Project files, not IL, because the harm lives in the packed `.nuspec`'s
dependency list, which is written from `PackageReference` whether or not any type from that package
is ever used — precisely the case that hurts a consumer most: paid for, unused, invisible.

## Consequences

- **Measured, not asserted.** A `Microsoft.NET.Sdk.Worker` generic host calling only
  `AddPlatformKernel()` resolved **39 packages, 8 of them OpenTelemetry** before and resolves **30,
  0 of them OpenTelemetry** after. Isolating the platform package's own contribution (a bare
  `Microsoft.NET.Sdk` project referencing nothing else), the same pair reads **26 → 5**. The packed
  `Ago.Platform.Hosting.nuspec` goes from **16 dependencies to 3**. Both graphs read from
  `project.assets.json` after a clean restore against locally packed packages.
- **Source-breaking for both existing consumers, deliberately and loudly.** Every host that wires
  telemetry needs one new `PackageReference` and one new `using`. It fails to compile if it does not;
  there is no version of this that changes behaviour silently. `ago-chat`'s three hosts and its
  `TracingEndToEndTests` are affected; `ago-calendar`'s unmerged scaffold is not (it never called
  the method) beyond moving its pin. This is a pre-1.0 package with exactly two consumers, both in
  this workspace, which is the cheapest this break will ever be.
- **A second platform package now exists, and that is a real cost this project has argued against
  before.** `adr/0012` rejects splitting the platform per adapter because it "multiplies the version
  matrix with no independent consumer to justify it", and `architecture/repositories.md` restates the
  test as: a new *repository* is justified only when the thing versions or deploys independently.
  This is a new project inside one repository, not a new repository — it packs, versions and
  publishes in the same CI run as the other nine, so the version matrix does not multiply at all.
  What it costs is one more line in `Directory.Packages.props` for consumers who want telemetry, and
  one more name a reader has to learn.
- **A generic host still has no telemetry — the gap moved, it did not close.** After this change
  `Ago.Calendar.Worker` pays nothing and gets nothing. A generic-host-shaped entry point (tracing plus
  an OTLP metrics push, no ASP.NET Core instrumentation, no scrape endpoint) is the obvious follow-up
  and is deliberately not guessed at here: `architecture/clean-architecture.md` warns that an
  abstraction shaped from zero live callers is a guess, and today nothing in `Ago.Calendar.Worker`
  has any work to instrument. The split is what makes that addable later inside
  `Ago.Platform.Observability`, touching no host that does not want it.
- **`Ago.Platform.Hosting`'s dependency list is now a reviewable claim rather than an accident.** The
  arch test's allowlist is short enough to read, and adding to it is a visible act in a diff with a
  named cost — which is the actual durable fix. The packaging was never the disease; not noticing
  that one package is mandatory for every host was.

## Alternatives considered

- **(a) Split only the module contract into `Ago.Platform.Hosting.Abstractions`.** The obvious shape,
  and it does not work. `AddPlatformKernel()` and `SystemClock` are also things every host needs —
  `Ago.Calendar.Worker`'s entire `Program.cs` is that one call — and they would stay behind in
  `Ago.Platform.Hosting` with the OpenTelemetry packages. The generic host would reference both and
  resolve all eight packages anyway: the measured defect survives the split untouched. Making (a)
  work requires moving `AddPlatformKernel` and `SystemClock` into the "abstractions" package too, at
  which point it holds concrete registrations and a live clock, is no longer an abstractions package
  by any reading, and what remains behind is only the telemetry wiring — which is (b) with the two
  names swapped, and the worse pair of names, since the package a consumer must reference should be
  the one called `Hosting`.
- **(c) Keep one package and gate the ASP.NET Core pieces.** Cannot be made to work by the mechanism
  it implies. A `PackageReference` is not conditional at restore time *for a consumer*: NuGet's
  dependency groups vary by target framework, never by what kind of host is consuming, so
  `Condition=` on the platform's own `PackageReference` is evaluated when the platform is packed, not
  when a product restores. The dependency set in the `.nuspec` is one fixed list. The only way a
  consumer declines a transitive dependency is by declaring it itself with `ExcludeAssets="all"` —
  which puts a per-host workaround in every generic host that must be kept correct forever, and blows
  up at runtime the moment any code path reaches the excluded assembly. That is the same defect this
  ADR is fixing, relocated into the product repositories and made each product's problem. There is a
  narrower reading of (c) — keep one package and drop the OpenTelemetry references, requiring hosts
  to supply them — but that is a package whose main method does not compile against its own declared
  dependencies, which is worse than either split.
- **Do nothing; let `Ago.Calendar.Worker` carry the eight packages.** Tempting, since they cost
  restore time and image size rather than correctness. Rejected on the grounds that a *prerelease*
  package sits in the mandatory dependency set of every host in the system, and that the defect
  scales with products rather than staying at one: the third host shape pays it too, and each new one
  makes the fix more expensive than it is today, with two consumers, both unreleased, both in this
  workspace.
