# Dependabot has never opened a NuGet pull request, in either product repository

- **Stage**: 17
- **Status**: ready
- **Depends on**: nothing. Carried out of `17-11`, which shipped the configuration and could not prove
  it works.
- **Decision**: none needed. This is a mechanism that does not run.

## What is actually true, counted on 2026-09-06

Every Dependabot pull request either product repository has ever received:

| Repository | PRs | Ecosystem | Dated |
|---|---|---|---|
| `ago-chat` | `#89`, `#90`, `#91` | `github-actions` | 2026-08-27 |
| `ago-calendar` | `#8`, `#9`, `#10` | `github-actions` | 2026-08-27 |

**Not one NuGet pull request, in either repository, ever** — and all six of those predate `17-11`'s
own change, which merged on 2026-09-03.

The `nuget` ecosystem *is* configured in both `.github/dependabot.yml` files. Something between that
configuration and a pull request does not run.

## Why this is not "nothing needed updating"

It might be. A whole solution with no NuGet update available across ten days is not impossible.

But `17-11`'s own Done-when demanded *"proven by an actual run"* precisely because that reading cannot
be told apart from a broken one from the outside — and **the ecosystem that is not producing pull
requests is the one carrying the actual dependency risk.** GitHub Actions bumps are the cheap half of
what `17-11` was for; .NET packages are the expensive half, and they are the silent one.

## The most likely cause, to start from rather than to assume

`ago-chat`'s NuGet block names a private registry (`ago-platform-github`, GitHub Packages, `adr/0018`)
and Dependabot needs a credential for it. A registry it cannot authenticate against is the ordinary
way this ecosystem fails **silently**: the update job errors on its own, no pull request appears, and
nothing in the repository's normal view says so.

**Look at the Dependabot job log before changing anything.** GitHub keeps the last run's outcome under
Insights → Dependency graph → Dependabot; an errored job says which registry and why. Fixing a guess
would be the second mistake.

## Scope

- Find out why no NuGet job produces a pull request, from the job's own record rather than by
  reasoning.
- Make it produce one, in both product repositories.
- **Something that notices this next time.** A configured-but-never-firing update job is invisible by
  construction, which is how it survived ten days and a closed ticket.

## Done when

- [ ] The reason no NuGet pull request has appeared is known and written down, from the job log.
- [ ] A NuGet pull request exists in both product repositories, or the job log shows nothing to
      update and that is recorded as the answer rather than assumed as one.
- [ ] A silently failing update job is visible somewhere a person will actually look.

## Out of scope

- `ago-platform`'s own Dependabot, which restores from public sources and has never had this problem.
- Acting on whatever the first NuGet PR proposes. That is ordinary work.
