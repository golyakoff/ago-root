# Runtime hardening: what the pods are allowed to do, and what the host exposes

- **Stage**: 17
- **Status**: done (2026-08-26) — with two named carve-outs, below
- **Depends on**: nothing
- **Decision record**: `adr/0054`

## Goal

A compromised container cannot do whatever it likes, and the host does not expose more than it means
to. Today the manifests say nothing at all about either, so every default applies — and the defaults
were not chosen, they were inherited.

## What the audit found

Checked 2026-08-25 against `ago-deploy` and the Dockerfiles.

- **Not one `securityContext` exists in any manifest.** A repository-wide grep returns zero. So no
  `runAsNonRoot`, no `readOnlyRootFilesystem`, no dropped capabilities, no seccomp profile, no
  `allowPrivilegeEscalation: false` — on any workload, in either overlay.
  > **Slightly out of date by the time it was worked on** (2026-08-26): `15-03` and `15-05` had since
  > added blocks to `alertmanager.yaml` and `node-exporter.yaml`, both citing this item's direction.
  > Two workloads out of seventeen, and both were missing `seccompProfile`. The finding stands.
- **No `NetworkPolicy` exists either.** Every pod can reach every other pod, so the three static-file
  nginx pods that serve the console, the widget demos and the marketing page can open a connection
  straight to Postgres, RabbitMQ, MinIO or the Keycloak admin port. Nothing about their job requires
  that, and they are the pods most exposed to the public internet.
  > **Confirmed live before anything was changed**, from `ago-console`: `nc -z postgres 5432`,
  > `nc -z rabbitmq 5672` and an HTTP GET to `minio:9000` all succeeded.
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

- ~~**No firewall of any kind.**~~ **Closed 2026-08-25**, before this item was worked on — `ufw` runs
  with `deny incoming`. Re-verified externally 2026-08-26, see "What was done".
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
  file. `sshd -T` is the authoritative view and disagreed with the file. **Fixed 2026-08-26**, see
  below.
- **`ago` holds `NOPASSWD:ALL`** — deliberate and documented (single-admin demo box), and worth keeping
  in view: the SSH key is the only thing between the internet and root.
- **Unattended security upgrades are on and working.** Re-checked 2026-08-26: still enabled, still
  zero pending. This was on the original unverified list and turns out to need nothing.
- **k3s Secrets are unencrypted at rest**: `k3s secrets-encrypt status` reports
  `Disabled, no configuration file found`. Reading them requires host-level access, so this is
  defence-in-depth rather than a live hole. **Decision taken and recorded** — `adr/0054` §5 declines
  it, and says what would reverse that.

## Context to read first

`docs/runbooks/public-deploy.md` in full, especially the SSH-hardening section and "Known gaps, named
plainly". `adr/0026` — one node, k3s, and the shape any change has to fit. `adr/0054` — what this item
decided and why. `ago-deploy/k8s/base/*.yaml` — every workload's `securityContext` and the volumes that
decide whether `readOnlyRootFilesystem` is even possible per container.
`docs/backlog/8-00-minimal-production-base-image.md` — the attack-surface reasoning behind the chiseled
base, which this item extends from "small image" to "constrained at runtime".
`docs/architecture/edge.md` — what is deliberately public, so a `NetworkPolicy` does not break the
thing the deployment exists for.

## What was done, 2026-08-26 — verified live, workload by workload

Everything below was applied to the running public deployment with a targeted `kubectl patch` per
workload — never `kubectl apply -k`, which would also have reset image tags and picked up the node
checkout's uncommitted edits (`public-deploy.md`'s own "Known gaps" describes that divergence). After
every change: pods `Running`, then the next workload. **18 pods Running throughout; `smoke.sh` on the
node reports 19 passed, 2 failed — the same two `15-07` already records** (`healthz/version` and the
widget bundle's self-reported commit), neither touched by this item.

The branch was then rendered on the node and compared field by field against the live cluster: every
Deployment's and DaemonSet's pod-level `securityContext`, every container's `securityContext` and
`lifecycle`, and every init container's `securityContext` **match exactly**. The repository is again
the truth about what is running.

### `securityContext`

Universal: `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`,
`seccompProfile: RuntimeDefault`. Per workload, the interesting part — the table is in `adr/0054` §1;
what it cost is here.

**Which images already complied, established from the node's own process table rather than assumed:**

| | Actual uid before this item | |
|---|---|---|
| `ago-chat-api`/`-worker`/`-webhooks` | 1654 | complied, by inheritance only |
| `keycloak` | 1000 (gid 0) | complied |
| `grafana` | 472 | complied |
| `jaeger` | 10001 | complied |
| `prometheus`, `alertmanager`, `node-exporter` | 65534 | complied |
| `postgres` | 70 | complied *for the server*; the entrypoint is root and drops |
| `redis` | 999 | same shape |
| `rabbitmq` | 999 | same shape |
| **`minio`** | **0** | **did not comply — root for the life of the process** |
| four nginx sites | **0** master, workers `nginx` | did not comply |

**What it took, per workload that fought back:**

- **MinIO — the one that failed.** `runAsUser: 1000` plus `fsGroup: 1000` produced a
  `CrashLoopBackOff` with `Unable to write to the backend`. `fsGroup` had done its job — every path
  was group-1000 and group-writable — and MinIO still refused, because it checks for **owner** write
  and does not accept group write in its place. A `local-path` PVC is created by the provisioner as
  root, so a rebuilt cluster starts in the same state and no manifest field fixes it. Resolved with a
  root init container holding `CHOWN`, `FOWNER`, `DAC_OVERRIDE` and one idempotent `chown -R`. **This
  was the only workload taken down by this item, and it was restored inside the same step.**
- **Postgres — the field that must not be set.** `fsGroup` would make `PGDATA` `0770`, and Postgres
  refuses any data directory that is not `0700`/`0750`. So no `fsGroup`, and therefore no
  `readOnlyRootFilesystem` either (its socket directory would need one). Named in the manifest.
- **Redis — the guess that would have broken it.** The image's `redis` account is uid 999 **gid
  1000**. Read with `id redis` in the running container; assuming 999:999 would have been wrong.
- **RabbitMQ — no read-only root.** Its entrypoint writes `/etc/rabbitmq/conf.d/10-defaults.conf` on
  every boot, and mounting an `emptyDir` over that directory would take `enabled_plugins` — and with
  it `15-03`'s `rabbitmq_prometheus` scrape — along with it.
- **Grafana — a cost, not a break.** `fsGroup` widens `grafana.db` from `0640` to `0660` and Grafana
  logs "SQLite database file has broader permissions than it should" on every start from now on.
- **Keycloak — no read-only root, and the reason belongs to another item.** `start-dev` re-runs
  Quarkus's build-time augmentation into `/opt/keycloak` on every boot. Read-only needs
  `start --optimized`, which needs a derived image — `15-01`/`adr/0036`'s deferred work. Its init
  container did get `readOnlyRootFilesystem`; all it runs is `psql`.

### A pre-existing bug found on the way, and fixed

**The `preStop` hook on all three `Ago.Chat.*` hosts had never once run.** It was
`exec: ["sh", "-c", "sleep 15"]`, and the chiseled base image contains no shell and no coreutils —
`kubectl exec ... -- true` in a running pod answers `executable file not found in $PATH`. Every
termination since the hook was written logged a `FailedPreStopHook` event and went straight to
`SIGTERM`. A failing `preStop` hook does not fail a rollout, which is exactly why it stayed invisible:
`3-06`'s verification watched for lost messages and readiness flapping and saw neither, because a
single replica draining slightly early loses nothing a client notices.

Fixed with Kubernetes' own `preStop.sleep` action (GA since 1.30), which the kubelet executes and
which therefore needs nothing from the image. Same durations, same reasoning. Proved by rollout: a pod
carrying the new form produces no `FailedPreStopHook` event where the old form produced one every
time. `architecture/edge.md`'s rolling-deploy section is corrected in the same change — it described
this hook as the mechanism that makes a rolling deploy clean, and on these three hosts it was not.

### `NetworkPolicy` — and the proof it bites

**Enforcement checked before a policy was written.** k3s runs kube-router's policy controller unless
`--disable-network-policy` is passed; this node's unit passes only `--disable traefik`, and
`iptables-save` carries 194 `KUBE-ROUTER-*` rules.

**The demonstration, same pod, same commands, before and after `static-sites-egress`:**

| From `ago-console` | Before | After |
|---|---|---|
| `nc -z postgres 5432` | exit 0 | exit 1 |
| `nc -z rabbitmq 5672` | exit 0 | exit 1 |
| `nc -z minio 9000` | exit 0 | exit 1 |
| `nslookup postgres...` | resolves | **still resolves** |
| serving `/version.json` | 200 | 200 |

DNS still resolving is the part that makes it evidence rather than an outage: the name resolves and
the TCP connect is what fails, so the drop is the policy and not a broken pod.

A second demonstration, from the same session and arguably the more vivid one, belongs to
`readOnlyRootFilesystem`: **before**, `ago-console` could write a file into `/usr/share/nginx/html`
and the pod served it (verified, then removed); **after**, the same command answers
`Read-only file system` and the site still serves.

**And the trap it found.** `minio-ingress` written the obvious way — pod selectors plus
`ipBlock: 10.42.0.1/32`, the flannel bridge — **breaks the nightly backup**, established by A/B on the
live node: `backup.sh`'s `minio/mc` step fails with the policy, succeeds with it deleted, and succeeds
again once `172.17.0.0/16` is allowed. `tcpdump` on `cni0` shows those packets arriving *from*
`10.42.0.1`, so a packet capture endorses the version that does not work: the policy is evaluated on
the **pre-masquerade** source, which is still the Docker bridge. The failure mode is the bad one — the
backup stops at 02:30 UTC with nothing else visibly wrong.

### Keycloak `sslRequired`

Raised from `none` to `external` on the live realm (via the Admin API, since `15-01`/`adr/0036` means
a changed import file does not reach an existing realm) and in
`ago-deploy/k8s/base/keycloak-realm-import.json` so a fresh cluster starts there.

Verified behind the real `--proxy-headers=xforwarded` configuration — NGF does set
`X-Forwarded-Proto` — with the hosted login page, the direct-grant token endpoint and
`Ago.Chat.Api`'s acceptance of the resulting JWT all returning `200` afterwards.

**And verified to refuse nothing today, which is the honest result.** `--hostname=https://auth...`
fixes the frontend URL scheme, so Keycloak's SSL check sees a secure request regardless of the
forwarded proto: replaying the login request with `X-Forwarded-Proto: http` and a public
`X-Forwarded-For` returns a byte-identical page. What forces TLS here is the Gateway's `301`. The
setting is a guard against a future misconfiguration, not the closing of a present hole —
`adr/0054` §4.

### The host

- **`sshd`.** A new drop-in `/etc/ssh/sshd_config.d/01-ago-hardening.conf` — the `01` prefix *is* the
  mechanism, since includes are read in lexical order and OpenSSH keeps the first value, so it must
  sort **before** `50-cloud-init.conf`, not after. Sets `PasswordAuthentication no`,
  `KbdInteractiveAuthentication no`, `PermitRootLogin no`, `PermitEmptyPasswords no`,
  `AuthenticationMethods publickey`. Validated with `sshd -t`, applied with `reload` rather than
  `restart`, and guarded by a dead-man switch that would have removed the file and reloaded after five
  minutes had the confirming session never arrived.
  `sshd -T` now reports `passwordauthentication no` and `authenticationmethods publickey`; a **new**
  session was confirmed working before the switch was disarmed; and a password-only attempt is now
  refused with `Permission denied (publickey)` — the message the runbook's own correction predicted,
  where it used to read `(publickey,password)`.
- **Firewall, re-verified externally** from a machine that is not the VPS, by content rather than by
  connectivity — the method `public-deploy.md` insists on, because a plain TCP probe on this path
  answers every SYN. `https://<host>:6443/version` and `:10250/healthz` return **no body at all**,
  where before the firewall they returned a real Kubernetes `401` JSON. `:32669` likewise. `:443`
  answers normally. `ufw` on the node: `deny (incoming)`, allowing only `22`, `80`, `443`, `25` and
  the k3s pod/service CIDRs plus `cni0`.
- **Secrets at rest: declined**, `adr/0054` §5.
- **`fail2ban`: declined**, `adr/0054` §6 — there is no password to brute-force any more.

## Deliberately not done, and why

- **The four nginx images stay root.** Making them non-root is a change to `ago-console`,
  `ago-widget` and `ago-landing`, not to `ago-deploy`, and it moves three port numbers together. Doing
  it blind from a deployment repository is how a public demo goes down for a reason nobody can bisect.
  The exact per-repository change is specified below.
- **No namespace-wide default-deny `NetworkPolicy`** — `adr/0054` §3. NGF's data plane and
  cert-manager's on-demand solver pods are the two whose traffic no committed file can describe, and
  being wrong about either shows up at certificate-renewal time.
- **No ingress policy on Keycloak, Grafana, Prometheus, Jaeger or Alertmanager.** Each is
  in-cluster-only already; each would need an allowance less certain than the four that were written.
- **The NGF data-plane pod has no `securityContext` from this repository.** It is generated by the
  Gateway API controller from the `Gateway` resource, not by a manifest here.
- **`readOnlyRootFilesystem` on Postgres, RabbitMQ and Keycloak** — three named blockers, above.

## What other repositories need (specified, not done)

Each of these is one small change plus a port move, and each needs its own verification against the
live deployment because the Service and route change with it.

**`ago-console`, `ago-widget` (both demo shop images), `ago-landing`** — identical shape in all three:

1. `Dockerfile`: change the runtime stage's base from `nginx:1.27-alpine-slim` to
   `nginxinc/nginx-unprivileged:1.27-alpine-slim`. That image runs as uid 101 and its default
   `default.conf` listens on **8080**, not 80.
2. The `default.conf` each repository copies in must change `listen 80;` to `listen 8080;`. Nothing
   else in it changes — `try_files $uri /index.html;` and the docroot are unaffected.
3. Nothing about `/version.json` (`15-07`/`adr/0051`) changes: it is a file in the docroot, and the
   commit still reaches it the same way. The CI publish job is untouched.

**Then, in `ago-deploy` (a separate follow-up change, not this one):**

4. `overlays/demo/{console,demo-shop1,demo-shop2,landing}-static.yaml`: `containerPort: 80` → `8080`,
   both probes' `port: 80` → `8080`, the Service's `targetPort: 80` → `8080` (the Service `port: 80`
   stays, so `gateway.yaml`'s `backendRefs` need no edit at all), and the container `securityContext`
   loses its `capabilities.add` list entirely and gains `runAsNonRoot: true` / `runAsUser: 101` at pod
   level. `readOnlyRootFilesystem` and the three `emptyDir` mounts stay exactly as they are —
   `nginx-unprivileged` writes to the same paths.

Nothing in `ago-chat`, `ago-platform` or `ago-calendar` is required by this item.

## Out of scope

- Multi-node topology, pod anti-affinity, or anything `adr/0026`'s one-node decision precludes.
- Moving Grafana off the public internet. Already done for a different reason and recorded in
  `gateway.yaml`.
- Keycloak's `start-dev` versus production `start` — `15-01` owns that, and it is now also the
  blocker for Keycloak's `readOnlyRootFilesystem`.
- Secret *handling* and rotation — `17-03`.
- Dependency and image vulnerability scanning — `17-04`.

## Done when

- [x] Every workload has an explicit `securityContext`, and every one still starts. 17 workloads,
      applied one at a time, 18 pods `Running`.
- [x] No container runs as root **by inheritance**. One still runs as root **by statement** — the four
      nginx sites — with the reason, the cost and the exact fix written down. `adr/0054` §2.
- [x] `NetworkPolicy` is in place and enforced — proven by three connections that used to work and now
      fail, from a pod that should never have had them, with DNS still resolving to show the drop is
      the policy.
- [x] Keycloak's realm requires TLS externally, verified behind the real proxy configuration — and
      verified to be inert today, which is recorded rather than glossed.
- [x] `6443`, `10250` and `32669` are no longer reachable from an arbitrary internet address, proven
      by an external content probe from a machine that is not the VPS.
- [x] `sshd -T` reports `passwordauthentication no`, and a new SSH session was confirmed working
      before the change was considered done.
- [x] The Secrets-at-rest decision is recorded — `adr/0054` §5.
- [x] `public-deploy.md`'s "Known gaps" no longer lists what this item closed.

## Writing about this while it is unfixed

The general rule now lives in `architecture/repositories.md`'s "Everything is public" section, added
2026-08-25 after the author asked whether recording findings publicly increases the risk. Briefly, as
it applies here: the manifests are public, so what they already reveal is not protected by vaguer prose
and the only remedy is fixing it — but live host configuration that no manifest describes is worth
naming as a mechanism without its current value, which is why the `sshd` finding above read the way it
did while it was open. Now that it is closed, the mechanism is written out in full, because a closed
gap explained is a better artefact than an open one hinted at.

## Open questions

None.
