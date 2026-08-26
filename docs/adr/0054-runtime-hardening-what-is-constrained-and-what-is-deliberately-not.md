# ADR-0054: Runtime hardening — what each workload is constrained to, and what is deliberately not

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 17

## Context

`backlog/17-05` found that not one `securityContext` and not one `NetworkPolicy` existed anywhere in
`ago-deploy` — so **every default applied unchosen**. That framing matters more than any individual
default being wrong: nobody had picked, so nothing could be reviewed, and a base-image change could
have reversed a property (non-root) that only held by inheritance.

Three constraints shape what a hardening pass can actually do here:

- **One node, 6 GB RAM** (`adr/0026`). A control that costs a pod, a sidecar or a policy engine has
  to justify itself against a memory budget whose worst case already exceeds the box.
- **The demo is public and healthy.** A `securityContext` a container cannot satisfy does not fail at
  apply time; it fails at start. Every change below was applied to one workload at a time against the
  live deployment and verified before the next.
- **Since `adr/0047`/`15-07` the images are pulled from GHCR under their commit SHA.** So an image is
  now identifiable, and "we could change the image" is a real option — but it is a change in
  `ago-console`, `ago-widget` or `ago-landing`, not in `ago-deploy`, and it moves a Service port with
  it.

## Decision

### 1. Every workload carries an explicit `securityContext`, and the values are per workload

`allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]` and
`seccompProfile: RuntimeDefault` are universal. `runAsNonRoot` / `runAsUser` /
`readOnlyRootFilesystem` are **not**, because three of them cannot be satisfied and one of them is
actively harmful:

| Workload | Runs as | `readOnlyRootFilesystem` | The thing that decided it |
|---|---|---|---|
| `ago-chat-api` / `-worker` / `-webhooks` | 1654 | yes | The chiseled base already defaulted to 1654 — now *stated*, so a base change fails loudly instead of silently reintroducing root |
| `postgres` | 70 | **no** | Needs a writable `/var/run/postgresql`; an `emptyDir` there arrives root-owned and only `fsGroup` would fix it — and `fsGroup` is the one field that must not be set here (below) |
| `redis` | 999:**1000** | yes | The image's `redis` account is uid 999 **gid 1000**; read out of the container, not guessed |
| `rabbitmq` | 999 | **no** | Its entrypoint writes `/etc/rabbitmq/conf.d/10-defaults.conf` on every boot |
| `minio` | 1000 | yes | **The only image genuinely running as root**, and the only one that needed a root init container to get off it (below) |
| `keycloak` | 1000:**0** | **no** | Group-root by design so it can run under any uid. `start-dev` re-augments `/opt/keycloak` on every boot; read-only needs `start --optimized`, which needs a derived image — `15-01`/`adr/0036`'s deferred work |
| `prometheus`, `alertmanager`, `node-exporter` | 65534 | yes | Already non-root; stated |
| `grafana` | 472 | yes | Already non-root; `fsGroup` needed for the existing group-root PVC |
| `jaeger` | 10001 | yes | In-memory storage, so nothing writes to disk at all |
| four nginx static sites | **root master** | yes | See 2 |

**`fsGroup` is not a safe default and is refused on Postgres specifically.** It makes Kubernetes
chgrp the volume and add group write, which turns `PGDATA` into `0770` — and Postgres refuses to
start on anything but `u=rwx` or `u=rwx,g=rx`. The obvious extra line is the harmful one. Where
`fsGroup` *is* used (Prometheus, Grafana, MinIO) it is paired with
`fsGroupChangePolicy: OnRootMismatch` so it does not re-walk a TSDB on every start, and on Grafana it
has a visible cost: it widens `grafana.db` from `0640` to `0660` and Grafana logs a permissions
warning on every boot from now on.

**MinIO needed a root init container, and that is a trade, not a workaround.** `fsGroup` alone made
every path group-writable — sufficient for Prometheus and Grafana — and MinIO still refused to start
with `Unable to write to the backend`, because it requires **owner** write and will not take group
write in its place. A `local-path` PVC is created by the provisioner as root, so a rebuilt cluster
lands in exactly the same state and no manifest field fixes it. So `minio.yaml` gains an init
container that runs as uid 0 with `CHOWN`, `FOWNER`, `DAC_OVERRIDE` and nothing else, whose whole job
is one idempotent `chown -R`. One short-lived root container in exchange for a permanently-root
server is worth it; pretending it is free is not.

### 2. The four nginx static sites stay root, and the manifest says so

`ago-console`, `ago-demo-shop1`, `ago-demo-shop2` and `ago-landing` are built `FROM
nginx:1.27-alpine-slim`, whose master process runs as root to bind `:80`. Making them non-root means
changing the image — `nginxinc/nginx-unprivileged` (listens on 8080) or a `USER` plus a config that
does — in three repositories, and moving the container port, the Service `targetPort` and the
`HTTPRoute` backend port with it. **`17-05` deliberately did not make that change from `ago-deploy`**,
because a hardening item that edits four images in three repositories it cannot test end to end is
how a public demo goes down for a reason nobody can bisect.

What the manifest does instead is not nothing. The root master keeps five capabilities out of the
fourteen it had — `NET_BIND_SERVICE`, `SETUID`, `SETGID`, `CHOWN`, `KILL`, each load-bearing for
nginx-as-root and none of them copied — cannot gain more, and **cannot write to its own image**. That
last one is the control with teeth: before it, `ago-console` could create a file under
`/usr/share/nginx/html` and the public internet would be served it.

### 3. `NetworkPolicy`: two targeted policies, not a namespace default-deny

k3s ships kube-router's policy controller unless `--disable-network-policy` is passed; this node
passes only `--disable traefik`, and its `iptables-save` carries 194 `KUBE-ROUTER-*` rules. **That was
checked before a single policy was written**, because a policy an unenforcing CNI ignores is worse
than none — it reads like protection.

- **`static-sites-egress`** — the four public static pods may reach DNS and nothing else. DNS is
  *allowed* on purpose: with it denied, every blocked connection would fail at name resolution, which
  proves the wrong thing.
- **`postgres`/`redis`/`rabbitmq`/`minio` ingress** — only from the workloads that have a reason to
  connect, plus two `ipBlock` entries.

**A namespace-wide default-deny was considered and refused.** `ago-chat` also holds the NGINX Gateway
Fabric data-plane pod, whose control-plane connection crosses into `nginx-gateway`, and cert-manager's
HTTP-01 solver pods, which are created in this namespace on demand with labels no committed file can
predict. A default-deny wrong about either takes the public certificate or the whole edge down — at
renewal time, weeks later, with nothing pointing back at the change.

### 4. Keycloak's realm moves from `sslRequired: none` to `external` — and it is inert today

Verified against the real `--proxy-headers=xforwarded` configuration: NGF does set
`X-Forwarded-Proto`, and after the change the hosted login page, the direct-grant token endpoint and
`Ago.Chat.Api`'s acceptance of the resulting JWT all still return `200`.

**But it refuses nothing on this deployment**, and saying otherwise would be false. Keycloak is
started with `--hostname=https://auth.reserve-me.ru`, which fixes the frontend URL scheme, so its SSL
check sees a secure request regardless of the forwarded proto — confirmed by replaying a request with
`X-Forwarded-Proto: http` and a public `X-Forwarded-For` and getting a byte-identical login page. What
actually forces TLS here is the Gateway's permanent `301`. `external` is therefore a guard against a
*future* misconfiguration — a removed `--hostname`, a second route, a NodePort onto `8080` — not the
closing of a present hole. It is still worth setting, and it is safe for the local loop because
loopback is a private address either way.

### 5. Kubernetes Secrets stay unencrypted at rest in k3s

Declined, with the reasoning recorded rather than the box ticked. `k3s secrets-encrypt enable` writes
its AES key to `/var/lib/rancher/k3s/server/cred/encryption-config.json` — the same directory tree as
the datastore it encrypts. So it defends only against an attacker who obtains the datastore file and
*not* its sibling, and no path this deployment has produces that: the k3s datastore is not in
`adr/0050`'s backup at all, and anything that copies the disk copies both halves. Against that it adds
a real new way to lose every Secret permanently (a lost or corrupted key file) and a rotation
obligation nobody on a single-admin demo box will meet.

What would change the answer, stated so it can be revisited on evidence rather than mood: a backup or
snapshot that takes the k3s datastore off this node, or a second node.

### 6. `fail2ban` is declined for the same shape of reason

`sshd -T` now reports `passwordauthentication no` and `authenticationmethods publickey`, so there is
no password to brute-force. `fail2ban` would spend memory on a 6 GB node rate-limiting attempts that
cannot succeed. The item itself predicted this ("it becomes near-irrelevant once password
authentication is genuinely off"); this records that the prediction was checked and acted on.

## Consequences

- **Every workload's identity is now a reviewable line in a manifest**, and a base-image change that
  reintroduces root fails at pod start instead of passing silently. That is the actual deliverable —
  more than any single flag.
- **Three `readOnlyRootFilesystem` gaps are now named, each with a named owner**: Postgres (needs a
  `fsGroup` it must not have), RabbitMQ (entrypoint writes its own config), Keycloak (`start-dev`
  re-augments on every boot, and `start --optimized` is `adr/0036`'s deferred work).
- **The nginx images remain the one place where a container runs as root**, and closing it is now a
  precisely specified change in three other repositories rather than a vague intention.
- **MinIO carries a root init container** — a real privilege that did not exist before this change,
  narrowed to three capabilities and one command, and the only way to get its long-lived process off
  root on a `local-path` PVC.
- **The `NetworkPolicy` set is deliberately incomplete.** Keycloak, Grafana, Prometheus, Jaeger and
  Alertmanager have no ingress policy. Each is in-cluster-only already; each would need an allowance
  whose shape is less certain than the four that were written.
- **A new operational trap exists and is written into the policy file**: the policies match on the
  **pre-masquerade** source address. `backup.sh` mirrors MinIO from a `minio/mc` container run by
  Docker on the host; `tcpdump` shows those packets arriving from `10.42.0.1`, and allowing
  `10.42.0.1/32` still drops them, because the policy is evaluated before the masquerade. The
  allowance that works is `172.17.0.0/16`. Established by A/B on the live node, not reasoned about —
  and the failure mode it avoids is the bad one: the nightly backup stopping at 02:30 UTC with
  nothing else visibly wrong.

## Alternatives considered

- **`nginxinc/nginx-unprivileged` for the four static images, now.** The right end state, and the one
  `17-05`'s own scope names first. Rejected *for this change*: it is an edit to three repositories a
  worker in `ago-deploy` cannot build or verify, and it moves the container port, the Service
  `targetPort` and the `HTTPRoute` backend port together. Specified per repository in
  `backlog/17-05` so it can be done as its own change with its own verification.
- **A namespace-wide default-deny `NetworkPolicy`.** See 3 — refused on the two components whose
  traffic no committed file can describe.
- **A Pod Security Admission label on the namespace** (`restricted`) instead of per-workload fields.
  Rejected: `restricted` requires `runAsNonRoot` on every pod, which the four nginx pods and MinIO's
  init container cannot satisfy today — so the namespace would need an exemption that turns the label
  back into a no-op, and the per-workload fields would still have to exist to say what each container
  actually needs. Worth revisiting once the nginx images are non-root, at which point the label
  becomes a genuine backstop rather than a duplicate.
- **Enabling k3s secrets encryption anyway, on the "it costs nothing" argument.** Rejected: it does
  cost something — a new way to lose every Secret — and it buys protection against a threat this
  node's shape does not produce. See 5, including what would reverse it.
- **Leaving Keycloak's `sslRequired` at `none` because raising it changes no behaviour today.**
  Rejected: "changes nothing today" is exactly the condition under which a guard should be installed,
  and the setting was already carried as an open gap in `runbooks/public-deploy.md`.
