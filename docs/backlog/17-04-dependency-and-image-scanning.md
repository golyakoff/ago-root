# Knowing when a dependency or a base image becomes a known vulnerability

- **Stage**: 17
- **Status**: done (2026-08-27)
- **Depends on**: nothing hard. Sequenced usefully after `15-06-image-registry-and-deploy-rollback.md`
  for the image half — scanning an image is most natural where the image is built and pushed, and
  today images are built by hand on the VPS, which is the wrong place to run anything on a schedule.
  `15-06` landed 2026-08-25, before this item started, so the image-scanning half was built rather than
  deferred — see "Shipped in" below.

## Goal

When a package or a base image this project ships picks up a known vulnerability, something says so
without anyone going to look. Today nothing does, anywhere.

## What the audit found

Checked 2026-08-25 across all seven repositories. **Re-verified 2026-08-27, and out of date in two
ways, corrected rather than silently overwritten:** `ago-landing` had gained a real `ci.yml` in the two
days since the audit (it did not exist when this file was first written and does now), and two new
repositories exist that this audit predates entirely — `ago-calendar` (a NuGet/GitHub-Actions repository
with no Dockerfile at all yet) and `ago-calendar-console` (npm + Docker, but no `publish-images` job,
because nothing deploys AGO Calendar yet). The sweep this item actually ran covers all nine repositories
current as of 2026-08-27; the paragraph below is left as the historical record of what prompted the
item, not edited to pretend it was written against nine repositories from the start.

- **No Dependabot configuration exists in any repository.** No `.github/dependabot.yml` anywhere.
- **No scanning step exists in any CI workflow.** Four repositories have CI (`ago-platform`,
  `ago-chat`, `ago-widget`, `ago-console`), and every one of them restores, builds and tests without
  ever asking whether what it restored is known-vulnerable. `dotnet list package --vulnerable` and
  `npm audit` are one line each and neither is present.
- **Two repositories have no CI at all**: `ago-deploy` and `ago-landing`. `ago-landing` builds a
  container image, so an image ships from a repository with no automated anything.
- **Base images are pinned to a minor tag** — `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`,
  `nginx:1.27-alpine-slim`, `node:22-alpine`. Pinning is right, and it means a patched base only
  arrives when somebody rebuilds; nothing today prompts that rebuild.
- **One dependency surface is publicly reachable**: `grafana.reserve-me.ru` is deliberately exposed
  (`gateway.yaml` records the author's reasoning), gated by its own login and TLS. That is a defensible
  decision, and it does mean Grafana's own release stream is now something this project has a reason
  to track rather than a container that only its author can reach.

## Context to read first

`.github/workflows/ci.yml` in each of the four repositories that has one — the shape a scanning step
joins. `adr/0015` — why CI looks the way it does. `docs/backlog/8-00-minimal-production-base-image.md`
— why the chiseled base was chosen, including the attack-surface reasoning that this item is the
follow-through for. `docs/backlog/15-06-image-registry-and-deploy-rollback.md` — where images will be
built and pushed once it lands, which is where image scanning belongs.
`docs/architecture/repositories.md` — the seven repositories, so the sweep covers all of them and not
just the ones with code in a familiar language.

## Scope

- **Dependabot across every repository**, covering the ecosystems each actually uses: NuGet, npm,
  Docker base images, and GitHub Actions themselves (an unpinned or stale action is a supply-chain
  surface as real as a package). Include `ago-deploy` and `ago-landing`, which have no CI to piggyback
  on.
- **A vulnerability check in CI** for the repositories that have it: `dotnet list package --vulnerable
  --include-transitive` for the .NET solutions, `npm audit` for the two frontends. Decide and state
  whether a finding fails the build or only reports — a check that always fails the build on a
  transitive advisory nobody can act on trains people to ignore it, and a check that never fails is
  decoration. Pick a severity threshold and say why.
- **Image scanning**, once there is a registry to scan into (`15-06`). Trivy or equivalent, on push,
  with the same fail-versus-report decision made deliberately.
- **Minimal CI for `ago-landing`** — enough to build the image and scan it. `ago-deploy` needs no
  build, but it can still carry Dependabot for its base-image references and any actions it gains.
- **Decide what happens on a finding.** Who looks, how quickly, and where it is recorded. A scanner
  with no route to a decision produces noise and nothing else; this is the half that usually gets
  skipped.
- An SBOM is *not* required here — say so explicitly, with the reason, rather than leaving it as an
  unstated omission.

## Out of scope

- Static analysis or secret scanning of source. Different tools, different failure modes, and GitHub's
  own secret scanning already covers public repositories by default — worth confirming is on, not
  worth rebuilding.
- Pinning base images by digest. A real hardening step with a real maintenance cost, and it interacts
  directly with automated base-image updates; it belongs in whichever direction this item's Dependabot
  configuration ends up going, as a follow-up with that experience in hand.
- Penetration testing or anything resembling it.
- The runtime posture of what is scanned — `17-05`.

## Done when

- [x] Every repository has a Dependabot configuration covering the ecosystems it uses. All nine —
      `ago-root` needed none, since it ships no package manifest, Dockerfile or workflow of its own.
- [x] Every repository with CI runs a dependency vulnerability check, with a stated threshold and a
      stated fail-or-report behaviour. Critical/High fails, Moderate/Low reports — see "Shipped in".
- [x] `ago-landing` has CI that builds and scans its image. It already had `ci.yml` (landed since the
      2026-08-25 audit); this item added the scan.
- [x] Image scanning runs where images are pushed, now that `15-06` gave them somewhere to be pushed —
      `15-06` landed 2026-08-25, so this was built rather than deferred. See "Shipped in".
- [x] The response path — who looks at a finding and where the decision is recorded — is written down.
      `docs/runbooks/vulnerability-response.md`.
- [x] The SBOM decision is recorded, whichever way it goes. Same file, "Why there is no SBOM".

## Open questions

None. Every choice here is one a session can make and defend, provided it states the threshold and the
fail-or-report behaviour rather than leaving them to a default nobody chose.

## Shipped in

**Nine repositories, not seven** — the audit above predates `ago-calendar` and `ago-calendar-console`,
and `ago-landing` gained a real `ci.yml` between the audit and this item starting. All nine were swept
fresh on 2026-08-27 rather than trusting the item's own stale text; `ago-business` (private) is out of
scope by the same reasoning `repositories.md` gives for every other split between what is and is not a
public technical repository.

**Dependabot** (`.github/dependabot.yml` in eight of the nine — `ago-root` needs none): NuGet
(`ago-platform`, `ago-chat`, `ago-calendar`), npm (`ago-widget`, `ago-console`, `ago-calendar-console`
— `ago-landing` has no `package.json` at all, confirmed rather than assumed from the name), Docker
(every repository with a `Dockerfile` — all but `ago-platform`, `ago-calendar` and `ago-root`), and
`github-actions` (every repository with a `.github/workflows/` directory). `ago-deploy` — no CI, so no
`github-actions` entry — gets `docker` entries for `k8s/base` and `k8s/overlays/{demo,local}` (Dependabot
reads Kubernetes manifest `image:` references this way, directory by directory, confirmed against
GitHub's own documentation while writing this) and `docker-compose` entries for `docker/` and
`k8s/backup/`, with this project's own commit-SHA-tagged images explicitly `ignore`d in the two
directories that carry them — their tags are placeholders kustomize overrides at apply time, not a
version Dependabot could sensibly propose bumping. One weekly schedule (Monday 06:00 UTC) everywhere,
matching `ago-chat/credential-expiry.yml`'s own cadence rather than inventing a second one.

**Dependency vulnerability check**, in every repository that has CI: `dotnet list package --vulnerable
--include-transitive --format json` for the four .NET repositories, `npm audit --audit-level=high` for
the four npm ones. **Threshold: Critical/High fails the build, Moderate/Low is reported (job log + step
summary) but does not.** `dotnet list package --vulnerable` always exits 0 regardless of findings
(verified) and its human-readable text is locale-dependent (verified — it printed in Russian on a
non-en-US machine while this was being written), so the .NET side parses `--format json` with `jq`
rather than trusting either; `npm audit --audit-level=high` does the same job in one flag, verified
against a real low-severity finding in `ago-widget` (`esbuild`, GHSA-g7r4-m6w7-qqqr) that printed in
full but did not fail the build.

**Image scanning was not deferred — `15-06` was already done (2026-08-25) when this item started**, so
Trivy scanning was built rather than left as a stated gap. Runs in `ago-chat`, `ago-widget`,
`ago-console` and `ago-landing`'s `publish-images` jobs, **before the push step, not after** — the more
obvious place to add a scan is at the end of an existing build-then-push job, but that lets a
Critical/High image sit in GHCR, however briefly, before anyone reacts; every job was restructured into
build → scan → push so nothing this check would fail ever reaches the registry. Same threshold as the
dependency check. `--scanners vuln` only — this item's own scope excludes secret scanning of source, and
Trivy's filesystem secret scanner is close enough to that job to stay out of it here.

Trivy is invoked as a pinned-by-digest `docker run`, not through `aquasecurity/trivy-action` or a
floating tag: both the Action's git tags (`0.0.1`-`0.34.2`) and the `aquasec/trivy` Docker Hub image
itself (`0.69.4`-`0.69.6`) were compromised in March 2026 — malicious code reached CI runs through
imposter commits and malicious image builds respectively — which is exactly the "unpinned or stale
Action is a supply-chain surface" risk this item's own scope names, demonstrated rather than
hypothetical. `aquasec/trivy@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969`
(tag `0.74.0`) is what ships, pulled and verified locally while writing this change. Dependabot's own
`docker`/`github-actions` entries will not bump a `docker run` digest embedded in a shell script the way
they would a `FROM` line or a `uses:` tag — that digest goes stale silently and needs updating by hand,
a real limitation of choosing the CLI form over the Action wrapper, stated rather than hidden.

**A real, live finding, left as found rather than fixed here** (this item adds scanning, it does not fix
what scanning turns up): `nginx:1.27-alpine-slim` — the base image `ago-widget`, `ago-console` and
`ago-landing` all share — carries 2 Critical and 15 High vulnerabilities as of 2026-08-27 (measured with
the same pinned Trivy invocation this item ships). **The very first run of the new `publish-images` job
in those three repositories will fail** until the base tag is bumped past `1.27`. This is exactly the
scenario `8-00`'s own follow-up note predicted ("pinning ... means a patched base only arrives when
somebody rebuilds; nothing today prompts that rebuild") and exactly what this item exists to surface —
correct behaviour, not noise, and deliberately not fixed in this change: bumping a base-image tag is
dependency content, out of this item's own scope. `ago-chat`'s own final-stage base,
`mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`, scanned clean (0 Critical/High) at the same time,
which is `8-00`'s attack-surface argument for Chiseled showing up as a real number rather than a stated
preference.

**Response path and SBOM decision**: `docs/runbooks/vulnerability-response.md` (new). Solo-maintainer
reality stated plainly — a red required check is the only mechanism that reliably forces a look;
Moderate/Low findings in a green log are the honest weak point, mitigated by Dependabot's own
version-update PRs not being severity-gated (most of them eventually surface as an ordinary PR
regardless). No SBOM: what one would add on top of Dependabot + the vulnerability/image scans already
shipped here is third-party-verifiable provenance and a machine-readable format for a downstream
consumer's own tooling — neither applies yet, since nothing downstream depends on these artifacts the
way a real supply-chain policy would require.

**A live gap found and left open on purpose**: GitHub's own Dependabot *alerts* feature (the
dependency-graph security scan, distinct from the `dependabot.yml` version-updates this item adds) is
off on all nine repositories — confirmed via `gh api repos/<owner>/<repo> --jq .security_and_analysis`
and a 404 from `GET .../vulnerability-alerts` on every one. Flipping a repository security setting on
nine repositories without being asked is outside what a session should do unilaterally; the author's
call, named explicitly in the runbook rather than silently skipped.

**Unverified**: a real GitHub Actions run of any of this — nothing here can trigger one from a local
session, so the jq filters were checked against a real, live "no vulnerabilities" JSON payload from
`ago-platform` and a hand-built payload matching the documented schema with a Critical/High/Moderate/Low
mix (both produced the expected counts against a real `jq` binary run via Docker), and the Trivy
invocation was run for real against locally-built images — but the workflow YAML itself has only been
parsed for syntax (`python -c "import yaml"`, every file in every repository, all valid) and reasoned
through by hand, not executed by GitHub Actions.
