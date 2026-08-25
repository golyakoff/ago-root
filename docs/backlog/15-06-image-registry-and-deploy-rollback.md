# An image registry, a repeatable deploy, and a rollback that works

- **Stage**: 15
- **Status**: done (2026-08-25) — `adr/0047`. The follow-up named at the bottom of this file was
  taken up as `15-07` and is done (`adr/0051`); **the author step remains**
- **Depends on**: nothing hard, but sequenced after `15-02-backup-and-verified-restore.md` in practice —
  that item's restore drill is the first thing that needs a repeatable way to get images onto a fresh
  cluster, and doing it by hand once is exactly what this item removes

## Goal

A specific, identifiable version of every host can be deployed to the public deployment and rolled back
from a machine that is not the VPS. Today images are built on the VPS itself and imported straight into
k3s's containerd (`k3s ctr images import`), with `imagePullPolicy: Never` patched onto all three
`ago-chat-*` Deployments precisely because no registry holds those tags — an approach `adr/0026` chose
deliberately and `8-01` explicitly kept out of scope. It has three costs that are now real: the node
must have a toolchain and enough RAM to build, no earlier image survives anywhere to roll back to, and
a rebuilt cluster (`15-02`) starts with nothing to run.

## Context to read first

`adr/0026`'s "Image delivery" section — the current mechanism and its stated reasoning; this item
supersedes part of it and therefore needs its own ADR or an update section there, not a silent change.
`deploy/k8s/overlays/demo/kustomization.yaml` — the three `imagePullPolicy: Never` patches and the
inline comment explaining why Keycloak deliberately does not get one (a real bug caught live). That
comment's reasoning inverts once a registry exists, so it must be revisited, not deleted.
`docs/backlog/8-00-minimal-production-base-image.md` — what is actually being built. `docs/backlog/
8-04-container-publish-rid-trim.md` — the existing publish/trim behaviour any registry push inherits.
`.github/workflows/ci.yml` in `ago-chat` (`adr/0015`) — CI already builds and tests on every push; this
item decides whether it also pushes images, and `architecture/repositories.md`'s "no hosted registry
yet" note is the statement being changed.

## Scope

- Choose and record a registry (GHCR is the obvious candidate given the repositories are already on
  GitHub and public; state the alternative considered and the cost of each) — an ADR, or an update
  section on `adr/0026`.
- Images tagged by something identifying — commit SHA at minimum. `latest` alone cannot be rolled back
  to anything, which is the whole point of this item.
- Push from CI on the branch that deploys, not from a developer's laptop.
- The demo overlay pulls tagged images: `imagePullPolicy: Never` and its three patches go away, pull
  credentials (if the registry is private) come from the existing Secret mechanism.
- A deploy command/script that takes a tag and applies it, and a **rollback proven by performing one** —
  deploy a known-good tag, deploy a deliberately broken one, roll back, confirm service restored. A
  rollback path that has never been walked is not a rollback path.
- Database migrations relative to rollback: state plainly what rolling an image back does and does not
  do to schema already migrated forward, and what the operator is expected to do about it. This is the
  part of every rollback story that is usually silently wrong.
- Update the runbook, and `architecture/repositories.md`'s "no hosted registry" statement.

## Out of scope

- Continuous deployment on every push to `main` — this item makes deploys repeatable and reversible,
  not automatic. Auto-deploying a portfolio deployment that also now holds other people's accounts is a
  separate decision with a separate risk, and nothing asks for it.
- Blue/green, canary, or progressive delivery — one node (`adr/0026`); the rolling update Kubernetes
  already performs is what is available.
- Signing or SBOM generation for the images. Real practices, no requirement here, and each is its own
  item if it is ever wanted.
- Changing what is inside the image (`8-00`, `8-04` own that).

## Done when

- [x] Every `ago-chat-*` image is published to a real registry under an identifying tag, by CI.
      GHCR, full 40-character commit SHA, pushed by `ago-chat`'s CI on `main` after `build-test`
      passes. **Not yet observed running** — the job lands with this item's own merge, so its first
      execution is the merge itself.
- [x] The demo overlay pulls those tags; no `imagePullPolicy: Never` patch remains, and the Keycloak
      comment that reasoned about it is updated rather than orphaned. The three patches are gone and
      an `images:` block replaces them; the Keycloak comment is rewritten to keep the 2026-08-24 bug
      it records now that the rule it was an exception to no longer exists. Four `imagePullPolicy:
      Never` declarations **do** remain — the static bundles, see the follow-up below.
- [x] A deploy of a specific tag and a rollback to the previous one have both actually been performed
      on the live deployment. Deploy → deploy → **rollback** → deliberately-broken deploy →
      **rollback**, on the real node on 2026-08-25. `adr/0047`'s "What was actually performed"
      section has the sequence, the evidence and what it exposed.
- [x] The migration-versus-rollback interaction is written down. `adr/0047` §6, `redeploy.md`'s
      "Rolling back, and what it does not roll back", and both scripts print it.
- [x] `adr/0026` is updated on image delivery (an amendment note on the section, its Consequences and
      its Alternatives, not a silent edit), and `architecture/repositories.md` gained a "Container
      images" section replacing the "no hosted registry" position.

## What is not done

- ~~**The four static bundles.**~~ **Done by `15-07` (`adr/0051`), 2026-08-25.** All four are
  published by their own repositories' CI under the full commit SHA, each serves `/version.json`, the
  four `imagePullPolicy: Never` declarations are gone, and `deploy.sh`/`rollback.sh`/`smoke.sh` cover
  seven Deployments instead of three. `15-07` also had to answer the question these three hosts do
  not raise — a browser bundle is configured at build time, so a build *argument* is what made the
  image environment-specific; `adr/0051` removes the argument rather than encoding the environment
  in the tag. The original note is kept below, because it is the honest record of what shipping this
  item did and did not close:

  > `ago-console`, both `ago-demo-shop*` and `ago-landing` still build on
  the node under a mutable `:local` tag with `imagePullPolicy: Never`, and still cannot say which
  commit they carry. This is not an oversight — those three repositories all had open PRs while this
  item ran and could not be touched — but it is worth being blunt about: **the 2026-08-25 incident
  that motivated this whole item was a stale *console* bundle**, so the specific failure is still
  possible in the one place this item did not reach. Each needs three small things, none of them
  hard:
  > 1. `Dockerfile`: `ARG GIT_COMMIT`, the `org.opencontainers.image.{source,revision}` labels, and the
  >    commit written into the served bundle (a Vite `define`, or a `version.json` next to
  >    `index.html`) so the browser can report it the way `/healthz/version` does for the backend.
  > 2. `.github/workflows/ci.yml`: a `publish-images` job mirroring `ago-chat`'s — `docker login ghcr.io`
  >    with `GITHUB_TOKEN`, `packages: write`, tag `${{ github.sha }}` plus `main`, `main`-only.
  >    `ago-widget` builds twice, once per demo page (`DEMO_PAGE_DIR`).
  > 3. `ago-deploy`: `build-static-images.sh` gains `IMAGE_REPO`/`IMAGE_TAG`, the four
  >    `*-static.yaml` files lose `imagePullPolicy: Never`, and the overlay's `images:` block gains
  >    four entries.

  All three landed as written. The one thing the estimate missed: `ago-console`'s CI overrode every
  `VITE_*` with a localhost placeholder in its build step, which was harmless while it published
  nothing and would have shipped a localhost console under a truthful-looking SHA the moment it did.
- **The GHCR packages' visibility** — the one step a session cannot do. See below. `15-07` adds four
  more packages needing the same one-time check.

## Open questions

None left about the choice itself. One thing needs the author, once:

**After CI's first publish to `main`, check that the three container packages are public.** GitHub
may create a new container package as private even when it is published by a public repository's own
workflow. While one is private, the node's anonymous pull fails with `403 Forbidden` — the exact
symptom observed live during this item's rollback exercise, against packages that did not exist yet.
If they land private, flipping each to public in its package settings is the whole fix and nothing
else changes. Leaving them private works too, but costs a `read:packages` PAT held as an
`imagePullSecret` — a second credential `adr/0047` chose GHCR partly to avoid.
