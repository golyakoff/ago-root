#!/usr/bin/env bash
# Compare every open queue issue against the backlog item it names.
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

# **An unreachable GitHub must not read as a clean queue.** The previous version parsed a local
# markdown table, so it could not fail this way; this one can, and the failure is silent by default -
# an empty issue list and "0 checked, 0 flagged" is indistinguishable from a genuinely empty queue.
# `gh` returning nothing is therefore treated as "could not look", never as "nothing to see", and
# `--state open` plus a non-empty check is what separates the two.
if ! command -v gh >/dev/null 2>&1; then
  echo "CANNOT AUDIT - the GitHub CLI is not installed; the queue lives on the board and cannot be read."
  exit 0
fi

if ! issues=$(gh issue list --state open --limit 100 --json number,title --jq '.[]|"\(.number)|\(.title)"' 2>&1); then
  echo "CANNOT AUDIT - could not read issues from GitHub:"
  echo "  $issues"
  echo "This is NOT a clean queue - it is an unread one. Re-run when GitHub answers."
  exit 0
fi

rows=0
flagged=0

# Issue titles are `<item> · <summary>`, e.g. `20-20 · Make AGO Calendar deployable`. Only the
# leading token names the row's own item: matching an item id anywhere in the title once deleted the
# wrong row in the markdown era, because `5-17`'s entry cited `11-08` in its reasoning and a loose
# filter swept it along. The anchor is kept for the same reason.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  number=${line%%|*}
  title=${line#*|}
  item=$(printf '%s' "$title" | grep -oE '^[0-9]+-[0-9]+' || true)

  # An issue that is not a queue item (a bug report, a question) has no item prefix and is skipped
  # rather than flagged - this audit is about the queue, and refusing to look at anything else is
  # what keeps its output worth reading.
  [ -n "$item" ] || continue

  rows=$((rows + 1))
  file=$(find docs/backlog -maxdepth 1 -name "$item-*.md" | head -1)

  if [ -z "$file" ]; then
    echo "MISSING  $item  (#$number) - queue issue names an item with no backlog file"
    flagged=$((flagged + 1))
    continue
  fi

  open=$(grep -c '^- \[ \]' "$file" || true)
  done_=$(grep -c '^- \[x\]' "$file" || true)

  if [ "$open" = "0" ] && [ "$done_" != "0" ]; then
    status=$(grep -m1 '^- \*\*Status\*\*:' "$file" | cut -c1-72 || true)
    echo "STALE?   $item  (#$number) all $done_ Done-when ticked, none open"
    echo "         $status"
    echo "         $file"
    flagged=$((flagged + 1))
  fi
done <<< "$issues"

echo
echo "$rows queue issues checked, $flagged flagged."

# Flagged entries are for a human to resolve, so this is not an error exit - it is a report. A CI job
# that failed on this would train people to close issues to make it green, which is the opposite of
# the point.
exit 0
