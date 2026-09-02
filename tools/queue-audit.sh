#!/usr/bin/env bash
# Compare every open queue issue against the backlog item it names - in `ago-root` and in the code
# repositories alike.
#
# Why this exists: the queue is hand-maintained, and the one edit that is easy to forget is the one
# that happens last - closing an item's entry after its PRs merge. Three entries have outlived their
# items so far (`15-03`, `16-01`, and `17-08`'s own), and each was found by accident rather than by
# looking. An item still in the queue is offered to the next session as available work, so a stale
# entry does not merely read wrong, it gets picked up and re-done.
#
# **Reads GitHub issues, not `docs/roadmap.md`** (changed 2026-09-02, when the Now queue moved to the
# board at https://github.com/users/golyakoff/projects/1). The roadmap's stage sections stay as
# narrative; the board holds status and order; the item file holds the reasoning. This script is the
# thing that notices when the first two disagree with the third.
#
# The check is deliberately dumb: an item whose Done-when list has no unchecked boxes left is
# reported. That is a heuristic, not a verdict - an item can legitimately sit in the queue with
# everything ticked while its PRs are still open. It is here to make somebody look, not to decide.
#
# Run from anywhere inside the repository:  bash tools/queue-audit.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# **Items are filed twice**, once here and once in the repository they change, and closing only one
# of the pair is a real, observed failure: on 2026-09-02 `11-15` shipped, `ago-root#322` was closed,
# and its twin `ago-calendar-console#27` stayed open. This script reported "6 queue issues checked,
# 0 flagged" and the mirror was found only because the author asked whether tickets were being
# closed at all.
#
# **The mapping between an item and its mirrors is deliberately not stored anywhere.** A
# hand-maintained item-to-issue table would be a second source of truth that drifts, which is the
# exact failure being fixed - the table would then need auditing itself. The mapping already exists
# in the `NN-NN · Title` issue-title convention, so it is derived instead.
#
# The one thing that genuinely is not derivable is which repositories to look in.
# `docs/runbooks/workspace.md` lists them, but as a prose directory tree - parsing that would be
# brittle in a way that fails silently, which is worse than a list somebody has to remember to
# extend. A new repository missing from here shows up as an audit that never mentions it.
MIRROR_REPOS="ago-chat ago-console ago-widget ago-calendar ago-calendar-console ago-deploy ago-landing ago-platform"

OWNER=golyakoff

# **An unreachable GitHub must not read as a clean queue.** The pre-2026-09-02 version parsed a local
# markdown table, so it could not fail this way; this one can, and the failure is silent by default -
# an empty issue list and "0 checked, 0 flagged" is indistinguishable from a genuinely empty queue.
# `gh` returning nothing is therefore treated as "could not look", never as "nothing to see".
if ! command -v gh >/dev/null 2>&1; then
  echo "CANNOT AUDIT - the GitHub CLI is not installed; the queue lives on the board and cannot be read."
  exit 0
fi

rows=0
flagged=0
unread=0

# One rule, not two. Both passes call this, so the `ago-root` check and the mirror check cannot drift
# apart into different definitions of "looks done".
#
# Issue titles are `<item> · <summary>`, e.g. `20-20 · Make AGO Calendar deployable`. Only the
# leading token names the issue's own item: matching an item id anywhere in the title once deleted
# the wrong row in the markdown era, because `5-17`'s entry cited `11-08` in its reasoning and a
# loose filter swept it along. The anchor is kept for the same reason.
check_issue() {
  where=$1
  number=$2
  title=$3

  item=$(printf '%s' "$title" | grep -oE '^[0-9]+-[0-9]+' || true)

  # An issue that is not a queue item has no item prefix and is skipped rather than flagged. That
  # covers deliberate non-item prefixes already in use (`deps ·`, `ux ·`) as well as plain bug
  # reports and questions. This audit is about the queue, and refusing to look at anything else is
  # what keeps its output worth reading.
  [ -n "$item" ] || return 0

  rows=$((rows + 1))
  file=$(find docs/backlog -maxdepth 1 -name "$item-*.md" | head -1)

  if [ -z "$file" ]; then
    echo "MISSING  $item  ($where#$number) - queue issue names an item with no backlog file"
    flagged=$((flagged + 1))
    return 0
  fi

  open=$(grep -c '^- \[ \]' "$file" || true)
  done_=$(grep -c '^- \[x\]' "$file" || true)

  if [ "$open" = "0" ] && [ "$done_" != "0" ]; then
    status=$(grep -m1 '^- \*\*Status\*\*:' "$file" | cut -c1-72 || true)
    echo "STALE?   $item  ($where#$number) all $done_ Done-when ticked, none open"
    echo "         $status"
    echo "         $file"
    flagged=$((flagged + 1))
  fi
}

# Read one repository's open issues, or say plainly that it could not be read. Per repository rather
# than once for everything, so a single unreachable repository shrinks the audit *visibly* instead of
# silently narrowing its scope while the summary still reads clean.
audit_repo() {
  repo=$1
  if ! issues=$(gh issue list --repo "$OWNER/$repo" --state open --limit 100 \
                  --json number,title --jq '.[]|"\(.number)|\(.title)"' 2>&1); then
    echo "CANNOT AUDIT $repo - could not read issues from GitHub:"
    echo "  $issues"
    unread=$((unread + 1))
    return 0
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    check_issue "$repo" "${line%%|*}" "${line#*|}"
  done <<< "$issues"
}

audit_repo ago-root
for repo in $MIRROR_REPOS; do
  audit_repo "$repo"
done

echo
echo "$rows queue issues checked across $(( $(printf '%s\n' $MIRROR_REPOS | wc -l) + 1 )) repositories, $flagged flagged."

if [ "$unread" != "0" ]; then
  echo
  echo "$unread repositor$( [ "$unread" = 1 ] && echo y || echo ies) could NOT be read."
  echo "This is NOT a clean queue - it is a partly unread one. Re-run when GitHub answers."
fi

# Flagged entries are for a human to resolve, so this is not an error exit - it is a report. A CI job
# that failed on this would train people to close issues to make it green, which is the opposite of
# the point.
exit 0
