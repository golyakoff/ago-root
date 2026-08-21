---
name: commit-prep
description: Prepare a change for the human to commit and push - verify it, stage it precisely, draft the message, then stop. Use whenever a slice of work is finished and ready to hand back, in any AGO repository.
---

# Preparing code for commit and push

`CLAUDE.md` rule 9: committing and pushing are always the author's action. This skill ends at a
drafted `git commit`/`git push` command block for the human to run - it never executes one.

## 0. Before adding a new commit to an EXISTING branch, confirm it isn't already merged

Skip this step only for a branch you just created in this same session for this change. For any
branch that already existed - especially "I found one more thing while verifying X" mid-session - a
PR against it may have merged on GitHub without this session knowing. Committing more work onto an
already-merged branch is exactly how `feat/1-06-api-realtime-and-wiring` ended up "2 ahead / 1 behind
main" twice in one project: a hub fix was committed onto a branch whose earlier commit had already
been rebase-merged into `main` moments before, unnoticed.

Run this before drafting the commit, not after the confusion shows up:

```
git fetch origin
git diff --stat origin/main..HEAD
```

- **The diff matches only what you intend to add** (the files you actually just changed) -> the
  branch is current, proceed normally to step 1.
- **The diff includes files you didn't touch, or the branch's own earlier commits** -> `origin/main`
  has moved past this branch, almost always because its PR already merged (this project always merges
  via GitHub's Rebase and merge, so the SHAs never match even though the content does). Stop before
  committing. Run `rebase-cleanup`
  first: it decides whether to fast-forward and delete the branch, or rebuild it with
  `git reset --soft origin/main`, depending on what's actually still unique to it. Only once that's
  resolved and the branch is clean against `origin/main` does this skill's step 1 apply, now to
  whatever new work remains.

This turns a check that used to happen reactively - after `git status` already looked confusing -
into a five-second gate that runs before the confusing state can be created at all.

## 1. Verify before staging anything

Do not stage on faith. For the repository you are in:

- Build: `dotnet build` (or the relevant project/solution).
- Test: `dotnet test` for the affected projects at minimum: full suite if the change is small enough
  to afford it.
- If the change touches a hub, endpoint, or anything with a UI-visible effect, it must have been
  exercised live (browser, curl, `dotnet run`) - not just unit-tested. State what was actually run.

A change that "should work" is not ready to hand back. Report what you verified and how, not what you
expect.

## 2. Read the diff before staging

`git status` first. On Windows repos with `core.autocrlf` set, a huge "modified" list is often pure
line-ending noise, not content - `git diff --stat` shows the real shape of the change; a file with a
line-ending-only diff won't appear there with more than a warning. Confirm with `git diff --stat`
before assuming the change is large. Never stage a file you haven't accounted for.

Check for secrets before staging, always - this project is public (`CLAUDE.md`: "everything is
public"). A token, connection string, or real endpoint in a fixture or fixed-later comment is not
acceptable even briefly.

## 3. Stage precisely

`git add <specific files>`, never `git add -A` or `git add .` - an unrelated file picked up by a
broad add is a silent scope leak into someone else's review. List every file explicitly in the
command you hand back.

## 4. Draft the message

Conventional-commit style, one line, present tense, states *why* over *what* when the diff doesn't
already make the *what* obvious: `fix(chat): broadcast across VisitorHub/OperatorHub - SignalR
groups are hub-scoped (1-06)`, not `fix: hub bug`. Reference the backlog item id if one exists.

## 5. Hand back, then stop

Output a single fenced `bash` block with `git add` (explicit files) then `git commit -m "..."`, and
`git push` only if the branch already has an upstream (check `git status` for "Your branch is
up to date with" / "ahead of" - if there's no upstream yet, the block needs
`git push -u origin <branch>` instead, and say so). Do not run any of it. Do not follow up by
running it later in the same turn "since it's ready" - the human runs it.

## Common trip-ups from past sessions

- **Forgetting the commit after `git reset --soft origin/main`**: reset alone stages nothing new to
  history: skipping straight to `git push` after it produces an empty push. Always re-check
  `git status` between a history-rewriting step and the push command you hand back.
- **A branch with no upstream**: first push on a new branch needs `-u origin <branch>`, or it fails
  with "no upstream branch" - check before drafting the push line, don't assume.
- **Committing new work onto an already-merged branch**: see step 0 - this is what produces the
  "N ahead / M behind main" confusion after the fact. Catch it with the fetch-and-diff check before
  the commit exists, not by diagnosing branch state afterward.
