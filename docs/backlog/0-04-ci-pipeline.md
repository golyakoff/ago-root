# CI pipeline

- **Stage**: 0
- **Status**: ready
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
- `ago-chat` builds against the published package, never a project reference — CI is what catches a
  branch that left the dev override switched on.
- Integration tests (Testcontainers) on branches and on `main`.
- Format check (`dotnet format --verify-no-changes`).
- Test results and coverage published as artifacts.
- A status that an MR can require.

## Out of scope

- Deployment — Stage 8.
- The provider matrix (Kafka, MySQL) — Stage 9 adds it.

## Done when

- [ ] A branch with a failing test cannot show green.
- [ ] A deliberate layering violation fails CI, not just the local build.
- [ ] Total run time stays under a few minutes, or the slow parts are split into their own job.

## Open questions

None. GitHub Actions is assumed: the repositories are public, Actions is free for them, and the
status badges are visible to exactly the audience this project is for. Revisit only if the
repositories move.
