#!/usr/bin/env bash
# Compare every row of `docs/roadmap.md`'s "Now" queue against the backlog item it names.
#
# Why this exists: the queue is a hand-maintained list, and the one edit that is easy to forget is
# the one that happens last - taking a row out after its PRs merge. Three rows have outlived their
# items so far (`15-03`, `16-01`, and `17-08`'s own), and each was found by accident rather than by
# looking. An item still in the queue is offered to the next session as available work, so a stale
# row does not merely read wrong, it gets picked up and re-done.
#
# The check is deliberately dumb: an item whose Done-when list has no unchecked boxes left is
# reported. That is a heuristic, not a verdict - an item can legitimately sit in the queue with
# everything ticked while its PRs are still open. It is here to make somebody look, not to decide.
#
# Run from the repository root:  bash tools/queue-audit.sh

set -euo pipefail

cd "$(dirname "$0")/.."

rows=0
flagged=0

# The item column is anchored on purpose. Matching an item name anywhere in the line once deleted
# the wrong row: `5-17`'s entry cites `11-08` in its reasoning, so a loose filter swept it along
# with `11-08`. Only the second column names the row's own item.
while IFS= read -r item; do
  rows=$((rows + 1))
  file=$(find docs/backlog -maxdepth 1 -name "$item-*.md" | head -1)

  if [ -z "$file" ]; then
    echo "MISSING  $item  - queue row names an item with no backlog file"
    flagged=$((flagged + 1))
    continue
  fi

  open=$(grep -c '^- \[ \]' "$file" || true)
  done_=$(grep -c '^- \[x\]' "$file" || true)

  if [ "$open" = "0" ] && [ "$done_" != "0" ]; then
    status=$(grep -m1 '^- \*\*Status\*\*:' "$file" | cut -c1-72 || true)
    echo "STALE?   $item  all $done_ Done-when ticked, none open"
    echo "         $status"
    echo "         $file"
    flagged=$((flagged + 1))
  fi
done < <(grep -oP '^\| \d+ \| `\K[0-9]+-[0-9]+' docs/roadmap.md)

echo
echo "$rows queue rows checked, $flagged flagged."

# Flagged rows are for a human to resolve, so this is not an error exit - it is a report. A CI job
# that failed on this would train people to sweep rows to make it green, which is the opposite of
# the point.
exit 0
