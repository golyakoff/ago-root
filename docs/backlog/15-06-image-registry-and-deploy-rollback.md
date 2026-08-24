# An image registry, a repeatable deploy, and a rollback that works

- **Stage**: 15
- **Status**: ready
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

- [ ] Every `ago-chat-*` image is published to a real registry under an identifying tag, by CI.
- [ ] The demo overlay pulls those tags; no `imagePullPolicy: Never` patch remains, and the Keycloak
      comment that reasoned about it is updated rather than orphaned.
- [ ] A deploy of a specific tag and a rollback to the previous one have both actually been performed
      on the live deployment.
- [ ] The migration-versus-rollback interaction is written down.
- [ ] `adr/0026` is updated or superseded on image delivery, and `architecture/repositories.md`'s
      "no hosted registry yet" note is corrected.

## Open questions

None. Registry choice is a decision a session can make and defend from the constraints above; if the
chosen registry turns out to cost money, that returns to the author the same way `15-02`'s destination
does.
