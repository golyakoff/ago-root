# AGO Calendar: repository scaffold and platform consumption

- **Stage**: 20
- **Status**: in progress — scaffold built and verified locally; CI green on the new repository is
  the one criterion that cannot be checked before the first push
- **Depends on**: nothing new architecturally — repeats `0-01-repositories-and-skeleton.md`'s and
  `0-02-arch-tests.md`'s own pattern for a second product, against `ago-platform`'s current `main`
  instead of building it from scratch

## Goal

A new repository, `ago-calendar`, exists at `C:/git/ago/ago-calendar` (`repositories.md`'s sibling
layout, a new `calendar/` junction from `ago-root`), builds against a *published* `Ago.Platform.*`
package version exactly the way `ago-chat` does, and has its own `Ago.Calendar.Architecture.Tests`
proving the same layering rules `Ago.Chat.Architecture.Tests` already proves — written first, and
demonstrably failing when deliberately violated, matching `0-02`'s own bar. This item builds no
product behaviour at all; it is the seam AGO Calendar's every later item plugs into, the same role
`0-01`/`0-02` played for AGO Chat.

## Context to read first

`docs/architecture/repositories.md` in full — the repository topology, why the platform is a package
and not a folder, and the "when a new repository is justified" test this item's own existence
satisfies (AGO Calendar deploys independently, a genuinely different load shape from chat).
`docs/conventions/naming-and-structure.md`'s `ago-chat` project layout — this item's own
`ago-calendar` layout mirrors it exactly, project for project, so state explicitly anywhere it
deviates and why. `docs/adr/0012-multi-repo-with-package-boundary.md` and
`docs/adr/0018-github-packages-nuget-feed.md` — the exact restore mechanism (`nuget.config` pointed at
this repository's GitHub Packages feed, `AGO_PLATFORM_PACKAGES_TOKEN`) this item's CI reuses unchanged.
`docs/backlog/0-01-repositories-and-skeleton.md` and `docs/backlog/0-02-arch-tests.md` — the exact
precedent this item repeats for a second product; read both in full rather than re-deriving the
scaffold from first principles. `docs/adr/0027-operator-identity-across-products.md` — states plainly
that `Ago.Calendar.Domain` gets its own `Operator`, never a reference to `Ago.Chat.Domain.Operator`;
this item's arch tests must therefore also assert `Ago.Calendar.*` has no reference whatsoever to any
`Ago.Chat.*` assembly, the same class of test `PersistenceBoundaryTests`/the platform's own
`Ago.Platform.Architecture.Tests` already prove for their own boundaries.

## Scope

- `ago-calendar` repository: `Ago.Calendar.Domain`, `Ago.Calendar.Application` (`Abstractions/`,
  `UseCases/`), `Ago.Calendar.Contracts`, `Ago.Calendar.Infrastructure.Postgres`, `Ago.Calendar.Module`,
  `Ago.Calendar.Api`, `Ago.Calendar.Worker` — no `Webhooks` host yet, nothing in this product's own
  spec needs an outbound-webhook bulkhead the way AGO Chat's CRM integrations did (`adr/0013`); add one
  later if a real caller needs it, not speculatively.
- `nuget.config` restoring `Ago.Platform.*` from this repository's GitHub Packages feed
  (`adr/0018`), plus the documented `AgoCalendarDevOverride` dev-override switch for a change spanning
  both repositories, mirroring `AgoPlatformDevOverride`'s exact shape in `ago-chat` — same env var
  pattern, new name, so both dev overrides can be active in the same shell without colliding.
- `Ago.Calendar.Architecture.Tests`, written first: the same rule set `clean-architecture.md` states —
  `Domain` depends on nothing but `Ago.Platform.Kernel` and the BCL; `Application` does not depend on
  `Infrastructure`/hosts; no platform project depends on `Ago.Calendar.*` (this direction is already
  enforced by the package boundary itself, but a same-repo arch test still documents the intent); and
  the new rule this item adds that neither `ago-chat` nor `ago-platform` has needed before — **no
  `Ago.Calendar.*` project references any `Ago.Chat.*` assembly**, proving `adr/0027`'s decision in
  code, not just in the ADR's own prose.
- `.editorconfig`, nullable, warnings-as-errors, central package management — copied from `ago-chat`'s
  own, not reinvented.
- CI (`.github/workflows/ci.yml`): restore, format-verify, build, test, arch-test on every branch —
  the same four commands `CLAUDE.md`'s own Commands section already documents for the other two
  backend repos, run from `ago-calendar`'s own root.
- `docs/architecture/repositories.md`'s topology table and `docs/conventions/naming-and-structure.md`'s
  repository list both gain `ago-calendar`, matching the existing `ago-chat` row's shape — a real doc
  gap this item closes rather than leaves for whichever later item happens to notice first.

## Out of scope

- Any real domain type (`Tenant`, `Operator`, `Worker`, ...) — `20-01`.
- A `deploy/k8s` overlay or `docker-compose` entry for the new hosts — deferred to whichever item first
  needs to actually run `Ago.Calendar.Api`/`Worker` locally (likely folded into `20-01`'s own
  verification, since a bare host with no domain code is not independently interesting to stand up).
- An `ago-calendar` `Ago.Calendar.Webhooks` host — named above, not built speculatively.

## Done when

- [x] `ago-calendar` builds against a *published* platform package version (not a project reference),
      `dotnet test` is green, and an intentional layering violation (a `Domain` type referencing
      `Npgsql`, and separately, an `Ago.Calendar.*` project referencing an `Ago.Chat.*` assembly) fails
      the arch-test suite — both proven by actually introducing and reverting the violation, matching
      `0-02`'s own verification bar, not merely writing the test and trusting it.
      Done: restores `Ago.Platform.Kernel`/`Abstractions`/`Persistence.Postgres`/`Hosting` **0.16.0**
      (ago-platform's current published version) with no `ProjectReference` into `../ago-platform`
      outside the dev-override branch; format/build/test green with zero warnings; **13 of the 16
      arch tests were each deliberately broken and confirmed red, then reverted** — including a real
      `Ago.Chat.Domain` assembly reference from `Ago.Calendar.Domain`. The three not broken are the
      two `PlatformBoundaryTests` (breaking them means editing `ago-platform`, and they are the pair
      the package boundary already makes true by construction) and nothing else.
- [ ] CI is green on the new repository, restoring `Ago.Platform.*` from the real GitHub Packages feed,
      not a local file feed or a source-pack step. **Blocked on a repository secret**:
      `AGO_PLATFORM_PACKAGES_TOKEN` is a *repository* secret and `ago-calendar` does not have one yet.
      The workflow is written and mirrors `ago-chat`'s exactly; it cannot pass until the PAT is added.
- [x] `repositories.md` and `naming-and-structure.md` updated with the new repository.

## Open questions

None about the scaffold itself. One thing the scaffold *found*, which belongs to the platform rather
than to this item: **`Ago.Platform.Hosting` assumes an ASP.NET Core host.** `IProductModule` — the
platform/product seam a second product must reference to exist at all — sits in the same package as
`AddPlatformObservability`, which hard-depends on `OpenTelemetry.Instrumentation.AspNetCore` and
`OpenTelemetry.Exporter.Prometheus.AspNetCore` (a package with no stable release, ever). So
`Ago.Calendar.Worker`, a plain `Microsoft.NET.Sdk.Worker` host that calls only `AddPlatformKernel()`,
restores eight OpenTelemetry packages including a prerelease one and can still not use the platform's
observability, because a Prometheus scrape endpoint needs an `IEndpointRouteBuilder` a generic host
does not have. `ago-chat` never noticed: its `Worker` and `Webhooks` hosts are `Microsoft.NET.Sdk.Web`
already. That is one product's workaround having quietly become the platform's requirement — exactly
the class of thing a second consumer exists to surface. Splitting the module contract out of the
telemetry package (or gating the ASP.NET Core pieces) is a real platform item; not opened here.
