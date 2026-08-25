# Knowing when a dependency or a base image becomes a known vulnerability

- **Stage**: 17
- **Status**: ready
- **Depends on**: nothing hard. Sequenced usefully after `15-06-image-registry-and-deploy-rollback.md`
  for the image half — scanning an image is most natural where the image is built and pushed, and
  today images are built by hand on the VPS, which is the wrong place to run anything on a schedule.

## Goal

When a package or a base image this project ships picks up a known vulnerability, something says so
without anyone going to look. Today nothing does, anywhere.

## What the audit found

Checked 2026-08-25 across all seven repositories.

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

- [ ] Every repository has a Dependabot configuration covering the ecosystems it uses.
- [ ] Every repository with CI runs a dependency vulnerability check, with a stated threshold and a
      stated fail-or-report behaviour.
- [ ] `ago-landing` has CI that builds and scans its image.
- [ ] Image scanning runs where images are pushed, once `15-06` gives them somewhere to be pushed.
- [ ] The response path — who looks at a finding and where the decision is recorded — is written down.
- [ ] The SBOM decision is recorded, whichever way it goes.

## Open questions

None. Every choice here is one a session can make and defend, provided it states the threshold and the
fail-or-report behaviour rather than leaving them to a default nobody chose.
