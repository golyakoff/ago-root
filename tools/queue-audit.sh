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
open_raw=""

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

  # Kept for the two closed-issue passes at the bottom, which need to know which items are still
  # open. Stashed here rather than fetched again: one call, one answer, no chance of the two
  # disagreeing because something was closed between them.
  if [ "$repo" = "ago-root" ]; then
    open_raw="$issues"
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

# ---------------------------------------------------------------------------
# Two checks that read *closed* issues, added 2026-09-04 after both failures
# below were found by hand rather than by this script.
#
# Everything above answers one question: "this issue is open - is its item
# really unfinished?" That question cannot see either of the failures below,
# because in both of them the issue is closed and the audit never looks at it.
# Both passes are `ago-root` only: it is the canonical queue, and the item files
# live here, so a mirror adds API calls without adding an answer.
# ---------------------------------------------------------------------------

if ! closed=$(gh issue list --repo "$OWNER/ago-root" --state closed --limit 300                 --json number,title,stateReason --jq '.[]|"\(.number)|\(.stateReason)|\(.title)"' 2>&1); then
  echo "CANNOT AUDIT ago-root's closed issues - could not read them from GitHub:"
  echo "  $closed"
  unread=$((unread + 1))
  closed=""
fi

# **A file that still says `ready` for work that has shipped.** The mirror image of the check above,
# and the more dangerous half: a stale *open* issue merely lingers, but a file saying `Status: ready`
# is an invitation, and the next session takes it. Seven files were in this state on 2026-09-04 -
# `11-16`, `13-08`, `15-13`, `15-17`, `17-12`, `22-15`, `22-16` - three of them shipped that same
# morning. The audit reported a clean queue throughout, correctly by its own definition and
# uselessly.
#
# Flagged only when a *closed* issue names the item. A `ready` file with no issue at all is an
# ordinary un-queued backlog item, which is a legitimate state and not this script's business.
if [ -n "$closed" ]; then
  for file in docs/backlog/*.md; do
    grep -q '^- \*\*Status\*\*: ready' "$file" || continue
    item=$(basename "$file" | grep -oE '^[0-9]+-[0-9]+' || true)
    [ -n "$item" ] || continue

    # An item whose issue is still open is the first check's business, not this one's.
    if printf '%s
' "$open_raw" | grep -qE "\|$item · "; then
      continue
    fi

    hit=$(printf '%s
' "$closed" | grep -E "\|$item · " | head -1 || true)
    [ -n "$hit" ] || continue

    rest=${hit#*|}
    echo "READY?   $item  (ago-root#${hit%%|*}) is closed as ${rest%%|*}"
    echo "         but $file still says Status: ready"
    flagged=$((flagged + 1))
  done
fi

# **One number, two items.** `NN-NN ·` is the only thing tying an issue to its backlog file, its
# stage, its ADRs and its commits, so a number used twice makes every one of those links ambiguous.
# It happens when a defect is filed with "the next free number" without checking that a *file* with
# that number already exists - the file is not on the board, so nothing shows it.
#
# Found 2026-09-04: `20-21` and `20-22` each named both an unstarted planned item (a file, from
# `adr/0090`) and a calendar defect that had already shipped with `feat(20-21)`/`feat(20-22)` commits.
# Three earlier pairs - `10-06`, `11-17`, `15-11` - had the same shape and were closed on both sides,
# so nothing was left to fix but nothing had noticed either.
#
# Duplicates are counted **within one repository**. An item legitimately has one issue here and one
# in the repository it changes; that pair is the mirror convention, not a collision.
if [ -n "$closed" ]; then
  duplicates=$(printf '%s
' "$closed" "$open_raw"     | grep -oE '\|[0-9]+-[0-9]+ ·' | tr -d '|·' | tr -d ' ' | sort | uniq -d || true)
  for item in $duplicates; do
    # Same "finished on every side is history" rule the MISMATCH pass below states in full: skip when
    # no issue with this number is open and its backlog file, if any, says done.
    if ! printf '%s
' "$open_raw" | grep -qE "\|$item · "; then
      dup_file=$(find docs/backlog -maxdepth 1 -name "$item-*.md" | head -1)
      if [ -z "$dup_file" ] || grep -qE '^- \*\*Status\*\*: done' "$dup_file"; then
        continue
      fi
    fi

    echo "TWICE    $item  is claimed by more than one ago-root issue:"
    printf '%s
' "$closed" "$open_raw" | grep -E "\|$item · " | while IFS= read -r row; do
      echo "         ago-root#${row%%|*}  ${row##*|}"
    done
    echo "         A number names one item. Renumber whichever side has not shipped."
    flagged=$((flagged + 1))
  done
fi

# **The collision that the check above cannot see, and the only one that was still live.** Two
# issues sharing a number is the easy shape. The dangerous shape is an issue and a *file* sharing
# one: `20-21` and `20-22` each named an unstarted planned item that had a backlog file and no issue,
# and a calendar defect that had an issue and had already shipped. Nothing above notices, because
# there is only ever one issue per number.
#
# So this compares the file's own title to the title of the issue bearing its number. Deliberately
# crude - a word-overlap ratio, not a judgement - because it exists to make somebody look. A title
# that was reworded after filing will trip it; that is a cheap false positive against a failure that
# otherwise surfaces only when somebody reads two documents side by side and happens to notice.
significant_words() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '
' | awk 'length($0) > 3' | sort -u
}

if [ -n "$closed" ]; then
  for file in docs/backlog/*.md; do
    item=$(basename "$file" | grep -oE '^[0-9]+-[0-9]+' || true)
    [ -n "$item" ] || continue

    issue_row=$(printf '%s
' "$open_raw" "$closed" | grep -E "\|$item · " | head -1 || true)
    [ -n "$issue_row" ] || continue

    # **A collision both of whose sides have finished is history, not a defect.** Nothing live is
    # wearing the wrong number: no open issue, and a file whose own Status says done. Reporting it
    # for ever would train people to read past this check's output, which is the only thing it has.
    # The alternative - a hand-kept list of accepted pairs - is a second source of truth that drifts
    # and would itself need auditing, the same reason the item-to-issue mapping here is derived
    # rather than stored. `22-21` resolved the two live pairs and left six closed ones behind.
    if printf '%s
' "$open_raw" | grep -qE "\|$item · "; then
      :
    elif grep -qE '^- \*\*Status\*\*: (done|.*— done)' "$file"          || grep -qE '^- \*\*Status\*\*: done' "$file"; then
      continue
    fi

    file_title=$(head -1 "$file" | sed 's/^# *//')
    issue_title=${issue_row##*· }

    file_words=$(significant_words "$file_title")
    [ -n "$file_words" ] || continue
    total=$(printf '%s
' "$file_words" | wc -l)
    shared=$(comm -12 <(printf '%s
' "$file_words") <(significant_words "$issue_title") | wc -l)

    # A third of the file title's own words is the line between "reworded" and "a different item".
    if [ "$((shared * 3))" -lt "$total" ]; then
      echo "MISMATCH $item  (ago-root#${issue_row%%|*}) names a different thing than its file:"
      echo "         issue: $issue_title"
      echo "         file:  $file_title"
      echo "         $shared of $total words shared. One number names one item - check for a collision."
      flagged=$((flagged + 1))
    fi
  done
fi

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
