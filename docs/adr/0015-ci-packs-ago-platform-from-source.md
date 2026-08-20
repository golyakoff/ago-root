# ADR-0015: `ago-chat`'s CI packs `ago-platform` from source, no hosted feed yet

- **Status**: Accepted
- **Date**: 2026-08-21
- **Stage**: 0

## Context

`0-04-ci-pipeline` requires `ago-chat`'s CI to build against a *published* `Ago.Platform.*` package,
never a `ProjectReference` - that is the whole point of the dev-override switch existing
(`repositories.md`, `Directory.Build.props`). Locally this already works: `ago-platform` packs into
`C:\git\ago\.nuget-feed\`, and `ago-chat`'s `nuget.config` lists it as a source. A CI runner has no
such path - it is a fresh machine with nothing but what the workflow checks out - so CI needs its own
answer to "where does the package come from."

The obvious real-world answer is a hosted NuGet feed: GitHub Packages, using the repository's own
`GITHUB_TOKEN` to publish from `ago-platform`'s workflow. Consuming it from `ago-chat`'s workflow is
the complication - GitHub does not allow anonymous reads of NuGet packages even on a public
repository (unlike container images on `ghcr.io`), so `ago-chat`'s CI would need a personal access
token with `read:packages`, stored as a repository secret. That is a small, ordinary piece of CI
infrastructure, not a business secret - but it is still a credential to create and rotate, on a
project that is otherwise fully self-contained and offline-capable by design.

## Decision

For now, `ago-chat`'s CI does not consume a hosted feed at all. Its workflow checks out
`golyakoff/ago-platform`'s `main` branch into a sibling folder and runs `dotnet pack` on it, in the
same job, into a throwaway local file feed (`nuget-feed-ci/`) that a CI-only `nuget.ci.config`
(`<clear/>` + nuget.org + that folder) points at. `ago-chat`'s own `nuget.config` - the one a
developer's machine uses - is untouched.

This still tests the thing that matters: the build goes through a real `.nupkg` boundary, selected by
`PackageReference` with a *version number* (`Directory.Packages.props`), never a `ProjectReference`
into platform source that happens to be sitting on disk. If `ago-chat` pins a version `ago-platform`'s
current `main` does not produce, restore fails loudly - which is the version-drift signal this whole
mechanism exists to catch. `AgoPlatformDevOverride` is never set in CI, so a branch merged with the
dev override still left on fails here exactly as it always would have.

`ago-platform`'s own CI still packs and uploads a `.nupkg` on every push to `main` (as a workflow
artifact, for a human to inspect) - that half of `0-04-ci-pipeline`'s scope needed no registry
decision either way, and having it run independently keeps `ago-platform`'s CI honest even before
`ago-chat`'s consumes anything durable.

## Consequences

- Zero secrets added to either repository or its CI - consistent with `repositories.md`'s "no secrets
  ever," even though a package-registry PAT would have been the ordinary infrastructure kind, not the
  business kind that rule is really about.
- `ago-chat`'s CI rebuilds `ago-platform` from source on every run. That costs real minutes (a `dotnet
  pack` before the restore even starts) and means CI never proves a specific *published* version
  survives unchanged across two independent builds - a subtle gap versus a real feed, where the same
  bytes are restored every time.
- `ago-chat`'s workflow now depends on `ago-platform`'s repository being public and its `main` branch
  building cleanly at all times - a `main` that does not pack breaks `ago-chat`'s CI too, coupling the
  two pipelines more tightly than a versioned feed would.
- No version pinning by tag: the checkout always takes `ago-platform`'s current `main` `HEAD`, not the
  commit that produced the version `ago-chat` actually declares in `Directory.Packages.props`. In
  practice this is caught by NuGet refusing to restore a version number `main` does not currently
  produce, but the failure mode is "wrong version, if any" rather than "exactly this artifact."
- Revisit when any of these stop being true: a second product repository needs the same package (more
  than one CI job re-deriving the same artifact), a real release cadence needs a durable version
  history independent of `main`'s current tip, or Stage 8's public deploy wants the same package
  mechanism CI already exercises. GitHub Packages, with a `read:packages` PAT as a repository secret
  in each consumer, is the concrete next step at that point.

## Alternatives considered

- **GitHub Packages NuGet feed** - the standard, reviewer-recognizable pattern; `ago-platform` publishes
  with its own `GITHUB_TOKEN`, `ago-chat` restores with a `read:packages` PAT secret. Rejected for now
  because it is the only option here that requires creating and storing a credential, on a project at
  a stage where nothing yet needs the durability a real feed buys - it is the better answer once
  something does (see "Consequences" above).
- **Cross-job artifact download** - `ago-chat`'s workflow downloads the `.nupkg` `ago-platform`'s CI
  already uploads as a build artifact, instead of re-packing from source. Rejected: GitHub Actions'
  artifact API does not allow one repository's workflow to read another repository's artifacts without
  the same kind of PAT the registry option needs, so this trades the pack-from-source cost for the
  registry option's secret cost while gaining neither option's full benefit.
- **A local NuGet feed committed to the repository** - vendoring `.nupkg` files into `ago-chat` or a
  shared location under version control. Rejected outright: binary artifacts in git history are exactly
  what a package registry exists to avoid, and every platform bump would mean a diff nobody can review
  meaningfully.
