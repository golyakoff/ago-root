# Dependabot has never proposed a single NuGet update for either product repository

- **Stage**: 17
- **Status**: in review (2026-09-04), `ago-chat#160` + `ago-calendar#34` — the one Done-when that
  matters cannot be met by the change itself. See Outcome.
- **Found**: 2026-09-03, tracing why `17-10`'s transitive floors had drifted.

## The gap, counted rather than suspected

Every Dependabot pull request ever opened, per repository:

| repository | NuGet PRs | github-actions PRs |
|---|---|---|
| `ago-platform` | many (`Polly.Core`, `AWSSDK.S3`, `xunit`, `coverlet`, …) | yes |
| `ago-chat` | **0** | 3 |
| `ago-calendar` | **0** | 3 |

The three `.github/dependabot.yml` files declare the `nuget` ecosystem identically, so the
configuration was not the visible cause.

## Why

`nuget.config` in both product repositories declared the developer's file feed by a **Windows
absolute path**, after a `<clear/>`. Dependabot's own update-job log names the result:

```
error NU1301: The local source
  '/home/dependabot/dependabot-updater/repo/C:\git\ago\.nuget-feed' doesn't exist.
```

The Linux runner read that string as *relative* and appended it to the clone root. And the job
reported **success** — it simply proposed nothing, which is why the `github-actions` PRs kept
arriving and made Dependabot look alive.

## Why it is more than tidiness

`17-04` opened these files to *"keep this repository's dependency surfaces from going stale
silently"*. For the two repositories that actually ship to production, the NuGet half had never run
once.

The drift is already load-bearing: `17-10` exists because `0.19.0` raised floors Dependabot had
proposed and merged **in `ago-platform`** while the consumers sat still. That blocked a deploy.

CI still gates on `dotnet list package --vulnerable`, so an advisory would fail the build. What was
missing is anything that *proposes* the upgrade — the difference between finding out at review time
and finding out when the build goes red.

## The tension this had to resolve

There were already **three** answers to "where do packages come from": `nuget.config` (local),
`nuget.ci.config` (CI, GitHub Packages), `nuget.docker.config` (the image build). A fix that added a
fourth would be worse than the problem.

## Done when

- [ ] Dependabot opens NuGet PRs for both product repositories, **proven by an actual run**.
- [x] Local development, CI and the Docker image build all still restore — each considered, and the
      two that could not be run said so rather than being reported as passing.
- [x] The number of places that answer "where do packages come from" does not grow.

## Outcome

**The fix turns on a distinction that was measured, not assumed**: a source that is *configured and
unreachable* is a hard `NU1301` for every project touching the package; a source that is *simply not
configured* fails only that pattern (`NU1100`) and lets another mapped source serve it. That was
proven against the real feed with a cleared cache before anything was written.

So `nuget.config` declares `nuget.org` only, with no `<clear/>` so outside config can merge in, and
maps `Ago.Platform.*` to two source keys **it does not itself declare**. Local development supplies
one from a workspace-level `NuGet.Config` beside `.nuget-feed`; `dependabot.yml` supplies the other
through a `registries:` block pointing at the same GitHub Packages feed CI already uses, with a
secret that already existed in both repositories.

**The first Done-when is deliberately unticked.** It needs a live Dependabot run on GitHub, which is
the author's, and neither the change nor any amount of local verification can stand in for it.

**One residual risk, found rather than glossed**: dependabot-core has open issues about a checked-in
`NuGet.Config` combined with `registries:` and `packageSourceMapping`
(`dependabot/dependabot-core#8721`, `#10859`, `#11914`, `#3724`), including a report that adding a
private registry can stop the public one being consulted. The evidence here points the other way —
this repository's own log proves the checked-in file is read directly rather than replaced, and it
still names `nuget.org` explicitly — but the combination has not been observed succeeding end to end.

**A fresh machine now needs one extra one-time step**: create `NuGet.Config` beside `.nuget-feed`.
`runbooks/workspace.md` and `architecture/repositories.md` carry it as of this change.
