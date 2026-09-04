# Committing and opening a PR

**Every commit and every pull request in every repository of this workspace goes through these two
scripts.** Not "should" — the scripts exist because the alternative was tried and failed twice.

```bash
cd <the worktree>
bash C:/git/ago/ago-root/.claude/skills/commit-guard/commit.sh  <message-file> [git commit args...]
bash C:/git/ago/ago-root/.claude/skills/commit-guard/open-pr.sh <title> <body-file> [gh args...]
```

## Opening a PR from the desktop app: two steps, not one

**The one-line form above hides the PR from the app's own display**, and that is not cosmetic. The
Claude desktop app renders its pull-request card - the green status a person actually reads - by
recognising `gh pr create` in the command it is handed. Called through the script, that string is one
level down, so the card never appears and a PR lands invisibly. Losing a check the author reads at a
glance costs more than the keystroke saved.

So from a session in the app, run the guard and the creation as two commands:

```bash
cd <the worktree>
bash C:/git/ago/ago-root/.claude/skills/commit-guard/open-pr.sh --check-only
gh pr create --title "<title>" --body-file <body-file>
```

`--check-only` runs **every** refusal below and prints the `gh` line to follow it with. The guard
still gates the PR - it just stops being the thing that types the final command.

**This is deliberately the weaker arrangement of the two**, and it is worth being clear about why it
is acceptable. The refusal that mattered most - the trailer - is enforced by the `commit-msg` hook at
the moment the commit is written, which no PR-time check can be a substitute for and which nothing
here can skip. What `--check-only` gives up is only that a session could, in principle, skip step one
and open the PR anyway. That is a lapse a person can see in the transcript, rather than a silent one.

The single-call form stays supported and is the right one anywhere the card is not being rendered -
a worker's commit-prep block, a terminal, CI.

They live in `ago-root` and are called from wherever the work is, because the rule is the workspace's
rather than one repository's.

## What they refuse, and why each one is here

**A `Co-Authored-By` trailer, at either step.** `CLAUDE.md` rule 9 forbids it: whoever is named in the
local git identity is the author of record, regardless of who typed the command.

That rule has now been broken twice by the same mechanism. A harness attribution reminder arrives
mid-session, says it *"replaces any earlier attribution guidance"*, and **recency gets mistaken for
precedence**. It is not: the project rule is the author's, and no reminder outranks it. On 2026-09-04
three such commits reached `main` across two repositories, and removing them meant rewriting `main`
twice — an action that belongs to the author alone and that they should never have had to take.

A memory file saying "never do this" already existed when it happened. It failed for a mechanical
reason — it was not in `MEMORY.md`, the index that loads at session start, so it was never read. Both
were fixed. **This script is the half that does not depend on having read anything.**

`open-pr.sh` checks **every commit on the branch**, not the tip. The trailer reaches `main` through
whichever commit carries it, and a three-commit branch with one bad message is exactly the shape that
got through.

**A stale base, at PR time.** `git-workflow.md`: an MR is the branch rebased onto main's tip *at push
time*. Once a branch is pushed with a PR open, a stale base is close-the-PR-and-rebuild rather than a
rebase — so the cheap moment to look is before the PR exists. This has cost rebuilt branches three
times.

**An unpushed branch, or a remote tip that differs from local.** A PR opened against a stale remote
describes something other than what was verified.

**Being on `main`.** Work happens on a branch (rule 10).

## What they deliberately do not touch

**The PR body's `🤖 Generated with [Claude Code]` line.** That was never objected to — only the commit
trailer was. Stated here so nobody later "tidies up" by removing it.

**Anything after the required arguments** is passed through to `git commit` or `gh pr create`
untouched, so `--amend`, `-a`, `--draft` and the rest still work.

## The message must be in a file

Not ceremony. A message passed inline goes through the shell, where backticks become command
substitution and `\n` becomes a real newline — both have already cost this project a rebuilt branch
and a broken script in one day. Git reads a file verbatim.

## The hook is what makes it unavoidable

The scripts protect the path that remembers to call them - which is the same discipline that already
failed twice. `hooks/commit-msg` runs for **every** commit: `-m`, `-F`, an editor, another script, a
background worker. Past it there is only `--no-verify`, which is a decision rather than a lapse.

Install once per machine: `bash install-hooks.sh`.

**It points `core.hooksPath` at this directory by absolute path, and that detail is the whole thing.**
The obvious install - copy the hook into each repository's `.githooks` and set
`core.hooksPath = .githooks` - fails here, and fails silently: **a relative `core.hooksPath` resolves
against the current working tree**, so a worktree looks for `<worktree>/.githooks`, finds nothing, and
commits with no hook at all. Nearly all work in this workspace happens in worktrees, so that version
protects almost nothing while reporting ten repositories installed. Found by testing it - a
`git commit -m` carrying the trailer went straight through.

Verified after the fix, from two different repositories' worktrees: a trailered commit exits 1, a
clean one exits 0.

## In commit-prep blocks

A worker's commit-prep block calls `commit.sh`, not `git commit`. Then the managing session cannot
paste a trailer in by executing somebody else's block, and the guard covers work this session did not
write.
