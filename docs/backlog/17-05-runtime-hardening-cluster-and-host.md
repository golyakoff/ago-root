# Runtime hardening: what the pods are allowed to do, and what the host exposes

- **Stage**: 17
- **Status**: ready
- **Depends on**: nothing

## Goal

A compromised container cannot do whatever it likes, and the host does not expose more than it means
to. Today the manifests say nothing at all about either, so every default applies — and the defaults
were not chosen, they were inherited.

## What the audit found

Checked 2026-08-25 against `ago-deploy` and the Dockerfiles.

- **Not one `securityContext` exists in any manifest.** A repository-wide grep returns zero. So no
  `runAsNonRoot`, no `readOnlyRootFilesystem`, no dropped capabilities, no seccomp profile, no
  `allowPrivilegeEscalation: false` — on any workload, in either overlay.
- **No `NetworkPolicy` exists either.** Every pod can reach every other pod, so the three static-file
  nginx pods that serve the console, the widget demos and the marketing page can open a connection
  straight to Postgres, RabbitMQ, MinIO or the Keycloak admin port. Nothing about their job requires
  that, and they are the pods most exposed to the public internet.
- **Three images run as root by inheritance.** No Dockerfile sets `USER`. `ago-chat`'s
  `aspnet:10.0-noble-chiseled` base defaults to a non-root user, so those three hosts are fine —
  by inheritance rather than by statement, which a base-image change would silently reverse.
  `ago-console`, `ago-widget` and `ago-landing` all use `nginx:1.27-alpine-slim`, whose master process
  runs as root.
- **Keycloak's realm still has `sslRequired: "none"`.** Already named in `runbooks/public-deploy.md`'s
  "Known gaps" as a deferred hardening step; recorded here so it has an owner.
- **The host's SSH is properly hardened and documented** — non-root sudo user, key-only, root login and
  password authentication disabled, verified 2026-08-24. That part is done and this item should not
  redo it.
- **Everything else about the host is unverified.** Nothing in any repository states whether a firewall
  exists, or whether k3s's API server on `6443` and the kubelet on `10250` are reachable from the
  internet. k3s also stores Secrets unencrypted in its datastore by default, which nothing here has
  turned on or off deliberately.

## Context to read first

`docs/runbooks/public-deploy.md` in full, especially the SSH-hardening section (done, do not redo) and
"Known gaps, named plainly". `adr/0026` — one node, k3s, and the shape any change has to fit.
`ago-deploy/k8s/base/*.yaml` — every workload that needs a `securityContext`, and the volumes that
decide whether `readOnlyRootFilesystem` is even possible per container. `docs/backlog/8-00-minimal-
production-base-image.md` — the attack-surface reasoning behind the chiseled base, which this item
extends from "small image" to "constrained at runtime". `docs/architecture/edge.md` — what is
deliberately public, so a `NetworkPolicy` does not break the thing the deployment exists for.

## Scope

- **A `securityContext` on every workload**: `runAsNonRoot`, an explicit non-root UID where the image
  does not already provide one, `allowPrivilegeEscalation: false`, all capabilities dropped, and
  `readOnlyRootFilesystem` wherever the container tolerates it — nginx and Postgres both need writable
  paths, so this is per workload with `emptyDir` mounts where required, not a blanket setting.
- **Non-root nginx for the three static images.** The `nginxinc/nginx-unprivileged` image exists for
  exactly this and listens on 8080; alternatively adjust the config and set `USER`. Decide which and
  state why; either way the Service and route targets change with it.
- **State the chiseled base's non-root default explicitly** rather than relying on it, so a future base
  change cannot silently reintroduce root.
- **`NetworkPolicy`, default-deny between namespaces at minimum**, with explicit allowances for what
  genuinely talks to what. The static-file pods should not be able to open a database connection.
  Verify k3s's CNI enforces policies at all before writing them — a policy an unenforcing CNI ignores
  is worse than none, because it reads like protection.
- **Tighten Keycloak's `sslRequired`** to `external` and verify it against the real
  `--proxy-headers=xforwarded` configuration, which is the reason it was left alone the first time.
- **Establish the host's exposure**: whether a firewall exists, what is reachable on `6443` and
  `10250` from outside, and whether unattended security updates are on. Then decide and apply, and
  record the result — including "already closed by the provider" if that is the answer.
- **Decide on encryption at rest for Kubernetes Secrets** in k3s, and record the decision either way.
- Every change verified against the running deployment, not just applied: a pod that fails to start
  under a new `securityContext` is the normal outcome of this work and the reason it is done
  deliberately rather than by copying a template.

## Out of scope

- Multi-node topology, pod anti-affinity, or anything `adr/0026`'s one-node decision precludes.
- Moving Grafana off the public internet. Deliberate, recorded in `gateway.yaml`, gated by its own
  login and TLS — a decision to revisit with a reason, not a gap to close by default.
- Keycloak's `start-dev` versus production `start` — `15-01` owns that, alongside the persistent store
  it needs anyway.
- Secret *handling* and rotation — `17-03`.
- Dependency and image vulnerability scanning — `17-04`.

## Done when

- [ ] Every workload has an explicit `securityContext`, and every one still starts.
- [ ] No container runs as root, by statement rather than by inheritance.
- [ ] `NetworkPolicy` is in place and enforced — proven by a connection that used to work and now
      fails, from a pod that should never have had it.
- [ ] Keycloak's realm requires TLS externally, verified behind the real proxy configuration.
- [ ] The host's firewall status, `6443`/`10250` exposure and update behaviour are established,
      decided and recorded.
- [ ] The Secrets-at-rest decision is recorded.
- [ ] `public-deploy.md`'s "Known gaps" no longer lists what this item closed.

## Open questions

None. Every item is either a decision a session can defend from the constraints above, or a fact it
can go and establish.
