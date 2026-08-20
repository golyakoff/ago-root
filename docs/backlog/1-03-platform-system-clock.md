# Platform: a real IClock implementation

- **Stage**: 1
- **Status**: ready
- **Depends on**: nothing — independent of `1-01`/`1-02`, can be branched in parallel

## Goal

`Ago.Platform.Kernel.IClock` has existed since Stage 0 with no concrete implementation anywhere.
Every host that composes real DI (starting with `1-06`) needs one to register. This item is small on
purpose: one class and its test.

## Context to read first

`docs/conventions/date-and-time.md`, `docs/architecture/clean-architecture.md` ("Hosts" section — the
only place concrete implementations get registered), `docs/architecture/repositories.md`
("Cross-repository changes" — this is a platform-branch-first change).

## Scope

- `SystemClock : IClock` in `Ago.Platform.Hosting` (not `Kernel` — `Kernel` stays a set of contracts
  and dependency-free primitives; `Hosting` is already where composition-root-adjacent pieces live,
  and a zero-dependency `DateTimeOffset.UtcNow` wrapper costs it nothing).
- A DI registration extension (`AddPlatformClock(this IServiceCollection)` or folded into an existing
  `IProductModule`-loading extension if `1-06` reveals a natural place to put it — implementation
  detail, decide when writing the host wiring).
- `Ago.Platform.Tests`: a test proving `SystemClock.UtcNow` returns a value close to
  `DateTimeOffset.UtcNow` (a tolerance-bounded assertion — never an exact equality against a second
  independently-read clock).
- `CHANGELOG.md` entry and a version bump (`0.1.0` -> `0.2.0` or `0.1.1`, whichever this change
  actually is under SemVer — it's additive, so minor).

## Out of scope

- `IIdGenerator`'s registration — `UuidV7Generator` already exists and is already usable; if it has
  no DI extension yet, add the one line here too, but that is not the point of this item.
- Anything in `Ago.Platform.Abstractions` — does not exist yet, not needed for this.

## Done when

- [ ] `dotnet pack` produces the bumped version; `ago-chat`'s CI (`adr/0015`) still restores
      successfully against a freshly-packed `main` — verify by running the same commands
      `CLAUDE.md`'s Commands section documents.
- [ ] `Ago.Platform.Architecture.Tests` passes unchanged.

## Open questions

None.
