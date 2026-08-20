# Runbook: workspace layout

All repositories are siblings under one parent folder:

```
C:\git\ago\
  ago-root\  ago-platform\  ago-chat\  ago-widget\  ago-console\  ago-deploy\
```

## Junctions

`ago-root` exposes its siblings as `platform/`, `chat/`, `widget/`, `console/`, `deploy/` so a single
session can work across repositories. They are Windows junctions with **absolute** targets and are
gitignored, so they must be recreated after moving or renaming the tree:

```powershell
$root = 'C:\git\ago\ago-root'
foreach ($l in 'platform','chat','widget','console','deploy') {
  $p = Join-Path $root $l
  if (Test-Path $p) { (Get-Item $p).Delete() }
  New-Item -ItemType Junction -Path $p -Target "C:\git\ago\ago-$l" | Out-Null
}
```

Junctions need no administrator rights, unlike symbolic links. Nothing else depends on absolute
paths: every documentation link between repositories is relative.

## Moving or renaming the tree

1. Move or rename the folders.
2. Recreate the junctions with the snippet above.
3. Claude Code stores per-project memory and session history under a directory keyed by the working
   directory path (`~/.claude/projects/<escaped-path>/`). Renaming the project folder starts a new
   key, so copy the old `memory/` folder into the new one, or the accumulated notes silently vanish.
4. Nothing in `docs/` needs editing — check with `grep -rn "C:" docs/` and fix anything that turns up.

## Cloning fresh

Clone all six repositories into one parent folder, then run the junction snippet. The build and test
commands live in `local-dev.md`; the cluster in `k8s-local.md`.
