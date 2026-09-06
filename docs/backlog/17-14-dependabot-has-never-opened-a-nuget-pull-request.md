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

## The cause, established 2026-09-06 — and this section replaces a guess

**What this section said when the item was filed was wrong**, and it is left corrected rather than
quietly rewritten, because a confidently-wrong written-down cause is the thing this project keeps
catching. It guessed a missing registry credential. The evidence points elsewhere, and part of it
points against that guess.

**The job was running, and failing, and reporting success.** `17-11`'s own fix addressed exactly what
Dependabot's update-job log named: the checked-in `nuget.config` pointed at a **Windows path that does
not exist on Dependabot's Linux runner**, so the `nuget` ecosystem failed `NU1301` on every run,
reported success anyway, and proposed nothing. Nobody could tell — the `github-actions` ecosystem kept
opening ordinary pull requests on the same schedule and made the whole mechanism look alive.

**And no scheduled run has happened since that fix.** `dependabot.yml` runs the `nuget` ecosystem
**weekly, Monday 06:00 UTC**. `17-11` merged **Thursday 2026-09-03 21:58 UTC**. The only Monday since
is **2026-09-07**, which has not arrived. So *"no NuGet pull request exists"* is, as of filing, exactly
what a correctly-fixed configuration would also look like.

**Against the credential guess:** the Dependabot secret exists in both repositories, and its Actions
twin — the same PAT against the same feed — restored successfully in CI on 2026-09-06. That is not
proof the Dependabot copy is valid, since they are separate secrets, but it is evidence in the other
direction from what this section originally asserted.

**`17-11` was not closed carelessly, and the audit that carried this out said so too harshly.** Its
first Done-when was **deliberately** unticked with a written reason: it needs a live Dependabot run on
GitHub, which is the author's, and no amount of local verification can stand in for it. Carrying the
open thing out to its own number was still right — the queue should hold it under a number rather than
inside a closed item — but the record should say the box was left open on purpose, not overlooked.

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
