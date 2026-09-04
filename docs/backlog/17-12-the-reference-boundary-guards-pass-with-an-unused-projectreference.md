# the reference-boundary guards pass with an unused `ProjectReference`

- **Stage**: 17
- **Status**: ready
- **Found**: 2026-09-04, cleaning up after a mistake of my own — which is how the guard came to be
  tested at all.

## The gap

`SchemaMigrationTests.TheMigrator_ReferencesPersistenceAndNothingAboveIt` (`adr/0056`) and
`RoleAssignmentProjectionBackfillHostTests.TheBackfillHost_ReferencesPersistenceAndNothingAboveIt`
(`22-16`, which copies it) both read the **compiled assembly** — `MainModule.AssemblyReferences` via
Cecil — and assert no forbidden name appears.

**The C# compiler elides a reference nothing uses.** So a `<ProjectReference>` added to the host and
never referenced from code does not reach the emitted metadata, and the guard passes.

Proven rather than reasoned: the reference was put back, the assembly rebuilt, the test run —
**42 passed.** Removed again: 42 passed. The guard cannot tell the two states apart.

## Why it matters more than it looks

Each guard's own comment claims more than it delivers. `22-16`'s says it *"fails the moment somebody
adds a `PackageReference` that quietly reintroduces one"*. It does not, unless something uses it.
**A guard that reads as stronger than it is, is worse than no guard, because it stops anyone
looking.**

An unused reference is not harmless either: it pulls the referenced project and its transitive
dependencies into the host's publish output. The safety argument these guards protect — *"this
one-shot tool cannot depend on the broker, cache or Keycloak being up"* — is about runtime, and an
unused reference does not break that. But the boundary is **stated as a reference boundary**, and that
is the part not enforced.

## How it was found

A commit was taken from a worktree an agent was still editing, capturing a deliberate fails-before
mutation. The architecture test that should have been the safety net **passed anyway**, which is what
prompted checking the guard rather than trusting it.

`22-16`'s own fails-before *did* show the test failing — because its mutation also added a
`typeof(Ago.Chat.Module.ChatModule)` call. With real use the reference is emitted and the guard fires.
Correct as a fails-before for the rule as written; it just does not cover the case that occurred.

## Done when

- [ ] Adding a forbidden `ProjectReference` to either host fails its guard **whether or not anything
      uses it** — proven by adding one and nothing else.
- [ ] Both guards say what they actually check, in their own remarks. If a reference-level check is
      not worth building, that is a legitimate outcome and the comments must stop claiming otherwise.

## The choice, weighed rather than assumed

Parsing the `.csproj` swaps an IL check for a text check and would not survive a reference injected by
`Directory.Build.props`. The generated `.deps.json` sees the resolved runtime graph. So does
`obj/project.assets.json`, at a fixed path and produced by restore alone. Neither is obviously right;
the choice is the work.
