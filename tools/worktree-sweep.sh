#!/usr/bin/env bash
# Report - and optionally reclaim - every task worktree in the workspace.
#
# usage: bash tools/worktree-sweep.sh <report-file> [--yes]
#   without --yes  : reports a verdict per worktree, changes nothing
#   with    --yes  : hands each one to after-merge-cleanup.sh, which does its own refusing
#
# Read the report with:
#   cut -d'|' -f1 <report-file> | sort | uniq -c | sort -rn
#
# WHAT THIS IS FOR. On 2026-09-08 the workspace held 158 GB across 253 task worktrees, of which
# 147 GB was `bin/` and `obj/` belonging to work merged weeks earlier. This pass removed 152 of them
# and reclaimed 100.4 GB, taking the workspace to 59 GB. Every `.git` in the workspace together was
# 66 MB, so none of it was ever repository size.
#
# THE DIVISION OF LABOUR, WHICH IS THE SAFETY PROPERTY.
#
# This script **enumerates**. It never decides. Every removal decision is made inside
# `after-merge-cleanup.sh`, per directory, by its own refusals - uncommitted tracked work, or any
# commit not present in `origin/main` by content. That separation is deliberate: a sweep that both
# enumerates and decides is exactly the shape that has twice taken something it should not have here
# (the agent runtime's isolation worktrees, and another session's working directory).
#
# Anything not named `<repo>-<NN-NN>` is not considered at all, so `.claude/`, the primary checkouts
# and anything a person created by hand are outside its reach by construction rather than by a rule.
#
# VERDICTS
#   REMOVED / WOULD-REMOVE   merged by content, clean, reclaimable
#   KEEP-DIRTY               uncommitted tracked changes - a person decides
#   KEEP-UNMERGED            carries work not in origin/main - see the `leftover-branch-triage` skill
#   GONE                     directory no longer there
#   SKIP-IN-USE              the worktree this is being run from
#   UNKNOWN                  cleanup refused for another reason, usually a detached HEAD - look by hand

set -u

WS="C:/git/ago"
OUT="${1:?usage: worktree-sweep.sh <report-file> [--yes]}"
MODE="${2:-}"
SELF="$(basename "$(pwd)")"

: > "$OUT"

for d in "$WS"/*/; do
  name="$(basename "$d")"
  if ! [[ "$name" =~ ^(ago-[a-z-]+)-([0-9]+-[0-9]+[a-z]?)$ ]]; then continue; fi
  repo="${BASH_REMATCH[1]}"
  item="${BASH_REMATCH[2]}"
  [ -d "$WS/$repo/.git" ] || { echo "SKIP-NO-REPO|$name|" >> "$OUT"; continue; }
  [ "$name" = "$SELF" ] && { echo "SKIP-IN-USE|$name|" >> "$OUT"; continue; }

  res="$(bash "$WS/ago-root/tools/after-merge-cleanup.sh" "$repo" "$item" $MODE 2>&1)"
  size="$(printf '%s\n' "$res" | awk '/^size /{print $2}')"
  if printf '%s\n' "$res" | grep -q "REFUSING: .* uncommitted"; then
    echo "KEEP-DIRTY|$name|${size:-?}" >> "$OUT"
  elif printf '%s\n' "$res" | grep -q "REFUSING: .* not in origin/main"; then
    echo "KEEP-UNMERGED|$name|${size:-?}" >> "$OUT"
  elif printf '%s\n' "$res" | grep -q "^removed "; then
    echo "REMOVED|$name|${size:-?}" >> "$OUT"
  elif printf '%s\n' "$res" | grep -q "would remove"; then
    echo "WOULD-REMOVE|$name|${size:-?}" >> "$OUT"
  elif printf '%s\n' "$res" | grep -q "nothing to do"; then
    echo "GONE|$name|" >> "$OUT"
  else
    echo "UNKNOWN|$name|${size:-?}" >> "$OUT"
  fi
done

echo "DONE" >> "$OUT"

echo
awk -F'|' '{c[$1]++; s=$3
  if (s ~ /G$/) { sub("G","",s); v=s } else if (s ~ /M$/) { sub("M","",s); v=s/1024 } else v=0
  t[$1]+=v } END {
  for (k in c) printf "%-14s %4d  %6.1f GB\n", k, c[k], t[k] }' "$OUT" | sort -k2 -rn
