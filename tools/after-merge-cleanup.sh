#!/usr/bin/env bash
# Reclaim one item's worktree and branches, after its PR has merged.
#
# usage: bash tools/after-merge-cleanup.sh <repo> <item> [--yes]
#   e.g. bash tools/after-merge-cleanup.sh ago-console 23-105
#
# Without --yes it reports what it would do and changes nothing.
#
# WHY THIS EXISTS, GIVEN THE RULE ALREADY DID.
#
# `finish-an-item` steps 3 and 4 have said "delete the remote branch" and "remove the worktrees this
# item created, by name" since they were written. On 2026-09-08 the workspace held **158 GB**, of
# which **147 GB was `bin/` and `obj/`** inside worktrees whose work had long since merged.
# `node_modules` was 12 GB and every `.git` in the workspace put together was 66 MB - so this is not
# git garbage and never was. It is build output in directories nobody closed.
#
# That is the same shape as `commit-guard` being invisible: a correct instruction with nothing that
# executes it. Prose asks; a script does.
#
# WHAT IT REFUSES TO DO, AND WHY THAT IS THE IMPORTANT HALF.
#
# It removes **only the directory whose name this item owns** - `<workspace>/<repo>-<item>` - passed in
# as arguments. It never enumerates worktrees and decides which look finished. Every
# sweep-by-computed-property tried in this workspace has taken something it should not have: an agent
# isolation worktree under `.claude/worktrees/` once, which left a running worker unresumable, and the
# author's own parallel session's worktree once, because its branch had merged and its tree was clean
# so the filter matched it.
#
# It also never runs `git worktree prune`, for the first of those reasons.

set -euo pipefail

WORKSPACE="C:/git/ago"

REPO="${1:-}"
ITEM="${2:-}"
CONFIRM="${3:-}"

[ -n "$REPO" ] && [ -n "$ITEM" ] || {
  echo "usage: bash tools/after-merge-cleanup.sh <repo> <item> [--yes]" >&2
  echo "  reports by default; --yes actually removes" >&2
  exit 2
}

PRIMARY="${WORKSPACE}/${REPO}"
TARGET="${WORKSPACE}/${REPO}-${ITEM}"

[ -d "$PRIMARY/.git" ] || { echo "refusing: no repository at $PRIMARY" >&2; exit 1; }

case "$TARGET" in
  *"/.claude/"*) echo "refusing: that path is inside .claude - agent isolation worktrees are never touched here" >&2; exit 1 ;;
esac

cd "$PRIMARY"
git fetch --quiet --prune origin

if [ ! -d "$TARGET" ]; then
  echo "nothing to do: $TARGET does not exist"
  exit 0
fi

BRANCH="$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
[ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ] || { echo "refusing: cannot read a branch name from $TARGET" >&2; exit 1; }

echo "worktree  $TARGET"
echo "branch    $BRANCH"

# Uncommitted work is the one thing that must never be thrown away silently. Untracked build output
# does not count - that is what this reclaims - so the check is on tracked changes only.
DIRTY="$(git -C "$TARGET" status --porcelain --untracked-files=no | wc -l)"
if [ "$DIRTY" -ne 0 ]; then
  echo
  echo "REFUSING: $DIRTY tracked change(s) are uncommitted here:" >&2
  git -C "$TARGET" status --short --untracked-files=no >&2
  echo "  Commit or discard them deliberately. This script will not decide that for you." >&2
  exit 1
fi

# Merged is asked of git, not of GitHub's API - a rebase-merge rewrites the SHA, so "is the branch an
# ancestor of main" answers false for work that certainly merged. `git cherry` compares patch content
# instead, which is what survives a rebase: an empty result means every commit on this branch is
# already present in origin/main by content.
UNMERGED="$(git cherry origin/main "$BRANCH" 2>/dev/null | grep -c '^+' || true)"
SIZE="$(du -sh "$TARGET" 2>/dev/null | cut -f1)"

echo "size      ${SIZE:-unknown}"
if [ "$UNMERGED" -ne 0 ]; then
  echo
  echo "REFUSING: $UNMERGED commit(s) on $BRANCH are not in origin/main by content:" >&2
  git cherry -v origin/main "$BRANCH" | grep '^+' | sed 's/^/  /' >&2
  echo "  This item is not finished. Land it before reclaiming its worktree." >&2
  exit 1
fi
echo "merged    yes (git cherry against origin/main is empty - survives a rebase-merge)"

REMOTE_HAS=""
git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1 && REMOTE_HAS="yes"

echo
if [ "$CONFIRM" != "--yes" ]; then
  echo "would remove the worktree, delete local branch '$BRANCH'${REMOTE_HAS:+, and delete origin/$BRANCH}"
  echo "re-run with --yes to do it"
  exit 0
fi

if [ -n "$REMOTE_HAS" ]; then
  git push --quiet origin --delete "$BRANCH"
  echo "deleted   origin/$BRANCH"
fi

git worktree remove "$TARGET"
echo "removed   $TARGET  (${SIZE:-unknown} reclaimed)"

git branch -q -D "$BRANCH"
echo "deleted   local branch $BRANCH"
