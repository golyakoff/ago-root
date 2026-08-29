---
name: dependabot-sweep
description: Work through a repository's open Dependabot PRs - infra image bumps and package/dependency bumps alike. Use when asked to "check Dependabot", "clean up the PRs", or when a repo's pull request list is dominated by dependabot/* branches. Covers both kinds this project actually has: CI-backed package bumps (npm, NuGet, GitHub Actions) and CI-less infra image bumps (Docker base images in k8s/docker-compose manifests) that need real local verification instead.
---

# Working through a Dependabot sweep

Two different kinds of PR show up under `dependabot/*`, and they need two different kinds of proof
before merging. Tell them apart first:

- **Package/dependency bumps** (npm, NuGet, GitHub Actions versions) live in a repo with a real CI
  workflow (`build-test` or equivalent) that runs `dotnet build`/`test` or `npm run` scripts against
  the bump. The CI result *is* the proof - do not re-derive it by hand.
- **Infra image bumps** (a `FROM`/`image:` line in a Dockerfile, `docker-compose.yml`, or a k8s
  manifest) usually have **no CI that exercises the new image at all** - `ago-deploy`'s own workflows
  never spin up Postgres/Keycloak/Grafana/etc. from its manifests. These need real local verification
  (pull the image, run it against the repo's own real config/data, check it does what the old one
  did) before merging - see "Verifying an infra image bump" below. Never merge one of these on git
  mergeability alone.

## One at a time, not in a batch

**Rebase, wait for green, merge, then move to the next PR.** Never fire `@dependabot rebase` at
several PRs in the same repository at once, even when they look independent. Two bumps from the same
repo rebase against the same `main`; merging the first moves `main` again and immediately re-stales
every other one you already rebased, which is wasted round-trips at best and, for two PRs touching
the same generated/lock file, a real conflict at worst. The sequence per PR:

1. Check current state: `gh pr view <n> --repo <owner>/<repo> --json mergeable,mergeStateStatus,statusCheckRollup`.
2. If `mergeStateStatus` is `BEHIND` or `DIRTY`/`CONFLICTING`, comment `@dependabot rebase` on that PR
   (`gh pr comment <n> --repo <owner>/<repo> --body "@dependabot rebase"`) and wait for the head SHA to
   change before doing anything else with that PR:
   ```
   until [ "$(gh api repos/<owner>/<repo>/pulls/<n> --jq '.head.sha')" != "<old-sha>" ]; do sleep 5; done
   ```
   Dependabot resolves real git conflicts on its own this way far more often than it looks like it
   should - a PR that shows `mergeable_state: dirty` (a genuine conflict, not just staleness) usually
   comes back `mergeable: true` after one rebase comment, because the conflict was almost always in a
   generated/lock file the bot regenerates cleanly, not in anything a human wrote by hand.
3. Wait for that PR's own CI run to finish on the new SHA:
   ```
   until [ "$(gh run list --repo <owner>/<repo> --branch <branch> --limit 1 --json status -q '.[0].status')" = "completed" ]; do sleep 8; done
   ```
4. Read the conclusion. `success` → merge (`gh pr merge <n> --repo <owner>/<repo> --rebase`).
   `failure` → see "A red check is not always the PR's fault" below before assuming it's a real
   regression.
5. Only then move to the next PR in the list.

## A red check is not always the PR's fault

Before treating a CI failure as evidence the bump is unsafe, check whether it is the bump's fault at
all:

- **Flaky test, not a regression.** A single failed test in an otherwise-green run - especially a
  timing-sensitive concurrency/fanout test with language like "timed out waiting for..." - is worth
  one retry before concluding anything: `gh run rerun <run-id> --repo <owner>/<repo> --failed`. If the
  retry is green, the original failure was noise. Confirmed real this way once: a .NET Test SDK major
  bump's only failure was a 10s cross-node fanout timeout that passed clean on rerun.
- **Pre-existing break, unrelated to the diff.** Check whether the *same* failure happens on `main`'s
  own latest run (`gh run list --repo <owner>/<repo> --branch main --limit 3`). If main is currently
  broken for an unrelated reason, every Dependabot PR against it will show the identical failure -
  fixing that is its own task, not a reason to distrust six unrelated version bumps.
- **Dependabot-triggered runs don't see regular repository secrets.** GitHub keeps a *separate*
  secrets store for Dependabot-triggered workflow runs ("Dependabot secrets", not "Actions secrets") -
  a security boundary, not a bug, so a compromised dependency bump can't exfiltrate a real secret via
  a modified workflow file. A restore/build step that needs a secret (a private NuGet/npm feed token,
  for instance) fails with that value empty on every Dependabot PR until the same secret is added
  *again*, separately, under Settings → Secrets and variables → **Dependabot** in that repository.
  Reading an existing Actions secret's value back is impossible (GitHub never returns one) - the fix
  is either pasting the same value the author already has stored elsewhere, or minting a fresh
  credential and updating both stores. This is real repository-settings work only the author can do;
  point them at the exact path rather than trying to work around it.

## `--admin` does not always mean bypass

`gh pr merge --admin` bypasses a **required status check under classic branch protection**. It does
**not** bypass a **repository ruleset** - a newer GitHub mechanism with its own separate bypass list
that `--admin` has no relationship to. `gh pr merge --admin` against a ruleset-protected repo with a
failing required check returns `GraphQL: Repository rule violations found` regardless of admin rights
on the CLI/API. If the author wants to force a merge past a check that is failing for a reason
unrelated to the PR's own diff, that has to happen from the GitHub web UI (where an owner may be on
the ruleset's own bypass list) - or, better, fix the actual cause (see above) and let the check turn
green for real.

## Verifying an infra image bump

For the CI-less kind - a Docker base image with no workflow that ever runs it - do not trust a clean
`git diff` or a passing lint job as proof. Pull the new image and exercise it against this repository's
own real configuration, not a synthetic smoke test:

- A service with **no state** (Prometheus, Alertmanager, Jaeger, node-exporter): run it with the
  repository's actual config/rule files mounted, confirm it starts and answers its own health
  endpoint. For Prometheus, `promtool check config`/`test rules` against the real scrape config and
  alert-rule test file catches a syntax break for free.
- A service with **real provisioned content** (Grafana): mount the actual dashboard JSON and
  datasource/provider YAML, confirm the API lists the same dashboards and datasources afterward, not
  just that the container stays up. Read the startup log for new-but-cosmetic noise (a background
  plugin auto-updater failing on a `readOnlyRootFilesystem` for a bundled plugin nothing here uses,
  for one real example) versus something that actually broke.
- A service with **real state carried in a volume** (Postgres, Keycloak's database): a major-version
  bump can be a genuinely different procedure, not a tag swap - see `docs/runbooks/backup-and-restore.md`
  and this session's own postgres-17-to-18 experience (`ago-deploy#93`) for what that actually
  involves: a fresh volume/PVC (an existing data directory in the old major's format will not start
  under the new one), a logical dump/restore rather than reusing the directory, and - the one part
  that fails silently rather than loudly - scaling every consumer to zero before touching the
  database, because a restore run against sessions the old app pods still hold open can under-restore
  without ever raising an error for it.

Windows/Git-Bash note for any of the above: `docker run -v <host>:<container>` frequently mangles the
*container-side* path through MSYS path conversion. Either set `MSYS_NO_PATHCONV=1` for that one
command, or prefix the container-side path with a doubled leading slash (`//container/path`) - the
convention MSYS itself recognizes as "leave this one alone."

## Report

State, per repository: how many PRs were merged, in what order, and for each - whether it needed a
rebase, whether CI was red at any point and why (flaky/pre-existing/secrets-scope/genuine), and
whether it needed hands-on infra verification rather than just a green check. Name anything left open
and why (a genuine regression, a repository-settings gap only the author can close, or a real conflict
Dependabot itself could not resolve).
