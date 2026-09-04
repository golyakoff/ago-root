#!/usr/bin/env bash
# Commit, with the trailer check in front of git rather than in somebody's memory.
#
# Usage, from the repository or worktree being committed:
#   bash <path-to-ago-root>/.claude/skills/commit-guard/commit.sh <message-file> [git commit args...]
#
# The message must be in a file. That is not ceremony: a message passed inline goes through the shell,
# where backticks become command substitution and a `\n` becomes a real newline - both of which have
# already cost this project a rebuilt branch. A file is read verbatim by git.
#
# Everything after the message file is passed to `git commit` untouched, so `--amend`, `-a` and the
# rest still work.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/guard.sh"

MSG="${1:-}"
[ -n "$MSG" ] || { echo "usage: commit.sh <message-file> [git commit args...]" >&2; exit 2; }
shift

refuse_trailer "$MSG" "commit" || exit 1

# Say what is about to be committed before doing it. A commit that captured a file somebody else was
# still editing has happened here (2026-09-04, 22-16), and the fix was a second commit rather than an
# amend, because amending a pushed branch is the author's alone.
echo "== staged for commit"
git diff --cached --stat
echo

git commit -F "$MSG" "$@"

echo
git log --format='%h %s%n  trailer:[%(trailers:key=Co-Authored-By,valueonly)]' -1
