# Repository topology

Each component is its own git repository. All of them live side by side in one parent folder
(`C:/git/ago/`), so every cross-repository reference in this documentation is relative and survives
the whole tree being moved:

```
ago/
  ago-root/       this repository — docs, ADRs, conventions, skills, backlog, load/
  ago-platform/   ago-chat/   ago-widget/   ago-console/   ago-deploy/
```

`ago-landing` was added later than the five above (it ships the marketing page routed at the apex
domain by `deploy/k8s/overlays/demo/landing-static.yaml`) and is recorded here as of 2026-08-24 — it
had been created, committed and deployed while this table still said five. It is load-bearing for more
than marketing now: `backlog/11-05-console-design-foundation.md` takes the console's colour and type
tokens from it rather than inventing a second visual identity.

`ago-root` additionally exposes the others as `platform/`, `chat/`, `widget/`, `console/`, `deploy/`
through Windows junctions, so one session can read and edit across repositories without leaving its
working directory. Those junctions are gitignored and never tracked here; they point at absolute
paths, so **if the tree is moved, recreate them** — nothing else in the documentation breaks.

| Repository | Contains | Produces | Depends on |
|---|---|---|---|
| `ago-platform` | `Ago.Platform.*` — Kernel, Abstractions, adapters (Postgres, RabbitMQ, Redis, S3), Realtime, Hosting, Resilience | **NuGet packages** | nothing of ours |
| `ago-chat` | `Ago.Chat.*` — Domain, Application, Contracts, Infrastructure, Module, **and the hosts** (Api, Worker, Webhooks) | Docker images | `Ago.Platform.*` packages |
| `ago-widget` | the embeddable script | a versioned CDN bundle | the public API contract |
| `ago-console` | operator console SPA | static bundle | the public API contract |
| `ago-deploy` | compose, Kustomize, seed | manifests | image tags, chart values |
| `ago-landing` | the public marketing page at the apex domain | a static page, served from the demo overlay | nothing |
| `ago-root` | docs, ADRs, conventions, skills, backlog, `load/` scenarios and reports | the rules everything else obeys | nothing |

## Why the platform is a package, not a folder

An arch test says the platform must not reference a product. A **package boundary** makes that
impossible rather than merely forbidden: `ago-platform` has no access to `Ago.Chat.*` source at all,
so the temptation cannot even be expressed. It also forces the platform to have a version, which
forces its API to be thought of as an API — the thing that distinguishes a platform from a folder
called `Common`.

The trade is real and is recorded in `adr/0012`: a change spanning platform and product costs two
merge requests, a version bump, and a package publish.

## Why the hosts live in the product repository

A host owned by the platform would have to reference `Ago.Chat.Module` in order to compose it, which
inverts the dependency direction at the repository level. So the hosts belong to the product: the platform ships
`Ago.Platform.Hosting` (module contract, health checks, telemetry, configuration binding) as a
library, and each product assembles its own deployables from it. AGO Calendar ships its own hosts
the same way (`Ago.Calendar.Api`/`Worker`, `roadmap.md` Stage 20), and the cluster runs both.

Names are therefore `Ago.Chat.Api`, `Ago.Chat.Worker`, `Ago.Chat.Webhooks`.

## Versioning and the development loop

- Platform packages use SemVer. A breaking change to a platform port is a major bump with a migration
  note in the platform's changelog — the same discipline demanded of integration events.
- Local development uses a **file-based NuGet feed**: `dotnet pack` into a local folder
  (`C:\git\ago\.nuget-feed\`, `runbooks/workspace.md`) that `nuget.config` in `ago-chat` lists as a
  source. No hosted feed is required to work offline.
- For a change that genuinely spans both repositories, `ago-chat` supports a **dev override**: a
  solution filter / `Directory.Build.props` switch that swaps the `PackageReference` for a
  `ProjectReference` into a sibling `../ago-platform` checkout. Use it while iterating; the branch
  that gets merged must build against the published package version, and CI builds only that way.
  Leaving a `ProjectReference` in a merged branch is a defect — it would hide exactly the API break
  the package boundary exists to catch.
- **CI restores from a real hosted feed**: `ago-platform`'s own CI publishes every package it packs
  on `main` to this repository's GitHub Packages NuGet feed, using its own `GITHUB_TOKEN` — no new
  secret to publish. `ago-chat`'s CI restores `Ago.Platform.*` from that feed, authenticated with a
  `read:packages`-scoped PAT held as a repository secret (`AGO_PLATFORM_PACKAGES_TOKEN`) — GitHub does
  not allow anonymous reads of NuGet packages even on a public repository. `adr/0018` (superseding
  `adr/0015`, which packed from source instead) records the trade.

## Cross-repository changes

Order of operations, always:

1. Platform branch: make the change, add tests, bump the version, publish the package.
2. Product branch: consume the new version, adapt, run the suite.
3. Deploy branch (if manifests change): update, and note the image tags.
4. Docs repository: update the architecture doc or ADR the change made wrong.

Each is a separate branch and merge request, each rebased onto its own `main`
(`conventions/git-workflow.md`). If step 1 turns out to be needed only by one product, that is a
signal the code was not platform code — put it back in the product and say so.

## Visibility

**Everything is public**, including `ago-root` with its `CLAUDE.md`, skills and backlog. Every
repository carries an MIT `LICENSE` from its first commit (`backlog/0-01-repositories-and-skeleton.md`).

That is a deliberate choice, not laziness. The AI-assisted workflow is itself part of what is being
demonstrated: rules that constrain an agent, skills that encode a procedure, ADRs that keep decisions
stable across sessions with no shared memory, and a backlog written so that a session with no context
can pick up an item and do it correctly. An engineer who can direct that work reproducibly is
demonstrating something most portfolios do not.

Consequences that must be respected from the first commit:

- **No secrets, ever** - not in code, not in manifests, not in a fixture, not in a commit that gets
  "fixed later". Git history is public and permanent. Local values live in gitignored
  `appsettings.Local.json` and `.env`; the repositories carry `.example` files only.
- **No personal or employer data**: no real customer names, no internal hostnames, no third-party
  endpoints, no anything from anyone's job.
- **Everything is written for a stranger.** Backlog items, working notes and skills are read as
  evidence of how the author thinks. That is the point - and it means a sloppy note is not private
  scruff, it is published work.
- Load reports are published with their misses intact. A report that only contains wins reads as
  marketing to exactly the audience being addressed.

## When a new repository is justified

Only when the thing **versions or deploys independently**. The widget qualifies because a shop cannot
be forced to update its script tag, so its release cadence is genuinely detached. A new adapter does
not qualify — it ships with the platform. Splitting `ago-platform` into per-adapter repositories is
available and currently rejected: it would multiply the version matrix with no independent consumer
to justify it.
