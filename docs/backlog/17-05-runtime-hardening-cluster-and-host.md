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
### The host, established live 2026-08-25

Checked directly on the VPS over SSH, read-only, plus an external port probe from a machine that is not
the VPS. These replace the "unverified" list this item originally carried.

- **No firewall of any kind.** `ufw` is `inactive`, and the provider does not filter either: an external
  probe found `22`, `80`, `443`, `6443`, `10250` and `32669` all reachable from the public internet.
  The `nftables` ruleset present is k3s's own service routing, not a policy.
- **`6443` (k3s API), `10250` (kubelet) and `32669` (k3s-server) are exposed but authenticated.**
  Anonymous requests get `401` from the first two — including `/version`, so not even the version leaks
  — and `32669` rejects the TLS handshake outright. So this is not an open cluster; it is three
  control-plane authentication surfaces facing the entire internet with nothing in front of them, which
  means any authentication-bypass advisory in k3s or the kubelet becomes immediately reachable by
  anyone, with no network layer to fall back on. That is also what makes `17-04`'s absence of any CVE
  tracking compound with this one rather than sit beside it.
- **An SSH hardening setting did not take effect, for a reason worth knowing.** Ubuntu's
  `sshd_config` opens with `Include /etc/ssh/sshd_config.d/*.conf`, and OpenSSH keeps the **first**
  value it obtains — so a cloud-image drop-in silently wins over an edit made further down the main
  file. `sshd -T` is the authoritative view and disagreed with the file. The current state is not
  exploitable, and this item deliberately does not spell out which setting or which account while it is
  unfixed (see the note at the end of this file); the work is to correct the drop-in and verify with
  `sshd -T` rather than by reading the file that lost.
- **`ago` holds `NOPASSWD:ALL`** — deliberate and documented (single-admin demo box), and worth keeping
  in view: the SSH key is the only thing between the internet and root.
- **Unattended security upgrades are on and working.** `unattended-upgrades` is enabled and active,
  `20auto-upgrades` sets both periodic keys, there are zero pending security updates and no reboot
  outstanding. This was on the original unverified list and turns out to need nothing.
- **k3s Secrets are unencrypted at rest**: `k3s secrets-encrypt status` reports
  `Disabled, no configuration file found`. Reading them requires host-level access, so this is
  defence-in-depth rather than a live hole — but every credential in `17-03`'s inventory sits in that
  datastore in plaintext.

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
- **Close the host's exposure** — established above, so this is now application rather than
  investigation. A host firewall (or the provider's, if it has one) that leaves `22`, `80` and `443`
  reachable and closes `6443`, `10250` and `32669` to everything except whatever genuinely needs them;
  if `kubectl` from the author's machine is one of those, say so and allow it by source address rather
  than leaving the port open to everyone.
- **Make every `sshd` setting the runbook claims actually hold**, by editing the drop-in that
  overrides them rather than the main file, and verifying with `sshd -T` rather than by reading a file
  that may have lost. Restart `ssh` and confirm a *new* session works before closing the current one —
  the same lockout-avoiding order the original hardening used. Consider `fail2ban` in the same pass, and
  note it becomes near-irrelevant once password authentication is genuinely off.
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
- [ ] `6443`, `10250` and `32669` are no longer reachable from an arbitrary internet address, proven
      by an external probe from a machine that is not the VPS.
- [ ] `sshd -T` reports `passwordauthentication no`, and a new SSH session was confirmed working before
      the change was considered done.
- [ ] The Secrets-at-rest decision is recorded.
- [ ] `public-deploy.md`'s "Known gaps" no longer lists what this item closed.

## Writing about this while it is unfixed

The general rule now lives in `architecture/repositories.md`'s "Everything is public" section, added
2026-08-25 after the author asked whether recording findings publicly increases the risk. Briefly, as
it applies here: the manifests are public, so what they already reveal is not protected by vaguer prose
and the only remedy is fixing it — but live host configuration that no manifest describes is worth
naming as a mechanism without its current value, which is why the `sshd` finding above reads the way it
does. The firewall entry in this file was found, fixed and rewritten as closed inside a day; that gap is
the actual control.

## Open questions

None. Every item is either a decision a session can defend from the constraints above, or a fact it
can go and establish.
