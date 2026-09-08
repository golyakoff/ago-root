#!/usr/bin/env bash
# Create one task worktree, correctly, without anybody reasoning about it.
#
# usage: bash tools/new-worktree.sh <repo> <item> <branch-type> <slug>
#   e.g. bash tools/new-worktree.sh ago-console 23-105 feat setup-page-drops-data-booking
#
# Produces:
#   directory  C:/git/ago/<repo>-<item>
#   branch     <branch-type>/<item>-<slug>   cut from a freshly fetched origin/main
#
# WHY THIS IS A SCRIPT AND NOT A PARAGRAPH IN A BRIEF.
#
# Worktree creation was described in prose in `background-worker-brief` and repeated into every
# worker's instructions. Prose gets paraphrased, and the paraphrase is where it goes wrong: a worker
# lands in the primary checkout, or in a directory another task already holds, or cuts a branch from
# a `main` it never fetched. Each of those is invisible until it is expensive - a stale base becomes
# close-the-PR-and-rebuild the moment the branch is pushed (`CLAUDE.md` rule 10), and two tasks in one
# worktree is the failure rule 12 was written from.
#
# So the three things that actually have to be true are checked here, once, rather than remembered:
#   1. origin is fetched, and the branch is cut from origin/main's real tip;
#   2. the directory does not already exist and is not already a worktree;
#   3. the branch name is free.
# Any of them failing stops the script rather than producing something that looks right.
#
# WHAT THIS DELIBERATELY DOES NOT DO. It never removes anything. Worktree removal is by explicit name
# only (`workspace-cleanup`), because every sweep-by-computed-property tried here has taken something
# it should not have - an agent isolation worktree once, the author's own parallel session once.

set -euo pipefail

WORKSPACE="C:/git/ago"

REPO="${1:-}"
ITEM="${2:-}"
TYPE="${3:-}"
SLUG="${4:-}"

usage() {
  echo "usage: bash tools/new-worktree.sh <repo> <item> <branch-type> <slug>" >&2
  echo "  e.g. bash tools/new-worktree.sh ago-console 23-105 feat setup-page-drops-data-booking" >&2
  echo >&2
  echo "  <repo>        a directory under ${WORKSPACE} (ago-chat, ago-console, ago-widget, ...)" >&2
  echo "  <item>        the backlog item id, e.g. 23-105 - names the directory" >&2
  echo "  <branch-type> feat | fix | docs | chore | test" >&2
  echo "  <slug>        kebab-case, no item prefix - it is added" >&2
  exit 2
}

[ -n "$REPO" ] && [ -n "$ITEM" ] && [ -n "$TYPE" ] && [ -n "$SLUG" ] || usage

case "$TYPE" in
  feat|fix|docs|chore|test) ;;
  *) echo "refusing: '<branch-type>' must be one of feat, fix, docs, chore, test - got '$TYPE'" >&2; exit 2 ;;
esac

case "$ITEM" in
  [0-9]*-[0-9]*) ;;
  *) echo "refusing: '<item>' should look like 23-105 - got '$ITEM'" >&2; exit 2 ;;
esac

case "$SLUG" in
  "$ITEM"-*|*[A-Z_]*|*" "*)
    echo "refusing: '<slug>' is kebab-case and carries no item prefix - got '$SLUG'" >&2; exit 2 ;;
esac

PRIMARY="${WORKSPACE}/${REPO}"
TARGET="${WORKSPACE}/${REPO}-${ITEM}"
BRANCH="${TYPE}/${ITEM}-${SLUG}"

[ -d "$PRIMARY/.git" ] || { echo "refusing: no repository at $PRIMARY" >&2; exit 1; }

# 2. The directory must be free. Checked before the fetch, so a plain mistake costs nothing.
if [ -e "$TARGET" ]; then
  echo "refusing: $TARGET already exists." >&2
  echo "  If it belongs to a finished task, remove it BY NAME first:" >&2
  echo "    cd $PRIMARY && git worktree remove '$TARGET'" >&2
  echo "  If another task is using it, this task needs its own directory - never share one." >&2
  exit 1
fi

cd "$PRIMARY"

if git worktree list --porcelain | grep -qiF "worktree ${TARGET}"; then
  echo "refusing: git already registers a worktree at $TARGET even though the directory is gone." >&2
  echo "  Fix that one registration by name, and do not run 'git worktree prune' -" >&2
  echo "  it drops agent isolation worktrees too, which is how a running worker becomes unresumable." >&2
  exit 1
fi

# 1. Fetch, then cut from what was fetched. Not from whatever this checkout last saw.
echo "== fetching origin"
git fetch --quiet origin

MAIN="$(git rev-parse origin/main)"
echo "   origin/main is ${MAIN:0:7}"

# 3. The branch name must be free, locally and remotely - a remote branch with this name means
#    somebody already pushed this work, and starting again from main silently forks it.
if git show-ref --quiet "refs/heads/${BRANCH}"; then
  echo "refusing: local branch '${BRANCH}' already exists." >&2
  echo "  A task is finished in the worktree where it started - continue that one, do not fork it." >&2
  exit 1
fi
if git ls-remote --exit-code --heads origin "${BRANCH}" >/dev/null 2>&1; then
  echo "refusing: origin already has '${BRANCH}'." >&2
  echo "  That work is already pushed. Check it out rather than cutting a second branch from main." >&2
  exit 1
fi

echo "== creating worktree"
git worktree add -b "$BRANCH" "$TARGET" "$MAIN" >/dev/null

# Prove the base rather than assert it - this is the check `CLAUDE.md` rule 10 asks for, done here
# so the worker never has to, and so a wrong answer stops the script instead of reaching a push.
BASE="$(git -C "$TARGET" merge-base HEAD origin/main)"
if [ "$BASE" != "$MAIN" ]; then
  echo "refusing: the new worktree's base is ${BASE:0:7}, not origin/main ${MAIN:0:7}." >&2
  echo "  Removing it rather than leaving something that looks correct." >&2
  git worktree remove --force "$TARGET"
  exit 1
fi

echo
echo "   worktree  $TARGET"
echo "   branch    $BRANCH"
echo "   base      ${MAIN:0:7}  (equals origin/main - checked, not assumed)"
echo
echo "Start there with:"
echo "  cd $TARGET"
echo
echo "Commit through the guard, never with an inline -m:"
echo "  bash ${WORKSPACE}/ago-root/.claude/skills/commit-guard/commit.sh <message-file>"
