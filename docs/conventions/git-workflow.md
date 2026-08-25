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

### One item's PRs land together, and the code lands first

A backlog item usually spans repositories - a fix in `ago-chat` and its record in `ago-root`, or a
change in `ago-deploy` plus the runbook it makes wrong. Those PRs are one change wearing several
numbers, and they are merged **as a group, in one sitting**, never one now and the rest later.

Within the group, **code before docs**, without exception.

The failure this prevents is specific and quiet. `ago-root` is the only place that records what is
considered done: an item's `Status` line, its Done-when boxes, its Outcome, and the queue. Merge the
`ago-root` half while its `ago-chat` half is still open and every one of those becomes false at once -
the item says `done`, the queue has dropped its row, and the code is not on `main`. Nothing fails, no
test goes red, and the next session reads the claim as fact and plans on top of it. That is worse than
an unmerged branch, because an unmerged branch is visibly unfinished.

The reverse order is harmless: code on `main` with its documentation a few minutes behind is a gap
that closes itself and misleads nobody while it is open.

Two practical consequences:

- **Do not merge a docs PR that says "done" until the thing it describes is on `main`.** If the code
  half is blocked - a red check, a review, a conflict - the docs half waits with it, however clean it
  looks on its own.
- If one half genuinely cannot land, say so in the other's PR rather than merging it anyway with the
  Status line quietly softened. A half-landed item is a decision worth stating, not a wording problem.

Branches for one item are given the same name across repositories precisely so the group is visible at
a glance (`feat/17-01-tenant-isolation` in both `ago-chat` and `ago-root`).

### The queue table has one writer

`docs/roadmap.md`'s "Now" table is the single most conflict-prone file in this repository, and the
reason is structural rather than careless: **every** finished item wants to delete its own row and
renumber the rest, so any two branches in flight at once edit the same lines from different starting
numbers. That is a genuine content conflict every time - not the spurious kind a tree-hash comparison
dismisses - and it does not care how carefully either side worked.

It happened three times on 2026-08-25 alone (`5-15`, `6-09`, `17-06`), each costing a close-and-rebuild
or a hand-reconciliation, while the actual content of those branches never overlapped at all.

So: **a branch implementing an item does not touch `docs/roadmap.md`.** Not the row, not the
numbering, not a note. The item's own backlog file records that it is done - that is the authoritative
record, with its date and merge reference - and the queue is edited **once, separately, by whoever
merges**, after the item lands. When several items are in flight this collapses N conflicting edits
into one uncontested commit.

This is not a rule about care. Two sessions can each be completely right about the queue and still
produce a conflict, because "delete row 4 and renumber 5-9" and "delete row 2 and renumber 3-9" are
incompatible descriptions of the same table. Removing the concurrency is the only fix that scales
with the number of parallel workers.

The same reasoning applies to any other file that is a *shared index* rather than a piece of the work:
`docs/adr/README.md` is the other one. There the collision is milder - appending distinct lines
usually merges - but two branches claiming the same ADR number is a real collision that no merge tool
can catch, so a session taking an ADR checks the number against `origin/main` **and** against every
open PR, and parallel workers are handed distinct numbers up front.

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
- The branch does **not** touch `docs/roadmap.md`'s queue table - the merger edits it once, afterwards.
- If the item spans repositories, every half is ready - they merge as a group, code first.
- No commented-out code, no `TODO` without an issue or backlog file reference.
