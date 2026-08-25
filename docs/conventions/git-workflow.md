# Git workflow

## Who may write history

**Narrowed 2026-08-23, and this file was left saying the old thing for two days.** It read: *"An AI
session never runs `git commit`, `git push`, `git commit --amend`, `git rebase`, or anything else
that writes history... This is not negotiable."* `CLAUDE.md` rule 9 replaced that with a narrower
delegation on the same day, so the two documents disagreed while real PRs were being opened under the
new rule. `CLAUDE.md` is the one that was right; this section now says the same thing.

The current split, which is deliberately not "the agent may write history":

- **The managing session may** `git commit`, `git push`, and open a PR on a **feature branch**, once
  the slice's own done-when criteria are verified and the local build and test suite are green. No
  per-commit ask.
- **A background worker may not.** A worker spawned to implement a slice hands back a commit-prep
  block for the managing session to review and execute. It never runs `git commit` or `git push`
  itself, whatever its own reasoning concludes.
- **Merging is always the author's action**, with no exception. Opening a PR is not merging it, and
  nothing about the delegation above changes who presses the button.
- **Never push to `main` directly.** Every change reaches `main` through a PR the author merges.
- **History rewriting on an already-pushed branch stays the author's exclusively**: `git push
  --force`, `git commit --amend`, `git rebase` on a branch that has been pushed. See the rule below
  for what to do instead when such a branch goes stale.
- A draft commit message never carries a `Co-Authored-By` trailer for an AI session. Whoever the
  local git identity names is the author of record, regardless of who typed the command.

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

### Check the base before the first push, not after the PR is open

Step 1 above says "rebase onto the current `main`", which is easy to read as something done once when
the branch is cut. It is not: `main` moves while a branch is being worked on, and it moves most when
several slices are in flight at once, which is the normal state here. **Before pushing a branch for
the first time, re-check that its base is still `main`'s tip:**

```bash
cd <repo>
git fetch origin
git merge-base HEAD origin/main   # must equal:
git rev-parse origin/main
```

If those two differ, rebase **now**, while the branch is still local. Nobody has seen the history, so
rewriting it costs nothing and is not the restricted operation.

**The boundary is the first push, and it is the whole point of doing this early:**

| State of the branch | Stale base is fixed by |
|---|---|
| Not yet pushed, no PR | `git rebase origin/main`, freely — this is the expected move |
| Pushed, PR open | Close the PR, delete the local **and remote** branch, rebuild on current `main`, open a new PR |

Rebasing or force-pushing a branch that has been pushed is the author's action only, so skipping the
pre-push check does not save the rebase — it converts a one-command rebase into a close-and-rebuild.

A stacked branch will look worse than it is. This project merges via **Rebase and merge**, which
gives every replayed commit a new SHA, so a branch stacked on another shows as `CONFLICTING` the
moment its base merges, **even when the content is byte-identical**. Confirm which case it is by
comparing trees rather than trusting the label:

```bash
git rev-parse <old-base-tip>^{tree}
git rev-parse origin/main^{tree}
```

Identical trees mean graph divergence, not a content conflict — but the remedy is the same one in the
table, because the branch has already been pushed either way.

Two failures this has actually caused, both worth the check being written down:

- `ago-root#115` conflicted in `docs/roadmap.md` because two sessions each deleted a different
  completed row from the same queue and renumbered from different starting points. A genuine content
  conflict, not graph divergence — and a pre-push rebase would have surfaced it while it was still a
  local, one-file merge.
- A branch rebuilt on a new base left its **remote** ref alive after a local `git branch -D`. Someone
  later opened a fresh PR from it, which would have silently reverted the fixes that landed in the
  meantime. Every rebuild ends with `git push origin --delete <old-branch>`, not just a local delete.

## Commit messages

`<type>(<scope>): <imperative summary>` - e.g. `feat(chat): assign waiting conversations to operators`.
Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `build`. Scope is the module
(`chat`, `platform`, `infra`, `widget`). The body explains *why*; the diff already shows *what*.

## What must be true before an MR is opened

- The branch's base is `main`'s current tip - checked with `git merge-base`, not assumed from when
  the branch was cut, and rebased while still local if it is not.
- Build clean, no new warnings.
- `Ago.Chat.Architecture.Tests` green - a layering violation is never "fixed later".
- New behaviour has tests at the right level (`testing.md`).
- Docs updated in the same branch if the change made one wrong.
- No commented-out code, no `TODO` without an issue or backlog file reference.
