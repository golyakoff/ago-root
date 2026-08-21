# ADR-0018: `ago-platform` publishes to GitHub Packages; `ago-chat`'s CI restores from it

- **Status**: Accepted
- **Date**: 2026-08-21
- **Stage**: 2
- **Supersedes**: `adr/0015`

## Context

`adr/0015` deliberately deferred a hosted NuGet feed: at Stage 0, nothing needed the durability it
buys, and a `read:packages` PAT was a credential to create and rotate on a project that was otherwise
credential-free. `ago-chat`'s CI worked around it by checking out `ago-platform`'s `main` and packing
it from source, fresh, in the same job.

That workaround has a real cost the ADR already named: CI never proves a specific *published* version
survives unchanged across two independent builds, `ago-chat`'s pipeline is coupled to `ago-platform`'s
`main` always building cleanly, and there is no durable version history independent of `main`'s
current tip. Building 2-04 surfaced a concrete instance of the gap: `ago-platform` shipped three
patch versions (0.2.0 → 0.2.2) in one session, entirely through local `dotnet pack` runs into a
developer machine's `.nuget-feed\` folder - nothing durable recorded any of it, and `ago-platform`'s
own CI `pack` job was quietly packing `main` under a stale version number, because it reads the
version from `CHANGELOG.md`, which had not been updated to match. A hosted feed does not fix a
forgotten changelog entry by itself, but it does mean the same drift shows up as a loud restore
failure in CI instead of staying invisible.

## Decision

`ago-platform`'s CI `pack` job, on every push to `main`, pushes every `.nupkg` it builds to this
repository's own GitHub Packages NuGet feed (`https://nuget.pkg.github.com/golyakoff/index.json`),
using the workflow's default `GITHUB_TOKEN` with `packages: write` permission - no new secret needed
to *publish*, since a repository's own token can always write to its own package feed. The existing
"upload as a workflow artifact" step stays alongside it, so a reviewer without package-read access can
still grab a `.nupkg` straight from the Actions run.

`ago-chat`'s CI restores `Ago.Platform.*` from that feed via `nuget.ci.config`, authenticated with
`AGO_PLATFORM_PACKAGES_TOKEN` - a classic PAT scoped to `read:packages` only, stored as an
`ago-chat` repository secret. GitHub does not allow anonymous reads of NuGet packages even on a public
repository, so this secret is unavoidable for the *consuming* side; it is ordinary CI infrastructure,
not a business secret, and carries no more access than "see published package bytes." The
`Checkout ago-platform (main)` + `dotnet pack ... from source` steps are removed entirely -
`ago-chat`'s CI now restores the exact bytes `ago-platform`'s CI published, the same way a production
consumer would, rather than re-deriving them.

Local development is unchanged: `dotnet pack` into `C:\git\ago\.nuget-feed\` and `nuget.config`
pointing at that folder remain the fast local loop (`repositories.md`). No developer machine needs a
PAT just to build - GitHub Packages is CI-only. `AgoPlatformDevOverride`'s `ProjectReference` swap for
genuinely cross-repository work is also unchanged.

`ago-platform/CHANGELOG.md` gained the two entries (0.2.1, 0.2.2) it was missing, closing the version
drift this ADR's Context section describes - the change that makes the version-mismatch failure mode
this decision is meant to surface actually possible to hit cleanly going forward.

## Consequences

- `ago-chat`'s CI restore now proves the exact published artifact resolves and works, not a
  freshly-repacked equivalent - the gap `adr/0015` named as its main cost is closed.
- One new secret exists: `AGO_PLATFORM_PACKAGES_TOKEN` in `ago-chat`, a classic PAT scoped to
  `read:packages` only. It must be rotated if it expires or leaks; GitHub classic PATs do not rotate
  themselves. `repositories.md`'s "no secrets, ever" is about business/customer secrets in the
  repository content itself - this is ordinary CI credential hygiene, held only in GitHub's secret
  store, never in a file.
- `ago-chat`'s CI restore now depends on GitHub Packages being reachable, in addition to
  `ago-platform`'s `main` building and publishing cleanly - one more external dependency than the
  from-source workaround had, in exchange for the correctness guarantee above.
- `ago-platform`'s CI is slightly slower per run on `main` (one more network push), and every
  merge to `main` now permanently publishes a package version - a version bumped and merged without
  a corresponding `ago-chat` consumer still gets published. That is intentional: it matches what a
  real release process does, and is the same trade a production package feed always makes.
- `dotnet nuget push --skip-duplicate` makes a re-run of the `pack` job on the same commit idempotent
  instead of a hard failure, but does **not** protect against re-using a version number for genuinely
  different content (the exact mistake this session made twice locally, packing 0.2.1 a second time
  with new content after the first `.nupkg` had already been restored into the local machine's global
  NuGet cache) - `CHANGELOG.md`'s top heading is still the single source of truth for the version
  about to be claimed, and bumping it remains a manual, reviewed step per change.

## Alternatives considered

Unchanged from `adr/0015`'s "Alternatives considered" - cross-job artifact download and a
repository-committed local feed are still rejected for the reasons recorded there. The option
`adr/0015` deferred, GitHub Packages, is what this ADR adopts; nothing new to weigh against it beyond
what changed in Context above.
