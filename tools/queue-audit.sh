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
# narrative; the item file holds the reasoning. `23-47` (2026-09-06) removed the board as a third
# claimant: the queue is not kept anywhere, board included - it is computed from these same issues,
# which is what `--ready` below does. This script is the thing that notices when a document asserts
# an order that does not match what is actually open.
#
# The check is deliberately dumb: an item whose Done-when list has no unchecked boxes left is
# reported. That is a heuristic, not a verdict - an item can legitimately sit in the queue with
# everything ticked while its PRs are still open. It is here to make somebody look, not to decide.
#
# Three ways to run it:
#   bash tools/queue-audit.sh            the full audit (unchanged shape, plus the UNSETTLED check below)
#   bash tools/queue-audit.sh --ready    which open ago-root items are ready to start right now
#   bash tools/queue-audit.sh --partial  which open ago-root items have a partial Done-when
#
# `--ready` and `--partial` read only `ago-root`'s own open issues - one `gh issue list` call, not the
# cross-repository sweep the full audit does - because readiness is a question about this repository's
# own queue, and because a Windows session hitting `gh`'s rate limit here would rather make one call
# than a hundred.

set -euo pipefail

cd "$(dirname "$0")/.."

MODE="full"
case "${1:-}" in
  --ready)   MODE="ready" ;;
  --partial) MODE="partial" ;;
  "")        MODE="full" ;;
  *)         echo "Usage: $0 [--ready|--partial]" >&2; exit 2 ;;
esac

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

# Hoisted here from the primary-checkout block below, because the per-issue checks need them too.
# `--git-common-dir` always resolves to the *primary* repository's `.git` from any worktree of it -
# this script is usually run from one, so the checkouts cannot be derived from `$0`.
primary_root="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
workspace="$(dirname "$primary_root")"

# **An unreachable GitHub must not read as a clean queue.** The pre-2026-09-02 version parsed a local
# markdown table, so it could not fail this way; this one can, and the failure is silent by default -
# an empty issue list and "0 checked, 0 flagged" is indistinguishable from a genuinely empty queue.
# `gh` returning nothing is therefore treated as "could not look", never as "nothing to see".
if ! command -v gh >/dev/null 2>&1; then
  echo "CANNOT AUDIT - the GitHub CLI is not installed; the queue is computed from GitHub issues and"
  echo "cannot be read without it."
  exit 0
fi

# ---------------------------------------------------------------------------
# Field readers, added 2026-09-06 (`23-47`, `23-50`). A backlog item's header is a handful of
# `- **Field**: value` bullets, and a value sometimes wraps onto continuation lines indented by two
# spaces with no `- **` of their own (e.g. `1-06`'s `Depends on`). These two functions are the one
# place that knows that shape, so the readiness and Done-when checks below read it the same way.
# ---------------------------------------------------------------------------

# Prints every line of one field's value, the first line (with its `- **Field**:` prefix) followed by
# any indented continuation lines, stopping at the first line that is neither.
extract_field() {
  local file="$1" field="$2"
  awk -v field="$field" '
    $0 ~ "^- \\*\\*" field "\\*\\*:" { p=1; print; next }
    p {
      if ($0 ~ /^  /) { print; next }
      exit
    }
  ' "$file"
}

# Same, collapsed to one line with the `- **Field**:` prefix stripped and internal whitespace
# normalised - the form every check below actually wants to reason about or print.
field_value() {
  local file="$1" field="$2"
  extract_field "$file" "$field" \
    | sed -E "1s/^- \\*\\*${field}\\*\\*: ?//" \
    | sed -E 's/^ +//' \
    | tr '\n' ' ' \
    | sed -E 's/ +/ /g; s/^ +//; s/ +$//'
}

# A `Status` value is READY only when it says exactly that and nothing more. Anything that starts
# with "ready" but goes on - `ready — blocked on the deploy`, `ready. **Answered by the author...**` -
# is QUALIFIED: a human wrote a reason next to the word, and this script is not the thing that decides
# whether that reason still blocks it. Guessing either way is exactly what `23-47`/`23-50` are about,
# so a qualified status is reported, never silently folded into READY or NOT_READY.
classify_status() {
  local lc
  lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    ready|"ready.") echo "READY" ;;
    ready*)         echo "QUALIFIED" ;;
    *)               echo "OTHER" ;;
  esac
}

# Classifies a `Depends on` value. Prints one word on its own line:
#   NONE          - says "nothing" (or a variant like "nothing new architecturally")
#   NONE_NOFIELD  - the file has no Depends-on field at all (the `Found`-defect convention - see the
#                   header survey in `23-47`'s report; every such file sampled was either done or a
#                   standalone defect, never a real unstated dependency)
#   OR            - "at least one of `a`/`b`/`c`" - a real dependency this script does not evaluate,
#                   because AND-ing them would be wrong and picking one would be guessing
#   UNPARSEABLE   - the field says something else with no item number in it (an ADR only, a provider,
#                   a person) - a real dependency this script cannot read, reported rather than assumed
#   PARSEABLE     - one or more item numbers, printed one per line after the marker
# `` `NN-NN` `` and `` `NN-NN-rest-of-filename.md` `` are both read; a bare, unquoted `NN-NN` is not -
# every citation surveyed for `23-47` used backticks, and matching bare digit pairs would also catch
# a date fragment such as the `09-06` inside `(2026-09-06)` on a `Status` line.
classify_depends() {
  local file="$1"
  local raw
  raw=$(field_value "$file" "Depends on")
  if [ -z "$raw" ]; then
    echo "NONE_NOFIELD"
    return
  fi
  local lc
  lc=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    nothing*) echo "NONE"; return ;;
  esac
  if printf '%s' "$lc" | grep -q "at least one of"; then
    echo "OR"
    return
  fi
  local refs
  refs=$(printf '%s' "$raw" | grep -oE '`[0-9]{1,2}-[0-9]{2}' | tr -d '`' | sort -u || true)
  if [ -z "$refs" ]; then
    echo "UNPARSEABLE"
    return
  fi
  echo "PARSEABLE"
  printf '%s\n' "$refs"
}

# **`23-50`'s answer, read literally: there is a question with an answer that changes as work lands -
# which open items are ready to start right now.** Not a list kept anywhere; recomputed on every run
# from the same issues `queue-audit.sh` already reads, plus the `Status`/`Depends on` fields of each
# one's backlog file. An item is READY when its own Status is plainly `ready` and every item it
# depends on is no longer open - "no longer open" rather than "closed done", because a dependency's own
# issue can be missing (never filed) or closed as not-planned and neither should block anything.
#
# **The three items already known to be blocked on something that is not another item** - `15-19`
# (the deploy), `17-14` (a scheduled Dependabot run), `24-07` (`25-01`, which the Depends-on line
# already says) - are not special-cased by number. `17-14`'s own Status does not say plain "ready", so
# it never enters this computation; `24-07`'s real dependency on `25-01` falls out of the ordinary
# PARSEABLE path since `25-01` is open; `15-19` has no Depends-on field and a qualified Status
# ("ready — **blocked on the deploy**"), so it lands in QUALIFIED, not READY. No number is hardcoded
# anywhere in this function - enumerating rather than keeping a list is the whole point of `23-47`.
compute_readiness() {
  local issues="$1"
  echo "Ready to start right now - computed from ago-root's open issues and their backlog files."
  echo "READY means: Status says plainly \"ready\", and every item this depends on is no longer open."
  echo "This is derived fresh on every run. Nothing here is kept between runs."
  echo

  local ready_list="" blocked_list="" qualified_list="" unknown_list="" nofile_list=""

  while IFS= read -r rdy_line; do
    [ -n "$rdy_line" ] || continue
    rdy_number=${rdy_line%%|*}
    rdy_title=${rdy_line#*|}
    rdy_item=$(printf '%s' "$rdy_title" | grep -oE '^[0-9]+-[0-9]+' || true)
    [ -n "$rdy_item" ] || continue

    rdy_file=$(find docs/backlog -maxdepth 1 -name "$rdy_item-*.md" | head -1)
    if [ -z "$rdy_file" ]; then
      nofile_list="${nofile_list}  ${rdy_item}  (ago-root#${rdy_number}) - no backlog file, cannot assess
"
      continue
    fi

    rdy_status_val=$(field_value "$rdy_file" "Status")
    rdy_st=$(classify_status "$rdy_status_val")

    if [ "$rdy_st" = "OTHER" ]; then
      continue
    fi
    if [ "$rdy_st" = "QUALIFIED" ]; then
      qualified_list="${qualified_list}  ${rdy_item}  (ago-root#${rdy_number})  Status: ${rdy_status_val}
"
      continue
    fi

    # rdy_st = READY from here on.
    rdy_dep_out=$(classify_depends "$rdy_file")
    rdy_dep_kind=$(printf '%s\n' "$rdy_dep_out" | head -1)
    rdy_refs=$(printf '%s\n' "$rdy_dep_out" | tail -n +2)

    case "$rdy_dep_kind" in
      NONE)
        ready_list="${ready_list}  ${rdy_item}  (ago-root#${rdy_number})
"
        ;;
      NONE_NOFIELD)
        ready_list="${ready_list}  ${rdy_item}  (ago-root#${rdy_number})  [no Depends-on field - treated as no dependency]
"
        ;;
      OR)
        unknown_list="${unknown_list}  ${rdy_item}  (ago-root#${rdy_number}) - Depends-on is an OR of several items, not AND; not evaluated:
      $(field_value "$rdy_file" "Depends on")
"
        ;;
      UNPARSEABLE)
        unknown_list="${unknown_list}  ${rdy_item}  (ago-root#${rdy_number}) - Depends-on names no item number this script can read:
      $(field_value "$rdy_file" "Depends on")
"
        ;;
      PARSEABLE)
        rdy_blockers=""
        for rdy_dep in $rdy_refs; do
          if printf '%s\n' "$issues" | grep -qE "\|${rdy_dep} · "; then
            rdy_blockers="$rdy_blockers $rdy_dep"
          fi
        done
        if [ -z "$rdy_blockers" ]; then
          ready_list="${ready_list}  ${rdy_item}  (ago-root#${rdy_number})
"
        else
          blocked_list="${blocked_list}  ${rdy_item}  (ago-root#${rdy_number}) - blocked on:${rdy_blockers}
"
        fi
        ;;
    esac
  done <<< "$issues"

  echo "READY NOW:"
  if [ -n "$ready_list" ]; then printf '%s' "$ready_list"; else echo "  none"; fi
  echo
  echo "BLOCKED on another open item:"
  if [ -n "$blocked_list" ]; then printf '%s' "$blocked_list"; else echo "  none"; fi
  echo
  echo "QUALIFIED - Status says \"ready\" plus more; read the qualifier yourself before treating as available:"
  if [ -n "$qualified_list" ]; then printf '%s' "$qualified_list"; else echo "  none"; fi
  echo
  echo "UNKNOWN - Status is ready but Depends-on cannot be read mechanically. Not a guess in either direction:"
  if [ -n "$unknown_list" ]; then printf '%s' "$unknown_list"; else echo "  none"; fi
  if [ -n "$nofile_list" ]; then
    echo
    echo "NO FILE - issue names an item with no backlog file, cannot assess:"
    printf '%s' "$nofile_list"
  fi
}

# `23-50`'s partial-report Done-when: "дай тикеты с частичным Done-when" as one command rather than a
# favour somebody has to remember to ask for.
partial_report() {
  local issues="$1"
  echo "Open ago-root items with a partial Done-when - some boxes settled, some not."
  echo

  local pr_found=0
  while IFS= read -r pr_line; do
    [ -n "$pr_line" ] || continue
    pr_number=${pr_line%%|*}
    pr_title=${pr_line#*|}
    pr_item=$(printf '%s' "$pr_title" | grep -oE '^[0-9]+-[0-9]+' || true)
    [ -n "$pr_item" ] || continue
    pr_file=$(find docs/backlog -maxdepth 1 -name "$pr_item-*.md" | head -1)
    [ -n "$pr_file" ] || continue
    pr_open_n=$(grep -c '^- \[ \]' "$pr_file" || true)
    pr_done_n=$(grep -c '^- \[x\]' "$pr_file" || true)
    if [ "$pr_open_n" != "0" ] && [ "$pr_done_n" != "0" ]; then
      echo "  ${pr_item}  (ago-root#${pr_number})  ${pr_done_n} ticked, ${pr_open_n} open"
      pr_found=$((pr_found + 1))
    fi
  done <<< "$issues"

  echo
  echo "${pr_found} open item(s) with a partial Done-when."
}

if [ "$MODE" != "full" ]; then
  if ! ready_issues=$(gh issue list --repo "$OWNER/ago-root" --state open --limit 100 \
                  --json number,title --jq '.[]|"\(.number)|\(.title)"' 2>&1); then
    echo "CANNOT AUDIT - could not read ago-root's open issues from GitHub:"
    echo "  $ready_issues"
    exit 1
  fi
  if [ "$MODE" = "ready" ]; then
    compute_readiness "$ready_issues"
  else
    partial_report "$ready_issues"
  fi
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

  # **Merged code under an open item.** The complement of the worktree check further down, and the one
  # that catches what that check cannot: work that was never written rather than written and left.
  #
  # 2026-09-05 is why this exists, and the instructive part is who it caught. That afternoon five items
  # were found whose documentation halves had been written and abandoned in worktrees; a check was added
  # for exactly that, and it worked - it flagged its own author's `23-27` within the hour. Then the same
  # session dropped `23-05` and `23-19` the same way, and the worktree check said nothing, correctly:
  # there was nothing in a worktree, because the half had never been written at all. Both times the code
  # merged in two repositories and the session moved to the next item in the same breath.
  #
  # A commit whose subject names this item, on `main`, with the item's issue still open, means the
  # landing is either mid-flight or was dropped - and only a person can tell which, which is why this
  # reports rather than fails.
  # `landed_repo`, not `repo`: shell functions share globals unless declared otherwise, and `audit_repo`
  # is holding its own `repo` while this runs. Reusing the name here made every issue after the first
  # report the wrong repository - caught by reading the output rather than by the check failing.
  for landed_repo in $MIRROR_REPOS; do
    dir="$workspace/$landed_repo"
    [ -e "$dir/.git" ] || continue
    landed=$(git -C "$dir" log --oneline origin/main --grep="($item)" -1 2>/dev/null || true)
    [ -n "$landed" ] || continue
    # Only worth reporting when this repository's own documentation has *not* followed it. `ago-root`
    # carrying a commit for the item is the signal that the half was written.
    docs=$(git -C "$primary_root" log --oneline origin/main --grep="$item" -1 2>/dev/null || true)
    if [ -z "$docs" ]; then
      echo "LANDED?  $item  ($where#$number) has merged code in $landed_repo but nothing in ago-root:"
      echo "         $landed"
      echo "         Either the documentation half is unwritten, or the item is mid-landing."
      flagged=$((flagged + 1))
    fi
    break
  done
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
# Checks that read *closed* issues, added 2026-09-04 and 2026-09-06 after the
# failures below were found by hand rather than by this script.
#
# Everything above answers one question: "this issue is open - is its item
# really unfinished?" That question cannot see any of the failures below,
# because in every one of them the issue is closed and the audit never looks
# at it. All these passes are `ago-root` only: it is the canonical queue, and
# the item files live here, so a mirror adds API calls without adding an
# answer.
#
# **How far back this looks, decided rather than drifted into (`23-49`):**
# --limit 500 is not a rolling window, it is "all of them" with headroom -
# checked on 2026-09-06, ago-root has 130 issues total (104 closed), starting
# at #312 on 2026-09-02. There is no pre-convention era to exclude: the
# per-item-issue convention and this repository's own issue tracking began at
# the same moment, so every closed issue that has ever existed here fits in
# one page today. The trigger to revisit this is size, not age - when the
# closed count approaches the limit, raise the limit first. A date cutoff
# only earns its keep once excluding old, pre-convention noise is a real
# problem rather than a hypothetical one, and it should carry its own reason
# the way NOT_SECRETS carries one per entry, not be added pre-emptively
# against items that do not exist yet.
# ---------------------------------------------------------------------------

if ! closed=$(gh issue list --repo "$OWNER/ago-root" --state closed --limit 500                 --json number,title,stateReason --jq '.[]|"\(.number)|\(.stateReason)|\(.title)"' 2>&1); then
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

# **A closed issue whose Done-when is not all settled.** `23-50`'s finding: everything above answers
# "does an open issue's file look finished" - this asks the opposite, unasked question, "does a closed
# issue's file actually say so". Three real defects were found by hand on 2026-09-06 because nothing
# checked this: `22-09` (closed "done except step 5", the last five ticks never came back for),
# `22-18` (closed with a box reading "not decided"), `17-11` (closed with "proven by an actual run"
# still unticked, and still not true two days later).
#
# Settled means `[x]`, or `[~]` with its own sentence explaining what shipped instead - `23-50`'s own
# third way to settle a box, "carried out to its own number", also ends as either `[x]` or `[~]` on
# the box itself, so nothing extra is needed here to recognise it. `grep -c '^- \[ \]'` already counts
# only the bare, unticked marker - a `[~]` line was never counted as open, so it needs no special
# handling to count as settled.
#
# Deliberately `ago-root` only, same reasoning as the two closed-issue checks above: the item files
# live here, and a mirror issue closing in a product repository says nothing about whether *this*
# repository's Done-when boxes are settled.
if [ -n "$closed" ]; then
  while IFS= read -r dw_line; do
    [ -n "$dw_line" ] || continue
    dw_number=${dw_line%%|*}
    dw_rest=${dw_line#*|}
    dw_stateReason=${dw_rest%%|*}
    dw_title=${dw_rest#*|}

    dw_item=$(printf '%s' "$dw_title" | grep -oE '^[0-9]+-[0-9]+' || true)
    [ -n "$dw_item" ] || continue

    dw_file=$(find docs/backlog -maxdepth 1 -name "$dw_item-*.md" | head -1)
    [ -n "$dw_file" ] || continue

    dw_open_n=$(grep -c '^- \[ \]' "$dw_file" || true)
    if [ "$dw_open_n" != "0" ]; then
      dw_status=$(field_value "$dw_file" "Status" | cut -c1-72)
      echo "UNSETTLED $dw_item  (ago-root#$dw_number, closed $dw_stateReason) has $dw_open_n unticked Done-when box(es)"
      echo "         Status: $dw_status"
      echo "         $dw_file"
      flagged=$((flagged + 1))
    fi
  done <<< "$closed"
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

# **A closed issue whose item never had a backlog file at all - the gap `23-49` itself is about.**
# Every check above reads an issue and asks something about it *against its file*: stale, ready but
# shipped, claimed twice, or naming something different. Every one of those questions presupposes a
# file exists to ask it of. An item that never had one is invisible to all four, because closing is
# the only thing that would make anyone look, and closing is exactly what stops anyone looking.
#
# Four items shipped this way and were found only because a person asked whether the queue was
# actually complete, not because anything mechanical noticed: `11-18` (closed as a duplicate inside
# fourteen minutes - no file, no commit anywhere, no trace but the issue itself), `11-19` (one
# commit), and `20-21` / `20-22` (nine commits each, cited by number in two other items' own files).
#
# The file-existence test is the same one `check_issue` uses for open issues above: any file whose
# name starts with the item number counts, regardless of which of two same-numbered issues it
# actually documents. That is deliberate, not a hole in this check - `11-17` legitimately names two
# different closed issues and carries one file between the two of them (`22-21`'s own resolution:
# skip a collision where nothing live wears the number), and this pass must not re-flag a collision
# that check already lets stand. It is why this looks for *a* file, never *the* file.
if [ -n "$closed" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    number=${line%%|*}
    rest=${line#*|}
    stateReason=${rest%%|*}
    title=${rest#*|}

    item=$(printf '%s' "$title" | grep -oE '^[0-9]+-[0-9]+' || true)
    [ -n "$item" ] || continue

    file=$(find docs/backlog -maxdepth 1 -name "$item-*.md" | head -1)
    if [ -z "$file" ]; then
      echo "NOFILE   $item  (ago-root#$number, closed $stateReason) - closed issue names an item with no backlog file at all"
      echo "         $title"
      flagged=$((flagged + 1))
    fi
  done <<< "$closed"
fi

# **A number named in a commit's own scope with no backlog file at all - not even an issue.** Every
# check above starts from a GitHub issue, open or closed, and asks something about its file. `22-26`
# and `22-27` (`22-29`) had neither: they exist only as `fix(22-26): ...` / `fix(22-27): ...` commits,
# with no issue ever filed in either repository. Walking issues cannot find a number that was never
# an issue - this is the one check here that does not start from one.
#
# The project's own commit convention is the mechanical foothold: a subject line's leading
# `type(NN-NN[, NN-NN...]):` names the item(s) a commit belongs to. This reads *subject lines only*,
# never bodies - `NN-NN` appears constantly in commit-message prose ("the identical failure `8-08`'s
# migrator hit", "cited by `20-21`"), and matching that would cry wolf on nearly every commit in this
# project. The scope position does not: checked against every subject on `origin/main` in every
# repository this script already reads while building this, it produced exactly three hits, all real
# - `22-25`, `22-26`, `22-27` - and zero from prose.
#
# Ground truth is a backlog *file*, not an issue, unlike every check above - matching against issues
# was tried first and is nearly useless here: the per-item-issue convention began at `ago-root#312` on
# 2026-09-02, so every item from the stages before that has commits naming it and no issue at all, and
# checking issues flagged well over a hundred of them. A file is the one record that has existed since
# the start of the project, so it is what "this number is taken" actually means.
#
# `origin/main` only, not `--all`: a long-lived feature branch repeats its own commits under fresh
# hashes every rebase, and `sort -u` on subjects already collapses what a cherry-pick or rebase-merge
# leaves duplicated - `origin/main` is both cheaper and what "shipped" means everywhere else here.
#
# No `gh` call: this needs nothing but the local clones the rest of the script already has, so it
# still runs when GitHub does not answer.
for scoperepo in "$primary_root" $(printf '%s\n' $MIRROR_REPOS | sed "s|^|$workspace/|"); do
  [ -e "$scoperepo/.git" ] || continue
  while IFS= read -r subj; do
    [ -n "$subj" ] || continue
    scope=$(printf '%s' "$subj" | sed -nE 's/^[a-z]+\(([^)]+)\):.*/\1/p')
    [ -n "$scope" ] || continue
    for scope_item in $(printf '%s' "$scope" | tr ',' '\n' | sed -E 's/^ +| +$//g'); do
      printf '%s' "$scope_item" | grep -qE '^[0-9]+-[0-9]+$' || continue
      find docs/backlog -maxdepth 1 -name "${scope_item}-*.md" 2>/dev/null | grep -q . && continue
      echo "ORPHAN   $scope_item named in a commit scope in $(basename "$scoperepo") but has no backlog file at all:"
      echo "         $subj"
      flagged=$((flagged + 1))
    done
  done < <(git -C "$scoperepo" log --oneline origin/main --format='%s' 2>/dev/null | sort -u)
done

echo
echo "$rows queue issues checked across $(( $(printf '%s\n' $MIRROR_REPOS | wc -l) + 1 )) repositories, $flagged flagged."

if [ "$unread" != "0" ]; then
  echo
  echo "$unread repositor$( [ "$unread" = 1 ] && echo y || echo ies) could NOT be read."
  echo "This is NOT a clean queue - it is a partly unread one. Re-run when GitHub answers."
fi

# --- Uncommitted work sitting in a primary checkout ------------------------------------------------
#
# Every worktree rule in this project says work happens in a worktree named for its item, never in the
# repository's own checkout. Twice on 2026-09-04 a background worker wrote its `ago-root` changes into
# `C:/git/ago/ago-root` instead, because its own commit-prep block began `cd C:/git/ago/ago-root`. The
# first time it was caught by accident - a `git pull` refused. The second time the changes were
# genuinely lost: the primary checkout had advanced three times while the work sat there uncommitted.
#
# Prevention was considered and rejected. Making the primary checkouts bare would remove the working
# tree a stray edit can land in - but `ago-root`'s tree is what everything reads: `CLAUDE.md`, the
# docs every brief cites, `tools/` including this script, and `.claude/skills/commit-guard/hooks`,
# which `core.hooksPath` names by absolute path. Making it bare would delete the reference, the commit
# gate and the audit at once.
#
# So this is detection instead, and it lives here because this is the script that actually gets run at
# every merge. It reports rather than fails, for the same reason the flagged entries above do.
echo
# This script is usually run from a worktree, so the primary checkouts cannot be derived from $0.
# `--git-common-dir` always resolves to the *primary* repository's `.git`, from any worktree of it -
# which is the same property that makes `core.hooksPath` work, and the same one whose absence made the
# per-worktree `info/exclude` silently do nothing.

primary_dirty=0
for dir in "$primary_root" $(printf '%s\n' $MIRROR_REPOS | sed "s|^|$workspace/|"); do
  [ -e "$dir/.git" ] || continue
  # Tracked changes only. Untracked files in a primary checkout are ordinary scratch and are not the
  # failure this looks for - the failure is *edits to tracked files* that no branch will ever carry.
  dirty="$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null)" || continue
  if [ -n "$dirty" ]; then
    primary_dirty=$((primary_dirty + 1))
    echo "UNCOMMITTED  $dir (on $(git -C "$dir" rev-parse --abbrev-ref HEAD)) carries tracked changes:"
    printf '%s\n' "$dirty" | sed 's/^/             /'
    echo "             This belongs in a worktree. It is on no branch, and the next pull or checkout here destroys it."
  fi
done
[ "$primary_dirty" = "0" ] && echo "No primary checkout carries uncommitted tracked changes."

echo
# **Work that exists only as uncommitted files in a worktree is invisible to everything else.** Not to
# this script before today, not to `git log --grep` (which finds commits), not to CI, not to the board.
# The item's queue row stays open and honest the whole time - and *open* and *nobody has started* look
# identical, so the next brief written from that row rediscovers what was already built.
#
# 2026-09-05 is why this exists. Four items were found in one afternoon whose work had been written and
# left behind: `23-17`'s console half twice, in two worktrees, plus a documentation half in a third that
# contained the item's own ADR; and the documentation halves of `23-06`, `23-22` and `24-11`, two of
# which also carried an ADR (`0109`, `0110`). Three ADRs in total had been written while their code was
# merged, which is what the gaps in `docs/adr/README.md`'s numbering actually were. Every one was found
# by accident, by somebody reading nearby code for an unrelated reason.
#
# This reports every worktree carrying uncommitted tracked changes, and says whether its item is still
# open. In-flight work shows up here too and that is correct - the line is a statement of what exists
# nowhere else, not an accusation. What it makes impossible is *not knowing*.
# Two passes rather than one list, because the two cases need different amounts of attention. A
# worktree for an item that is still open may be the half nobody knows exists - that one gets its
# files printed. A worktree for an item already closed is almost always a leftover from a rebuild,
# so it gets a single line: worth removing, not worth reading.
wt_open=""
wt_closed=""
for dir in "$primary_root" $(printf '%s\n' $MIRROR_REPOS | sed "s|^|$workspace/|"); do
  [ -e "$dir/.git" ] || continue
  for wt in $(git -C "$dir" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}'); do
    [ "$wt" = "$dir" ] && continue
    # `.claude/worktrees/` is the agent runtime's own isolation, not task work. Never reported and
    # never touched: pruning those is what once left a worker unable to resume.
    case "$wt" in *".claude/worktrees"*) continue ;; esac
    dirty="$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" || continue
    [ -n "$dirty" ] || continue
    item="$(basename "$wt" | grep -oE '[0-9]+-[0-9]+' | head -1 || true)"
    if [ -n "$item" ] && printf '%s\n' "$open_raw" | grep -qE "\|$item · "; then
      wt_open="$wt_open$wt|$item
$(printf '%s\n' "$dirty" | head -8 | sed 's/^/    /')
"
    else
      wt_closed="$wt_closed  $wt
"
    fi
  done
done

if [ -n "$wt_open" ]; then
  echo "Uncommitted work in a worktree, for an item that is still OPEN:"
  printf '%s' "$wt_open" | while IFS= read -r line; do
    case "$line" in
      *"|"[0-9]*) echo "  $(printf '%s' "$line" | cut -d'|' -f1)  ($(printf '%s' "$line" | cut -d'|' -f2) is open)" ;;
      *) [ -n "$line" ] && echo "  $line" ;;
    esac
  done
  echo "  This exists nowhere else. It is on no branch and in no commit, so nothing else can see it -"
  echo "  not this script's other checks, not \`git log --grep\`, not CI, not the board."
fi

if [ -n "$wt_closed" ]; then
  echo
  echo "Uncommitted changes in worktrees whose item is already closed (leftovers, safe to remove once read):"
  printf '%s' "$wt_closed"
fi

[ -z "$wt_open$wt_closed" ] && echo "No worktree carries uncommitted tracked changes."

# An ADR file with no row in docs/adr/README.md. The index is the only place the decisions can be read
# as a set, so an ADR missing from it is a decision nobody browsing will find - and the gap is created
# by exactly the situation that makes it hard to avoid: `land-a-slice` forbids two open pull requests
# touching README.md at once, so a second and third concurrent ADR deliberately ship without their row
# and somebody is supposed to remember. On 2026-09-06 three were open at the same time.
# This turns remembering into looking.
# Read THIS working tree, not `primary_root` - unlike the checks above, which ask "what does the
# repository as a whole know", this one asks "is the change in front of me complete", and the change
# being made is in whichever worktree the script was run from. Using `primary_root` here made the check
# report a missing row that the very edit adding it had just written, one directory away.
audit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
missing_rows=""
for adr in "$audit_root"/docs/adr/[0-9][0-9][0-9][0-9]-*.md; do
  [ -e "$adr" ] || continue
  n=$(basename "$adr"); n=${n%%-*}
  grep -q "^| *$n *|" "$audit_root/docs/adr/README.md" || missing_rows="$missing_rows  $n  ($(basename "$adr"))
"
done

echo
if [ -n "$missing_rows" ]; then
  echo "ADR files with no row in docs/adr/README.md:"
  printf "$missing_rows"
  echo "  Add the row in the next ago-root change. An ADR outside the index is a decision that"
  echo "  cannot be found by anyone reading the decisions as a set."
else
  echo "Every ADR file has a row in docs/adr/README.md."
fi

# A skill without YAML frontmatter is never registered, so it can never be offered and can never be
# invoked - it is a file, not a skill. Nothing said so until 2026-09-08, when three were found in that
# state at once: `user-story-writer`, `finish-an-item`, and `commit-guard` - the last written
# specifically to stop the shell-quoting failures and the forbidden trailer, and bypassed every single
# time for two weeks because it could not be seen. SKILLS.md listed all three, correctly, which is
# what made it invisible: the index said the skill existed and the runtime disagreed, and nothing
# compared them.
#
# This is the cheapest possible check for the most expensive possible failure - a control that is
# believed to be running and is not.
headerless=""
for skill in "$audit_root"/.claude/skills/*/SKILL.md; do
  [ -e "$skill" ] || continue
  if [ "$(head -1 "$skill")" != "---" ]; then
    headerless="$headerless  $(basename "$(dirname "$skill")")
"
  fi
done

echo
if [ -n "$headerless" ]; then
  echo "Skills with no YAML frontmatter (they are never registered, so they can never be used):"
  printf "$headerless"
  echo "  Add 'name:' and 'description:' between --- fences at the top of SKILL.md."
else
  echo "Every skill carries frontmatter and can actually be invoked."
fi

# Flagged entries are for a human to resolve, so this is not an error exit - it is a report. A CI job
# that failed on this would train people to close issues to make it green, which is the opposite of
# the point.
exit 0
