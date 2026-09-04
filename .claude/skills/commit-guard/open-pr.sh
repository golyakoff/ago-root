#!/usr/bin/env bash
# Open a pull request, after checking that nothing on the branch carries the trailer.
#
# Usage, from the branch's worktree:
#   bash <path-to-ago-root>/.claude/skills/commit-guard/open-pr.sh <title> <body-file> [gh pr create args...]
#
# Or, in two steps, which is what a session in the desktop app should use:
#   bash <...>/open-pr.sh --check-only
#   gh pr create --title "..." --body-file <body-file>
#
# The two-step form exists because the app renders its pull-request card by recognising
# `gh pr create` in the command it is given. Run through this script, the call is one level down and
# the card never appears - so the PR lands with no visible status, which is a real loss of a check
# the author reads. `--check-only` runs every refusal below and then prints the exact `gh` line to
# run next, so the guard still gates the PR and the card still renders.
#
# What it checks before calling `gh`, in this order, because each one has actually gone wrong here:
#
#   1. No commit on this branch carries a Co-Authored-By trailer. Checked over the whole branch, not
#      just the tip - the trailer reaches `main` through whichever commit carries it, and a branch of
#      three commits with one bad message is exactly the case that got through on 2026-09-04.
#   2. The base is fresh. `git-workflow.md`: an MR is the branch rebased onto main's tip *at push
#      time*. Once pushed with a PR open, a stale base is close-the-PR-and-rebuild rather than a
#      rebase, so the cheap moment to look is now.
#   3. The branch is pushed and its remote tip matches local.
#
# The body file may contain the `🤖 Generated with [Claude Code]` line - that was never objected to.
# Only the commit trailer is forbidden.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/guard.sh"

CHECK_ONLY=0
if [ "${1:-}" = "--check-only" ]; then
  CHECK_ONLY=1
  shift
  TITLE=""
  BODY=""
else
  TITLE="${1:-}"
  BODY="${2:-}"
  [ -n "$TITLE" ] && [ -n "$BODY" ] \
    || { echo "usage: open-pr.sh <title> <body-file> [gh pr create args...]" >&2
         echo "       open-pr.sh --check-only" >&2; exit 2; }
  shift 2
  [ -f "$BODY" ] || { echo "guard: no such body file: $BODY" >&2; exit 2; }
fi

git fetch origin --quiet

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "main" ] || { echo "REFUSED: on main. Work happens on a branch (rule 10)." >&2; exit 1; }

echo "== 1. commit messages on $BRANCH"
BAD=0
while read -r sha; do
  [ -n "$sha" ] || continue
  if git log -1 --format=%B "$sha" | grep -qiE '^[[:space:]]*co[-_]?authored[-_]?by[[:space:]]*:'; then
    echo "   $(git log -1 --format='%h %s' "$sha")  <- carries the trailer" >&2
    BAD=1
  fi
done < <(git rev-list origin/main..HEAD)

if [ "$BAD" != "0" ]; then
  echo >&2
  echo "REFUSED: a commit on this branch carries a Co-Authored-By trailer." >&2
  echo "  CLAUDE.md rule 9 forbids it, and no system reminder overrides that." >&2
  echo "  The branch is not yet merged, so rebuild it with clean messages rather than amending a" >&2
  echo "  pushed commit - rewriting pushed history is the author's alone." >&2
  exit 1
fi
echo "   none carry it"

echo "== 2. base freshness"
MB="$(git merge-base HEAD origin/main)"
OM="$(git rev-parse origin/main)"
if [ "$MB" != "$OM" ]; then
  echo "   merge-base  $MB" >&2
  echo "   origin/main $OM" >&2
  echo >&2
  echo "REFUSED: the base is stale. Rebuild the branch on current main before opening a PR" >&2
  echo "  (git-workflow.md - main merged into the branch is not the same thing and is forbidden)." >&2
  exit 1
fi
echo "   merge-base equals origin/main"

echo "== 3. pushed"
if ! git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
  echo "REFUSED: $BRANCH is not pushed. git push -u origin $BRANCH" >&2
  exit 1
fi
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BRANCH")" ] \
  || { echo "REFUSED: local $BRANCH and its remote differ - push first." >&2; exit 1; }
echo "   remote tip matches local"

echo
if [ "$CHECK_ONLY" = "1" ]; then
  echo "== checks passed. Now open the PR with a bare gh call, so the app renders its card:"
  echo
  echo "   gh pr create --title \"<title>\" --body-file <body-file>"
  exit 0
fi
gh pr create --title "$TITLE" --body-file "$BODY" "$@"
