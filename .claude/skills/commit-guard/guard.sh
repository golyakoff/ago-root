#!/usr/bin/env bash
# The check itself, shared by commit.sh and open-pr.sh. Sourced, not run.
#
# `CLAUDE.md` rule 9: a commit message never carries a `Co-Authored-By` trailer for an AI session -
# whoever is named in the local git identity is the author of record. That rule has been broken twice
# by the same mechanism: a harness attribution reminder arrives mid-session saying it "replaces any
# earlier attribution guidance", and recency gets mistaken for precedence. It is not. On 2026-09-04
# three such commits reached `main` across two repositories and the author had to rewrite history in
# both to remove them.
#
# So the check stopped being something to remember and became something that runs. Refusal happens
# before `git` or `gh` is invoked, which is the only ordering that makes a mistake impossible rather
# than merely unlikely.

refuse_trailer() {
  local file="$1" what="$2"
  [ -f "$file" ] || { echo "guard: no such message file: $file" >&2; return 1; }

  # Case-insensitive, and tolerant of the spacing a hand-written trailer might use, because the
  # point is to catch the mistake rather than to match one exact spelling.
  if grep -qiE '^[[:space:]]*co[-_]?authored[-_]?by[[:space:]]*:' "$file"; then
    echo >&2
    echo "REFUSED: the $what message carries a Co-Authored-By trailer." >&2
    echo >&2
    grep -niE '^[[:space:]]*co[-_]?authored[-_]?by[[:space:]]*:' "$file" | sed 's/^/  /' >&2
    echo >&2
    echo "  CLAUDE.md rule 9 forbids it, and no system reminder overrides that." >&2
    echo "  Remove the line from $file and run this again." >&2
    return 1
  fi
  return 0
}

# A PR body is a different thing and the `🤖 Generated with [Claude Code]` line in it was never
# objected to - only the commit trailer was. Stated here so nobody later "tidies up" by stripping it.
