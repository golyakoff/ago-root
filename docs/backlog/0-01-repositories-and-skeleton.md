# Repositories, packages and skeleton

- **Stage**: 0
- **Status**: ready
- **Depends on**: nothing

## Goal

Six repositories exist, build, and consume each other the way the architecture says they must:
`ago-chat` compiles against a **published** `Ago.Platform.*` package, not a project reference. No
business code yet — every later item drops into a slot that already exists.

## Context to read first

`docs/architecture/repositories.md`, `docs/architecture/clean-architecture.md`,
`docs/conventions/naming-and-structure.md`, `docs/runbooks/workspace.md`, `docs/adr/0012`, `docs/adr/0003`.

## Scope

- `ago-platform`: solution, `Ago.Platform.Kernel` (`Result<T>`, `Error`, strongly-typed id base,
  `IClock`, `IIdGenerator` producing uuid v7) and `Ago.Platform.Hosting` with `IProductModule`.
  `dotnet pack` to a local file feed; SemVer starting at `0.1.0`; a `CHANGELOG.md`.
- `ago-chat`: solution, empty `Ago.Chat.Domain`/`Application`/`Contracts`/`Infrastructure.Postgres`/
  `Module`, and the three host projects. `nuget.config` pointing at the local feed.
- The documented dev override that swaps `PackageReference` for `ProjectReference`, plus a note in
  the repo's README that a merged branch must never keep it.
- `Directory.Build.props` (net10.0, nullable, warnings-as-errors) and `Directory.Packages.props` in
  both backend repositories; `.editorconfig` per `docs/conventions/coding-style.md`.
- READMEs already exist in each repository — update them if this work makes them wrong.

## Out of scope

- Ports in `Ago.Platform.Abstractions`: they arrive with their first consumer, not before. Creating
  empty interfaces now guarantees they will be the wrong shape.
- Any domain type, adapter or endpoint — Stage 1.
- A hosted package feed; the local file feed is enough until Stage 8.

## Done when

- [ ] Both backend repositories build clean with zero warnings.
- [ ] `ago-chat` restores `Ago.Platform.*` from the feed, with the dev override switched off.
- [ ] `Ago.Platform.Kernel` has unit tests for `Result<T>` and for uuid v7 ordering.
- [ ] No project named `Common`, `Shared`, `Utils` or `Core` exists anywhere.
- [ ] Junctions work per `runbooks/workspace.md`.

## Open questions

None.
