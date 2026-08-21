---
name: rebase-cleanup
description: Clean up and re-fetch local branch state after a PR was merged or rebased on GitHub. Use whenever GitHub shows a branch as merged, or a local branch's push looks wrong (empty push, unexpected ahead/behind counts) after merging on GitHub.
---

# Cleanup and fetch after a GitHub rebase/merge

AGO repos merge every PR via GitHub's **Rebase and merge** button, always - never squash, never a
merge commit, never the plain "Merge" button (`docs/conventions/git-workflow.md`). Rebase-and-merge
still writes fresh commit objects on `main` even when the diff is identical to the branch's own
commits: the SHA changes (new committer date), the message and content don't. So the commits that
land on `main` are *never* literally the feature branch's own commits, even right after a clean merge
with nothing else going on. This is the single most common source of confusing branch state in this
project - not a sign anything went wrong. Never delete or force-push a branch to "fix" confusing state
before running the diagnosis below.

**Better than diagnosing it after the fact: catch it before it happens.** `commit-prep`'s step 0 runs
`git fetch origin && git diff --stat origin/main..HEAD` before adding any new commit to a branch that
already existed - if that turns up more than the new work being added, `origin/main` has already
absorbed this branch and step 2 below is what to run before committing anything further on top.

## 1. Fetch first, always

```
git fetch origin
```

Every diagnosis below depends on `origin/main` being current. Skipping this step produces false
readings.

## 2. Diagnose before touching anything

```
git diff --stat origin/main..<local-branch>
```

- **Empty output** -> the branch's commits are pure duplicates of content already rebase-merged into
  `origin/main` under new SHAs. There is no unique work left on this branch. Safe path:
  ```
  git checkout main
  git merge --ff-only origin/main
  git branch -D <local-branch>
  ```
  `--ff-only` refuses if `main` has local commits of its own - if it refuses, stop and look, don't
  force it.
- **Non-empty output** -> there is genuinely new work stacked on top of the merged PR. Do not delete
  anything. Rebuild the branch on the new `main` instead:
  ```
  git checkout <local-branch>
  git reset --soft origin/main
  git commit -m "..."   # re-commit the real remaining diff, human writes/confirms the message
  ```
  Rename the branch first if it now represents a different unit of work than its name implies.

## 3. Stale remote branches

After a rebase-merge, GitHub often auto-deletes the source branch, but the local remote-tracking ref
survives until pruned:

```
git fetch --prune origin
git branch -vv     # anything showing ": gone]" is a stale tracking ref
```

Deleting a local branch whose remote-tracking ref shows `gone` is safe *only after* step 2 confirmed
there's nothing unique on it.

## 4. Before any destructive branch command

`git branch -D`, `git push --force`, `git reset --hard` - run `git status` immediately before each
one and read it. If it mentions uncommitted changes or files you don't recognize, stop and ask rather
than assume they're safe to lose. This mirrors the general project rule: investigate unfamiliar state
before deleting or overwriting it.

## Real examples from this project

**Empty-diff case**: a push that reported `Total 0 (delta 0)` after
`git push -u origin feat/1-04-postgres-persistence` looked broken. Diagnosis:
`git diff --stat origin/main..origin/feat/1-04-postgres-persistence` was empty - the branch had
already been rebase-merged in an earlier PR, so the push legitimately had nothing new to send. The
fix was not to delete the branch (that was the first instinct) but to notice a missing `git commit`
step upstream of the push, fix the actual gap, and re-push with real content.

**Non-empty-diff case, and why it recurred**: `feat/1-06-api-realtime-and-wiring`'s original commit
was rebase-merged into `main` mid-session. A follow-up bug fix (the SignalR hub-isolation fix) was
then committed onto that *same* branch without re-checking whether it had already merged - producing
"2 commits ahead, 1 behind main" on GitHub. Diagnosis confirmed step 2's non-empty case: only the new
fix (23 lines) was real, the rest was the already-merged content showing up again because the branch's
merge-base with `origin/main` was still the pre-1-06 commit, not the rebase-merged one. Fixed with
`git reset --soft origin/main` + one clean commit + `git push --force-with-lease`, then merged
cleanly via Rebase and merge again. It recurred a second time in the same session before
`commit-prep` step 0 existed - that step exists specifically so the fetch-and-diff check happens
*before* committing onto an existing branch, not only when GitHub's ahead/behind counter already
looks wrong.
