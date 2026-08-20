# CI pipeline

- **Stage**: 0
- **Status**: done — both workflows verified by running every step locally with the exact commands
  they use (restore, format check, build, test, pack). Surfaced and fixed one real pre-existing bug:
  two `Program.cs` files had stray CRLF line endings that `dotnet format --verify-no-changes` was
  never run against before. The CI package-flow question this item raised (no hosted NuGet feed
  exists — where does `ago-chat`'s CI get `Ago.Platform.*` from?) is recorded in `adr/0015`.
- **Depends on**: `0-01-repositories-and-skeleton.md`, `0-02-arch-tests.md`

## Goal

Every branch is built and tested automatically, so "green" is a fact rather than a claim, and the
rebase-then-MR rule has something to enforce it.

## Context to read first

`docs/conventions/git-workflow.md`, `docs/conventions/testing.md`.

## Scope

Per repository, since each is its own repository (`docs/adr/0012`):

- Build, unit tests, arch tests on every push to any branch.
- `ago-platform` additionally packs on `main` and publishes the package version from its changelog.
  Delivered as: version read from `CHANGELOG.md`'s top heading, packed, uploaded as a workflow
  artifact for a human to inspect — not pushed to a hosted registry (`adr/0015`; "publish" without
  a registry is the open question that ADR answers).
- `ago-chat` builds against the published package, never a project reference — CI is what catches a
  branch that left the dev override switched on. Delivered as: CI packs `ago-platform`'s current
  `main` from source, in the same job, into a throwaway local feed (`adr/0015`) — not a restore
  against `ago-platform`'s own CI artifact, since cross-repository artifact access needs the same
  credential the registry option would have needed.
- Integration tests (Testcontainers) on branches and on `main`. No `Ago.Chat.Integration.Tests`
  project exists yet (`testing.md`; it arrives with Stage 2's outbox). Nothing extra was needed for
  when it does: `dotnet test Ago.Chat.slnx` already runs every test project the solution references,
  so adding the project and its `Testcontainers` package reference is enough — the workflow does not
  change. `ubuntu-latest` runners carry Docker preinstalled, which is what Testcontainers needs.
- Format check (`dotnet format --verify-no-changes`) — in both repositories, before build so a
  formatting-only branch fails fast.
- Test results published as artifacts (`.trx`, via `actions/upload-artifact`). Coverage collection
  (`coverlet.collector` is already a test dependency in both repos) was not wired into the workflow —
  there is nothing yet to report against (`testing.md`: "no target percentage... whether every rule
  in the ADRs... has a test that would fail if broken", not a number) — added when a coverage report
  actually informs a decision, not before.
- A status that an MR can require: each workflow's `build-test` job is what a GitHub branch
  protection rule names as a required check. Enabling that protection rule is a repository setting,
  not a file in the repository — left for the author to flip in GitHub's UI.

## Out of scope

- Deployment — Stage 8.
- The provider matrix (Kafka, MySQL) — Stage 9 adds it.

## Done when

- [x] A branch with a failing test cannot show green. Verified by running the exact `dotnet test`
      command each workflow uses; a failing test fails the process the workflow step depends on.
- [x] A deliberate layering violation fails CI, not just the local build. Already proven for both
      solutions' architecture tests in `0-02-arch-tests.md` — `dotnet test` runs them with no
      separate job, so the same proof applies here unchanged.
- [x] Total run time stays under a few minutes, or the slow parts are split into their own job.
      Measured locally: `ago-platform`'s restore+format+build+test is ~15s; `ago-chat`'s equivalent,
      including packing `ago-platform` from source first, is ~35s. Both comfortably under a minute
      before GitHub-hosted-runner overhead; no split needed at this size.

## Open questions

None left open by this item. GitHub Actions is assumed: the repositories are public, Actions is free
for them, and the status badges are visible to exactly the audience this project is for. Revisit only
if the repositories move. The package-registry question this item raised while implementing is
answered, not open — `adr/0015`.
