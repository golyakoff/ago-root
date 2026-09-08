#!/usr/bin/env bash
# Delete remote branches whose work is already in origin/main, across one repository.
#
# usage: bash tools/prune-merged-remote-branches.sh <repo> [--yes]
#   reports by default; --yes deletes
#
# WHY "MERGED" IS ASKED BY CONTENT AND NOT BY ANCESTRY.
#
# This project always merges with GitHub's Rebase and merge, which rewrites every commit's SHA. A
# branch that certainly merged is therefore **not** an ancestor of `main`, so `git branch --merged`
# and `git merge-base` both call finished work unmerged and would keep every branch forever - which
# is how 114 of them accumulated. `git cherry` compares patch *content* instead, and that survives the
# rewrite: an empty result means every commit on the branch is already present in `origin/main`.
#
# THREE THINGS IT WILL NOT DELETE, EACH FOR ITS OWN REASON.
#
#   - `main`, obviously, and any branch named as protected below.
#   - A branch with an **open pull request**. The PR is somebody's request for review; deleting its
#     head closes it silently and loses the discussion.
#   - A branch carrying any commit not in `origin/main` by content. That is unfinished work, and this
#     script has no way to tell abandoned from paused - only the author does.
#
# It reports every kept branch and why, so nothing disappears from view just because it survived.

set -uo pipefail

WORKSPACE="C:/git/ago"
PROTECTED="main master gh-pages"

REPO="${1:-}"
CONFIRM="${2:-}"
[ -n "$REPO" ] || { echo "usage: bash tools/prune-merged-remote-branches.sh <repo> [--yes]" >&2; exit 2; }

DIR="${WORKSPACE}/${REPO}"
[ -d "$DIR/.git" ] || { echo "refusing: no repository at $DIR" >&2; exit 1; }

cd "$DIR"
git fetch --quiet --prune origin

# Heads of open PRs are off limits. Asked once, not per branch.
OPEN_HEADS="$(gh pr list --state open --limit 300 --json headRefName -q '.[].headRefName' 2>/dev/null | tr '\n' ' ')"

deleted=0; kept_unmerged=0; kept_pr=0
to_delete=""

while IFS= read -r ref; do
  b="${ref#refs/heads/}"
  case " $PROTECTED " in *" $b "*) continue ;; esac
  case " $OPEN_HEADS " in *" $b "*) echo "  keep  $b  (open pull request)"; kept_pr=$((kept_pr+1)); continue ;; esac

  unmerged="$(git cherry origin/main "origin/$b" 2>/dev/null | grep -c '^+')"
  if [ "${unmerged:-1}" -ne 0 ]; then
    echo "  keep  $b  ($unmerged commit(s) not in main by content)"
    kept_unmerged=$((kept_unmerged+1))
    continue
  fi
  to_delete="$to_delete $b"
  deleted=$((deleted+1))
done < <(git ls-remote --heads origin | awk '{print $2}')

echo
if [ "$deleted" -eq 0 ]; then
  echo "$REPO: nothing to prune (kept $kept_unmerged unmerged, $kept_pr with open PRs)"
  exit 0
fi

if [ "$CONFIRM" != "--yes" ]; then
  echo "$REPO: would delete $deleted merged branch(es); kept $kept_unmerged unmerged, $kept_pr with open PRs"
  echo "  re-run with --yes to delete"
  exit 0
fi

# One push, not one per branch - 100 sequential deletes is 100 round trips.
# shellcheck disable=SC2086
git push --quiet origin $(for b in $to_delete; do printf -- "--delete %s " "$b"; done) 2>&1 | tail -3
echo "$REPO: deleted $deleted merged branch(es); kept $kept_unmerged unmerged, $kept_pr with open PRs"
