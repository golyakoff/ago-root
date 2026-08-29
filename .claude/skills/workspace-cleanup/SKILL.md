---
name: workspace-cleanup
description: Reclaim disk space in C:\git\ago and tidy local branches once everything is landed. Covers worktrees (each carries its own bin/obj/node_modules, so worktree count drives disk use directly), orphan local branches with no worktree at all, and stray non-worktree directories/dev-server processes left over from past sessions. Use periodically, when C:\git\ago has grown large, or whenever asked to "clean up the workspace"/"delete merged branches" or similar. Never run while a background worker or peer session might still be using a worktree — confirm everything relevant is idle first.
---

# Workspace cleanup

`C:\git\ago` holds one primary checkout per repository plus one worktree per in-flight item
(`background-worker-brief` §0.7). Each worktree is a full checkout — its own `bin/`, `obj/`,
`node_modules/` — so worktree count, not repo count, is what drives disk use. Landed items whose
worktrees were never removed are the entire problem; this skill finds and removes exactly those; it
does not touch anything else.

**This is a bulk version of the per-task cleanup `background-worker-brief` already describes.** That
skill's own rule still applies and is the one most likely to be violated by acting too broadly here:
*"Remove only the worktrees this task created, by name. Never sweep by a computed property."* This
skill exists because sometimes nobody did that at the time, not because a computed sweep is now safe
— the computed property below (`branch is merged`) is a **necessary** condition for removal, checked
per worktree before acting, never a filter applied blindly across all of them at once.

## 0. Confirm nothing is actively using a worktree

**Do not run this while any background worker might still write to a worktree.** Two failures on
2026-08-26 came from exactly this shape of mistake — see `background-worker-brief` §0.7's own account
of both. This skill inherits its "never touch" list unchanged:

- `git worktree list` marks a row `locked` for the agent runtime's own isolation worktrees
  (`.claude/worktrees/agent-*`) — never remove these, never run bare `git worktree prune` in a
  repository that might have one, and do not unlock one to force the issue. A worker that does its
  real work in a task worktree it created itself (the normal case) leaves this one untouched; removing
  it anyway is what makes that worker unresumable.
- `ListAgents` — any subagent still `running` may hold a task worktree open. Do not remove a worktree
  named for a task whose agent has not completed or been explicitly stood down.
- `ListAgents`'s peer-session rows are other interactive sessions on this machine, possibly with their
  own in-progress worktrees. Their paths are not derivable from this list — if a worktree's branch
  doesn't look like it belongs to any task this session knows about, treat it as a peer's and skip it
  rather than guessing.

If anything is genuinely ambiguous, leave that one worktree alone and note it in the report rather
than resolving the ambiguity by deleting.

## 1. Enumerate

Per repository (`ago-platform`, `ago-chat`, `ago-widget`, `ago-console`, `ago-deploy`, `ago-root`,
`ago-calendar` if present, `ago-business`):

```
git -C <repo> worktree list
```

Skip the primary checkout (the row with no branch name in brackets showing `[main]`, at the repo's own
root) and every `.claude/worktrees/agent-*` row unconditionally.

## 2. Classify every remaining row — never batch this step

For each worktree path and branch:

```
git -C <repo> fetch origin
git -C <repo> status --short -- <worktree-path>        # or: cd <worktree-path> && git status --short
gh pr list --repo <owner>/<repo> --head <branch> --state all --json number,state,mergedAt
```

- **Merged and clean** (`gh` shows a PR with `state: MERGED`, and `git status --short` in that
  worktree is empty): safe to remove. This is the only category this skill removes automatically.
- **Merged but dirty** (uncommitted changes sitting in an already-merged worktree): do not delete.
  Someone was using the landed worktree for something else afterward. Flag it in the report.
- **Open PR, or no PR at all**: never remove. This is live or abandoned-but-unresolved work, and
  telling those apart is a judgement call for whoever is asked, not something to infer from a stale
  timestamp.
- **`prunable`** in `git worktree list`'s own output (the working directory is already gone from disk
  but git's admin metadata for it remains): safe to clear via `git worktree remove <path>` even though
  there is nothing left to delete on disk — this only drops the stale registration. Confirm first that
  the path really is gone (`ls` it) rather than trusting the label alone.

## 3. Remove, one worktree at a time

```
git -C <repo> worktree remove <path>
git -C <repo> branch -d <branch>
```

Use `-d`, not `-D`. This repository set merges every PR via rebase-and-merge
(`docs/conventions/git-workflow.md`), so the branch's own SHA never lands on `main` verbatim — expect
`-d` to print a warning ("merged to refs/remotes/origin/<branch>, but not yet merged to HEAD") and
still succeed; that warning is normal here; see `rebase-cleanup` for why. If `-d` *refuses* (not just
warns), stop and re-check the PR's `state` via `gh pr view --json state,mergedAt` rather than escalating
to `-D` — a refusal after `gh` claims MERGED means the local branch has diverged from what merged, and
force-deleting it would be discarding whatever that divergence is, not "just" clearing a merged branch.

## 3.5 Orphan local branches — no worktree at all

A branch does not need a worktree to pile up: `git branch <name>` or an old worktree removal that
dropped the directory but not the branch both leave one behind. Once §§1-3 have cleared every
worktree-backed branch, sweep what remains:

```
git -C <repo> branch --list           # a leading `+` marks a branch checked out in ANOTHER worktree -
                                       # never touch those; a leading `*` is the primary checkout's own
gh pr list --repo <owner>/<repo> --state merged --json headRefName --limit 500 -q '.[].headRefName' \
  | sort -u > /tmp/merged_<repo>.txt
```

For every local branch not `main`, not `+`-marked, and not on the never-touch list below: if its exact
name appears in the merged list, `git branch -d` it (same `-d`-then-verify-then-`-D` escalation as §3).
If it does **not** appear, do not assume it is live work — this project's git-mechanics notes describe
a repeated pattern of a branch going stale mid-flight and being closed and rebuilt under a new name
(often suffixed `-v2`/`-v3`) that then merges instead. An orphan whose name looks like an earlier
attempt at something that *did* merge under a different name is real, just under the wrong name to
match automatically:

- Diff it against its likely successor (`git diff <old> <new> --stat`) — if the delta is purely
  additive (the new one contains everything the old one has, plus more), the old one is a discarded
  precursor, not divergent work, and `-D` is safe once you've looked.
- If no successor is obvious, or the diff shows the old branch has content the new one dropped, leave
  it and flag it — this is exactly the "ambiguous, don't guess" case §0 already describes, just for a
  branch instead of a worktree.

**Never touch a branch matching `worktree-agent-*`, `worktree-agent-a[0-9a-f]{16}`, or any other
agent-runtime-looking name, even with no `git worktree list` entry for it.** These are the agent
runtime's own bookkeeping and this skill does not know enough about how resumability keys off them to
safely say an orphaned one is dead. Leave every one, flag them as a group, move on.

**If the primary checkout itself is not on `main`**, do not delete the branch it has checked out
(git will refuse anyway) — confirm that branch is merged and clean the same way, then
`git checkout main && git pull --ff-only` in the primary checkout before deleting it, so the primary
stops floating on a stale feature branch as a side effect of the sweep.

## 3.6 Stray non-worktree directories and locked files

Not everything under `C:\git\ago` that looks like a worktree still is one — a `git worktree remove`
that failed partway (see below) can leave a plain directory with a dead or missing `.git` pointer.
Find them with:

```
for d in /c/git/ago/*/; do [ -e "$d/.git" ] || echo "$d"; done
```

Cross-check each: does it have real content unrelated to any repo (a user's own files - leave it
untouched, it is not this skill's business) or does it look like an abandoned repo checkout (empty, or
holds only `node_modules`/`README.md`/build output with a merged PR of the same name)? Only remove the
latter kind.

**A locked file, not a real conflict, is the usual reason `git worktree remove`/`rm -rf` fails on
Windows** with `Permission denied`, `Device or resource busy`, or `Invalid argument`. It is almost
always a stray dev-server process (`npm run dev`/`preview`, `npx serve`, `vite preview`, an old
`dotnet run`) left running from a past session, still holding a file handle in that directory. Find it
rather than guessing:

```
netstat -ano | grep ':<port>'                                    # if you know the port
powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Select-Object ProcessId,CommandLine"   # or 'dotnet.exe'
taskkill //PID <pid> //F
```

Kill only processes that are plainly orphaned local preview/dev servers (no task in this session needs
them) — never a process tied to work still in flight. Retry the removal after; it will succeed once the
handle is released.

## 4. What this skill does not do

- Does not touch `bin/`, `obj/`, or `node_modules/` inside worktrees that are kept — those regenerate
  on the next build and are not worth the risk of interrupting an in-progress one.
- Does not run `git worktree prune` (bare, repo-wide) at any point — see §0.
- Does not delete remote branches. `gh pr merge` and GitHub's own branch-protection settings own that
  lifecycle; this skill only ever removes a *local* worktree and its *local* branch.
- Does not touch anything under `.claude/worktrees/`.

## 5. Report

State, per repository: how many worktrees were removed (path + branch + PR number), how many were
flagged and why (dirty-but-merged, open PR, no PR, ambiguous ownership), and how many were skipped as
agent-runtime or plausibly-a-peer's. A before/after `du`-style size if it was cheap to get; not worth
a slow recursive size scan of a large tree just for the number.
