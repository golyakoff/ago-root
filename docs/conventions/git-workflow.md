# Git workflow

## Hard rule: the author commits, not the agent

An AI session **never** runs `git commit`, `git push`, `git commit --amend`, `git rebase`, or
anything else that writes history. Sessions change files and report what changed; the author stages
and commits deliberately. Creating a branch is fine. This is not negotiable and is repeated in
`CLAUDE.md` for a reason.

## Branching

- `main` is always green: it builds, all tests pass, and it is deployable.
- All work happens on a feature branch: `feat/<short-slug>`, `fix/<short-slug>`,
  `chore/<short-slug>`, `docs/<short-slug>`.
- One branch is one vertical slice or one backlog item. A branch that grows a second unrelated
  concern gets split.

## Merge requests

A merge request is a **feature branch rebased onto `main`, with tests passing**. Concretely:

1. `git fetch` and rebase the branch onto the current `main` - never merge `main` into the branch.
   History stays linear, and the diff shown in review is the diff that will land.
2. Conflicts are resolved during the rebase, on the branch, before review.
3. The full test suite passes **after** the rebase, not before it. A green run on stale base is
   evidence about a state that no longer exists.
4. The MR describes what changed and why, and links the ADR if a decision was made.
5. Merge is via GitHub's **Rebase and merge** - no merge commits, no squash. Because the branch was
   already rebased onto `main` in step 1, this replays already-linear commits onto `main` one-for-one,
   preserving individual commit messages instead of collapsing them. GitHub still writes each replayed
   commit as a new object (new SHA, new committer date) even when the diff is identical to the
   branch's own commit - a rebased/re-applied branch is never literally `git merge --ff-only`-able
   against `main` afterward, only diff-identical to it. `rebase-cleanup` exists for exactly this.

Rationale for rebase-only: with a linear history, `git bisect` is meaningful, `git log` reads as a
sequence of complete features, and every commit on `main` is a state where the tests passed.

## Commit messages

`<type>(<scope>): <imperative summary>` - e.g. `feat(chat): assign waiting conversations to operators`.
Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `build`. Scope is the module
(`chat`, `platform`, `infra`, `widget`). The body explains *why*; the diff already shows *what*.

## What must be true before an MR is opened

- Build clean, no new warnings.
- `Ago.Chat.Architecture.Tests` green - a layering violation is never "fixed later".
- New behaviour has tests at the right level (`testing.md`).
- Docs updated in the same branch if the change made one wrong.
- No commented-out code, no `TODO` without an issue or backlog file reference.
