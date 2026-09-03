# Runbook: workspace layout

All repositories are siblings under one parent folder:

```
C:\git\ago\
  ago-root\  ago-platform\  ago-chat\  ago-calendar\  ago-widget\  ago-console\  ago-deploy\
  ago-landing\  ago-calendar-console\  .nuget-feed\
```

`ago-calendar-console` arrived with `20-06` (`adr/0064`) — AGO Calendar's own operator SPA, separate
from `ago-console` because the two track different products' API contracts and deploy independently.
There is deliberately **no** `ago-calendar-widget`: AGO Calendar's booking UI is a module inside
`ago-widget`, because a shop pastes one script tag.

## Junctions

`ago-root` exposes its siblings as `platform/`, `chat/`, `calendar/`, `widget/`, `console/`,
`deploy/` so a single session can work across repositories. They are Windows junctions with
**absolute** targets and are gitignored, so they must be recreated after moving or renaming the tree:

```powershell
$root = 'C:\git\ago\ago-root'
foreach ($l in 'platform','chat','calendar','widget','console','deploy') {
  $p = Join-Path $root $l
  if (Test-Path $p) { (Get-Item $p).Delete() }
  New-Item -ItemType Junction -Path $p -Target "C:\git\ago\ago-$l" | Out-Null
}
```

Junctions need no administrator rights, unlike symbolic links. Nothing else depends on absolute
paths: every documentation link between repositories is relative.

## Local NuGet feed

`C:\git\ago\.nuget-feed\` is a plain folder, sibling to the repositories and outside all of them, so
it is gitignored by construction rather than by rule and survives any single repository being deleted
or recloned. `ago-platform` runs `dotnet pack` into it; `ago-chat/nuget.config` and
`ago-calendar/nuget.config` both **map** `Ago.Platform.*` to it (`architecture/repositories.md`).
Create it once with `mkdir C:\git\ago\.nuget-feed` — nothing else needs to exist inside it
beforehand.

**A second file beside it is required, and a fresh machine will not build without it** (`17-11`).
`C:\git\ago\NuGet.Config` — same folder, also outside every repository, also untracked:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="ago-local" value="C:\git\ago\.nuget-feed" />
  </packageSources>
</configuration>
```

**Why it is not simply inside each repository's own `nuget.config`, where it used to be.** That is
where it was until `17-11`, named by this absolute Windows path — and Dependabot's Linux runner read
that string as *relative*, resolved it under its clone root, and failed with `NU1301`. A NuGet source
that is **configured and unreachable** is a hard restore error for every project touching the package;
one that is **simply absent** is not. So the committed files now name only `nuget.org` and map
`Ago.Platform.*` to source keys they do not declare, and each environment supplies its own: this file
for local development, a `registries:` block in `dependabot.yml` for Dependabot, and
`nuget.ci.config`/`nuget.docker.config` unchanged for CI and the image build.

The consequence for this runbook: **both** files are workspace state. Recreate both if the tree moves
or the machine is new, and note that a missing `NuGet.Config` fails at restore with "unable to find
package `Ago.Platform.Kernel`" rather than anything mentioning a missing config, which is not an
obvious message to trace back to this paragraph.

It holds every version ever packed, and NuGet resolves the *lowest* version satisfying a pin, so two
products pinning different platform versions coexist in it without interfering. What it does **not**
do is track the published GitHub Packages feed: a version CI published from `ago-platform`'s `main`
is only here if someone packed it locally, and `dotnet pack` only ever produces the version the local
checkout happens to be on. To build against a *newly published* version, either update that checkout
and repack, or pull the exact `.nupkg` files CI produced straight from its run —

```powershell
cd C:\git\ago
gh run download <run-id> --repo golyakoff/ago-platform -n nupkgs-<version> -D C:\git\ago\.nuget-feed
```

— which is what `20-00` did to build `ago-calendar` against 0.16.0 while the local `ago-platform`
checkout still sat on 0.15.0, and without a `read:packages` token (the workflow uploads that artifact
precisely so a reviewer with no package-read access can get the bytes).

## Moving or renaming the tree

1. Move or rename the folders, `.nuget-feed\` included.
2. Recreate the junctions with the snippet above.
3. Claude Code stores per-project memory and session history under a directory keyed by the working
   directory path (`~/.claude/projects/<escaped-path>/`). Renaming the project folder starts a new
   key, so copy the old `memory/` folder into the new one, or the accumulated notes silently vanish.
4. Nothing in `docs/` needs editing beyond this file — check with `grep -rn "C:" docs/` and fix
   anything that turns up outside `workspace.md`.

## Cloning fresh

Clone all eight repositories into one parent folder, then run the junction snippet. The build and test
commands live in `local-dev.md`; the cluster in `k8s-local.md`.

`ago-landing` (the marketing page, added 2026-08-24 to this runbook — it existed and was deployed
before it was written down anywhere) has no junction and is not needed for the build or test loop; it
is a single static page. Clone it when working on the marketing page, or on
`backlog/11-05-console-design-foundation.md`, which takes the console's design tokens from it.
