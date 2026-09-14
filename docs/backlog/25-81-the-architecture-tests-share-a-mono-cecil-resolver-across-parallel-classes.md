# 25-81 · The architecture tests share a Mono.Cecil resolver across parallel classes

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-14, independently re-verifying `25-70` — a full `dotnet test` run of `ago-chat`
  failed exactly once, on `Ago.Chat.Architecture.Tests.TenantScopeTests
  .EveryPermissionCheck_IsScopedToASiteTheEntryPointWasGiven`, with:
  `System.InvalidOperationException: Operations that change non-concurrent collections must have
  exclusive access. A concurrent update was performed on this collection and corrupted its state.`
  — thrown from inside `Mono.Cecil.DefaultAssemblyResolver.Resolve(AssemblyNameReference)`, reached
  through `TenantScopeRule.TryResolve` → `HasSiteIdMember` → `CarriesSiteId` → `Scan`. The same test,
  the same project, and the whole `Ago.Chat.Architecture.Tests` project (46/46) each ran clean twice
  in a row immediately after, in isolation.

## What is actually true

`TestAssemblies.cs` loads every product assembly **once**, as static properties
(`public static ProductAssembly Application { get; } = Load(...)`), each carrying a single shared
`Mono.Cecil.AssemblyDefinition` for the lifetime of the test process — `TestAssemblies.Application`
is the same instance no matter which test class reads it. `AssemblyDefinition.ReadAssembly(path)`
with no explicit `ReaderParameters` gives that instance one `DefaultAssemblyResolver`, and that
resolver caches what it resolves in an ordinary, non-thread-safe `Dictionary`.

xUnit runs test **classes** in parallel by default unless a class opts out via `[Collection]`. Any
two test classes that each call `.Resolve()` on a `TypeReference` belonging to
`TestAssemblies.Application.Cecil` — which `TenantScopeRule.Scan` does, once per entry point, on
every call — can now do so on two threads at once, against the one resolver's one dictionary. That is
exactly the shape of the exception: a `Dictionary` corrupted by a concurrent, unsynchronized write.

**This is not new in `25-70`, or in `24-17`, or in anything this session touched.** `TestAssemblies`
has looked this way since well before either — the race has likely always been reachable, and simply
had not been rolled by whatever timing/thread-count `dotnet test` happened to use on a given machine,
on a given run, until now. It is exactly the kind of failure this project's own `land-a-slice` skill
warns is easy to miss: a run that goes red once, for a reason that has nothing to do with the change
being verified, is the case a merger has to actually look at rather than re-run and forget.

## Why this is worth fixing rather than shrugging off

A test suite where "run it again" is a legitimate answer to a red run is a suite nobody can trust the
next time it turns red for a real reason. This project's own architecture tests are the mechanical
gate CLAUDE.md's teaching mode and `tenant-isolation.md` both lean on — `TenantScopeTests` in
particular is the one test class in this whole codebase whose entire job is catching a missing
tenant-isolation check before a reviewer has to. A flaky version of that gate is worse than an absent
one, because it teaches whoever hits it to distrust red and re-run rather than to look.

## Scope

- Give every `ProductAssembly.Cecil` in `TestAssemblies.cs` its own `DefaultAssemblyResolver`
  instance is already the default (Mono.Cecil creates a fresh implicit one when none is
  passed) — the actual fix is one of: (a) load each product assembly with an explicit,
  purpose-built resolver whose own internal cache is pre-warmed or wrapped for thread safety, or
  (b) the simpler, cheaper fix — stop the *test classes* from racing each other on the shared
  static state at all, by putting every Cecil-scanning test class in one xUnit
  `[CollectionDefinition(DisableParallelization = true)]` collection (or, narrower, just the classes
  that call `TenantScopeRule.Scan`/read `TestAssemblies.*.Cecil`), so `TestAssemblies`'s static
  loading stays exactly as it is and the tests simply stop overlapping on the one thing that isn't
  safe to share. Pick whichever is less invasive once actually looked at — this item's own Found
  section is a diagnosis, not a prescribed fix.
- Whichever fix lands, prove it: the failure is timing-dependent and does not reproduce on demand
  (two clean re-runs in isolation did not catch it), so the proof this item needs is not "ran it
  twice and it passed" — it is showing *why* the race can no longer happen (the collections no longer
  overlap, or the resolver is now synchronized), the same "why," not "it happened not to fail,"
  standard the rest of this codebase holds itself to.

## Done when

- [ ] The race Mono.Cecil's own exception names is closed by construction (parallel test classes no
      longer share unsynchronized Cecil state), not merely unreproduced.
- [ ] A full `dotnet test` run of `ago-chat` stays green, and the fix is explained in terms of why the
      concurrent access can no longer happen.
