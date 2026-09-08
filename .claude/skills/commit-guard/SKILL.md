---
name: commit-guard
description: The whole path from finished work to an open PR - verify, read the diff, stage precisely, draft the message into a FILE, then commit and open the PR through the two scripts that take files rather than inline strings. Use for EVERY commit and EVERY PR in every AGO repository. Absorbs the former commit-prep skill.
---

# Committing and opening a PR

**This skill absorbed `commit-prep` on 2026-09-08, and the merge was not tidying.** The two described
one moment in two files, and they *contradicted each other*: `commit-prep`'s step 5 said to hand back
`git commit -m "..."`, while this file has said since 2026-09-04 that the message must be in a file
because an inline message goes through the shell. Only one of the two was reachable — `commit-guard`
had no YAML frontmatter and so was never registered — so for a month the visible half taught exactly
what the invisible half forbade. Four shell-quoting failures on 2026-09-08 alone came out of that gap.
One door, one answer.

## Who may run what

`CLAUDE.md` rule 9 is the authority, and the split is deliberate:

- **A background worker never commits, pushes, or opens a PR.** It ends at a drafted block and hands
  it back. Rule 9's delegation does not reach workers.
- **The managing session may run it directly** on a feature branch, once the item's own done-when
  criteria are verified and the local suite is green. It then follows `land-a-slice`.
- **Nobody pushes to `main`.** Every change reaches `main` through a PR. `--force`, `--amend` and
  rebasing an already-pushed branch remain the author's exclusively.

## The two commands

```bash
cd <the worktree>
bash C:/git/ago/ago-root/.claude/skills/commit-guard/commit.sh  <message-file> [git commit args...]
bash C:/git/ago/ago-root/.claude/skills/commit-guard/open-pr.sh <title> <body-file> [gh args...]
```

Everything below is what has to be true before you run the first one.

---

# Part 1 — before anything is staged

## 0. On an EXISTING branch, confirm it is not already merged

Skip only for a branch created in this session for this change. For any branch that already existed —
especially "I found one more thing while verifying X" — a PR against it may have merged on GitHub
without this session knowing. That is how `feat/1-06-api-realtime-and-wiring` ended up "2 ahead /
1 behind main" twice: a hub fix was committed onto a branch whose earlier commit had been
rebase-merged moments before, unnoticed.

```bash
git fetch origin
git diff --stat origin/main..HEAD
```

- **Only what you intend to add** → the branch is current, go to step 1.
- **Files you did not touch, or the branch's own earlier commits** → `origin/main` has moved past this
  branch, almost always because its PR merged (this project always uses Rebase and merge, so the SHAs
  never match even though the content does). **Stop.** Run `rebase-cleanup` first.

A five-second gate before the confusing state exists, rather than a diagnosis afterwards.

## 1. Verify before staging anything

Do not stage on faith. For the repository you are in: build, then test — the full suite if the change
is small enough to afford it, the affected projects at minimum. If the change touches a hub, an
endpoint, or anything with a UI-visible effect, it must have been exercised live (browser, curl,
`dotnet run`), not only unit-tested.

Report what you verified and how, not what you expect. A change that "should work" is not ready.

## 2. Read the diff before staging

`git status` first, then `git diff --stat`. On Windows repositories with `core.autocrlf` set, a huge
"modified" list is usually line-ending noise rather than content, and `--stat` shows the real shape.
Never stage a file you have not accounted for.

**Check for secrets every time.** This project is public (`CLAUDE.md`). A token, a connection string
or a real endpoint in a fixture or a fixed-later comment is not acceptable even briefly.

## 3. Stage precisely

`git add <specific files>` — never `git add -A` or `git add .`. A broad add picks up an unrelated file
and leaks scope silently into somebody else's review. List every file explicitly.

## 4. Write the message into a file

Conventional-commit style, one line, present tense, saying *why* over *what* when the diff already
makes the *what* obvious: `fix(chat): broadcast across VisitorHub/OperatorHub - SignalR groups are
hub-scoped (1-06)`, not `fix: hub bug`. Reference the backlog item id if one exists.

**Into a file, and this is not ceremony.** A message passed inline goes through the shell, where
backticks become command substitution and `\n` becomes a real newline. Both have already cost this
project a rebuilt branch and a broken script in one day. Git reads a file verbatim.

## 5. If you are a worker: hand back and stop

Output one fenced `bash` block that begins with an explicit `cd`, writes the message to a file, and
calls `commit.sh` — **never `git commit` directly**, so the managing session cannot paste a trailer in
by executing somebody else's block, and the guard covers work this session did not write. End it with
the push (`-u origin <branch>` for a new branch; check `git status` for whether an upstream exists).

Do not run any of it. Do not run it later in the same turn "since it is ready".

---

# Part 2 — running it

## Opening a PR from the desktop app: two steps, not one

**The one-line form hides the PR from the app's own display**, and that is not cosmetic. The Claude
desktop app renders its pull-request card — the green status a person actually reads — by recognising
`gh pr create` in the command it is handed. Called through the script, that string is one level down,
so the card never appears and a PR lands invisibly.

```bash
cd <the worktree>
bash C:/git/ago/ago-root/.claude/skills/commit-guard/open-pr.sh --check-only
gh pr create --title "<title>" --body-file <body-file>
```

`--check-only` runs **every** refusal below and prints the `gh` line to follow it with.

**This is deliberately the weaker arrangement**, and it is acceptable for one reason: the refusal that
matters most — the trailer — is enforced by the `commit-msg` hook when the commit is written, which no
PR-time check substitutes for and which nothing here can skip. What `--check-only` gives up is that a
session could skip step one; that is a lapse visible in the transcript rather than a silent one.

The single-call form stays right anywhere the card is not rendered — a worker's block, a terminal, CI.

## What they refuse, and why each one is here

**A `Co-Authored-By` trailer, at either step.** `CLAUDE.md` rule 9: whoever is named in the local git
identity is the author of record, regardless of who typed the command.

That rule has been broken twice by the same mechanism. A harness attribution reminder arrives
mid-session saying it *"replaces any earlier attribution guidance"*, and **recency gets mistaken for
precedence**. It is not: the project rule is the author's, and no reminder outranks it. On 2026-09-04
three such commits reached `main` across two repositories, and removing them meant rewriting `main`
twice — an action belonging to the author alone, which they should never have had to take.

A memory file saying "never do this" already existed when it happened. It failed mechanically: it was
not in `MEMORY.md`, the index that loads at session start, so it was never read. **This script is the
half that does not depend on having read anything.**

`open-pr.sh` checks **every commit on the branch**, not the tip — a three-commit branch with one bad
message is exactly the shape that got through.

**A stale base, at PR time.** `git-workflow.md`: an MR is the branch rebased onto main's tip *at push
time*. Once pushed with a PR open, a stale base is close-the-PR-and-rebuild rather than a rebase, so
the cheap moment to look is before the PR exists. This has cost rebuilt branches three times.

**An unpushed branch, or a remote tip differing from local.** A PR against a stale remote describes
something other than what was verified.

**Being on `main`.** Work happens on a branch (rule 10).

## What they deliberately do not touch

**The PR body's `🤖 Generated with [Claude Code]` line.** Only the commit trailer was ever objected to.
Stated here so nobody later "tidies up" by removing it.

**Anything after the required arguments** passes through to `git commit` or `gh pr create` untouched,
so `--amend`, `-a`, `--draft` and the rest still work.

## The hook is what makes it unavoidable

The scripts protect the path that remembers to call them — the same discipline that already failed
twice. `hooks/commit-msg` runs for **every** commit: `-m`, `-F`, an editor, another script, a
background worker. Past it there is only `--no-verify`, which is a decision rather than a lapse.

Install once per machine: `bash install-hooks.sh`.

**It points `core.hooksPath` at this directory by absolute path, and that detail is the whole thing.**
The obvious install — copy the hook into each repository's `.githooks` and set
`core.hooksPath = .githooks` — fails silently: **a relative `core.hooksPath` resolves against the
current working tree**, so a worktree looks for `<worktree>/.githooks`, finds nothing, and commits with
no hook at all. Nearly all work here happens in worktrees, so that version protects almost nothing
while reporting ten repositories installed. Found by testing it — a `git commit -m` carrying the
trailer went straight through.

Verified after the fix, from two different repositories' worktrees: a trailered commit exits 1, a clean
one exits 0. Re-verified 2026-09-08.

## Common trip-ups

- **Forgetting the commit after `git reset --soft origin/main`.** Reset stages nothing new to history;
  going straight to `git push` produces an empty push. Re-check `git status` between a
  history-rewriting step and the push.
- **A branch with no upstream.** The first push needs `-u origin <branch>` or it fails with "no
  upstream branch". Check before drafting the push line.
- **Committing onto an already-merged branch.** Step 0. Catch it before the commit exists.
- **Reaching for `git commit -m` because it is shorter.** That is the habit this skill exists to
  replace, and the reason the file it replaced was deleted rather than left beside it.
