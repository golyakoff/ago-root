#!/usr/bin/env bash
# Point every repository in this workspace at the one commit-msg hook.
#
# Run once per machine, and again whenever this skill moves. Idempotent.
#
# WHY AN ABSOLUTE PATH, AND WHY THIS WAS WRONG THE FIRST TIME. The obvious install is to copy the
# hook into each repository's `.githooks` and set `core.hooksPath = .githooks`. That fails here, and
# it fails silently: **a relative `core.hooksPath` resolves against the current working tree**, so a
# worktree looks for `<worktree>/.githooks`, does not find it, and commits with no hook at all. Since
# nearly all work in this workspace happens in worktrees, the copy-per-repository version protects
# almost nothing while looking installed. Found by testing it: a `git commit -m` carrying the trailer
# went straight through.
#
# So: one hook file, referenced by absolute path. Every repository and every one of its worktrees runs
# the same file, and editing that file updates all of them at once.
#
# The cost, stated: the hook now lives outside each repository, so a fresh clone on another machine
# has no hook until this is run there. Hooks are never carried by a clone anyway - `.git/hooks` is not
# versioned - so this trades one kind of manual step for a better one.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HERE/hooks"
[ -x "$HOOKS/commit-msg" ] || [ -f "$HOOKS/commit-msg" ] \
  || { echo "missing $HOOKS/commit-msg" >&2; exit 1; }
chmod +x "$HOOKS/commit-msg" 2>/dev/null || true

WORKSPACE="${WORKSPACE:-C:/git/ago}"

# Named rather than globbed. A glob would sweep in worktrees, backup checkouts and anything else
# sitting in the workspace - the same class of mistake as sweeping worktrees by a computed property,
# which cost somebody their working session once (see `background-worker-brief`).
REPOS="ago-root ago-platform ago-chat ago-console ago-widget ago-calendar ago-calendar-console ago-deploy ago-landing ago-business"

installed=0
skipped=0

for name in $REPOS; do
  repo="$WORKSPACE/$name"
  if [ ! -e "$repo/.git" ]; then
    echo "   $name: not a repository here - skipped"
    skipped=$((skipped + 1))
    continue
  fi
  git -C "$repo" config core.hooksPath "$HOOKS"
  echo "   $name: core.hooksPath -> $HOOKS"
  installed=$((installed + 1))
done

echo
echo "$installed pointed at the hook, $skipped skipped."
echo
echo "Worktrees are covered: they share the parent repository's config, and the path is absolute so"
echo "it resolves the same from any of them. Verify in a worktree, not only in the main checkout -"
echo "that is where the relative-path version silently did nothing."
