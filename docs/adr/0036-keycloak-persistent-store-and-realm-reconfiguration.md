# ADR-0036: Keycloak on a separate database inside the shared Postgres; `start-dev` stays; realm settings stop arriving by restart

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 15

## Context

`15-01-keycloak-persistent-user-store.md`: Keycloak ran `start-dev` with no `KC_DB` anywhere in
`ago-deploy` and no volume at its data directory, so its embedded H2 database lived in the container's
ephemeral writable layer. Every restart, redeploy, eviction and node reboot destroyed it. Only what
`--import-realm` re-created came back — the seeded demo operators. Everything created at runtime did
not, which is every account `10-01`'s self-registration flow (`adr/0028`) exists to create.

Reproduced live before changing anything, on the local cluster (2026-08-25): a user created through
Keycloak's admin API, then `kubectl rollout restart deployment/keycloak`, then the user list — the
account was gone, and only the two seeded operators remained. The bug was real and it was total.

There is a second face to the same mechanism, and it landed the day before this item: `17-06`
(`adr/0034`) put the realm's login-security policy — brute-force thresholds, password policy, TOTP
parameters, four token/session lifetimes — into `keycloak-realm-import.json`. That file only reaches a
realm through `--import-realm`, and `--import-realm` does not unconditionally apply. Persistence and
re-importability are the same fact seen from opposite ends: *the realm import is a bootstrap, and it
only rebuilt the realm on every boot because the store was being destroyed on every boot*. Fixing the
data loss necessarily takes the accidental reconfiguration mechanism away with it, so this ADR has to
answer both or it has broken something while fixing something.

Three things needed deciding: which database backs Keycloak and whether it is shared; whether the
public deployment moves off `start-dev`; and how a realm-settings change reaches a realm that already
exists.

## Decision

### 1. A separate logical database (`keycloak`) with its own role, inside the existing Postgres

Not a second Postgres instance, and not merely a second schema in `ago_chat`.

**Why not its own instance.** `adr/0026`'s sizing puts steady-state at ≈3.65–4.25 GiB on a 6 GB node
with ≈1.75–2.35 GiB of headroom, and it already accepts a real OOM risk in the worst case where every
pod sits at its limit. A second Postgres Deployment spends 256 MiB of requests and 512 MiB of limit
out of exactly that headroom, permanently, to isolate a workload measured in kilobytes — a Keycloak
realm with a handful of users. The honest cost of sharing is stated rather than hidden: **an outage of
the application's database is now also an authentication outage.** On a one-node cluster where both
would live on the same node, the same disk, and the same kernel anyway, that correlation is close to
free — the failure that takes out Postgres takes out the API in the same instant, and an IdP that
survives while nothing can be authenticated *for* is not a meaningfully better outcome. This is the
kind of coupling worth refusing on a real multi-node production system and worth accepting here, and
the reason it is worth accepting is a property of this deployment (`adr/0026`), not a general rule.

**Why not a schema in `ago_chat`.** Keycloak owns its schema and migrates it with Liquibase on every
version bump. `ago-chat` owns its schema and migrates it with EF Core (`redeploy.sh` step 4). Two
migration tools with independent version histories writing into one database is a class of accident —
a `dotnet ef database update` that drops what it does not recognise, a restore of one product's backup
clobbering the other's tables — with nothing to gain, since a second database in the same server costs
one `CREATE DATABASE`.

**Its own role, not `POSTGRES_USER`.** `KEYCLOAK_DB_PASSWORD` is a new key in the existing
`infra-credentials` Secret (the same `.env` → `secretGenerator` mechanism every other credential in
this deployment already uses — no new secret mechanism, nothing new committed). The role `keycloak`
owns only the `keycloak` database. Reusing the application's own superuser would mean a compromise of
the IdP's database credentials hands over the application's database too, which is a strictly worse
trade than one extra line in a `.env` file. The cost is real and is stated in `.env.example`: an
existing deployment that does not add this key gets a Keycloak pod that fails to start.

**How the database gets created.** Postgres's official image only creates `POSTGRES_DB`, and only on
the first initialisation of an empty data directory — so an `initdb.d` script is useless here, because
every cluster this change will ever be applied to already has data in its PVC. An **init container**
on the Keycloak pod creates the role and the database instead, idempotently, on every boot: identical
on a fresh cluster and on one that has been up for weeks. It doubles as the startup-ordering
dependency — the pod waits in `Init` until Postgres accepts connections, so Keycloak's readiness
delays are not spent probing a server that is still coming up. `docker-compose` has no init
containers, so it gets the same script as a one-shot service with
`depends_on: condition: service_completed_successfully`, which is the same thing under a different
name.

### 2. `start-dev` stays, on the demo deployment as well as locally

`adr/0026` named production `start` mode as a deliberate gap. This item is the reason to re-open it,
because one of that gap's justifications ("a demo IdP for one seeded operator") stopped being true
when `adr/0028` opened the realm to public self-registration, and because "start-dev keeps its data in
H2" was part of what made the gap matter. Re-opened, and still declined — for a different and narrower
reason than before:

- The database objection is gone. `start-dev` only *defaults* to `dev-file`; an explicit `KC_DB` wins,
  which is what this change relies on and what was verified live (Keycloak boots on `jdbc-postgresql`,
  logs `Installed features: [... jdbc-postgresql ...]`, and its data survives a pod delete).
- What is left between here and `start` is not a flag. Production mode enforces the strict
  hostname/TLS posture that `17-06` deliberately did **not** enable: it left `sslRequired: "none"`
  because it could not verify that Keycloak actually trusts the `X-Forwarded-Proto` header NGINX
  Gateway Fabric sets in front of it. That is unchanged by this item — nothing about moving the user
  store to Postgres makes proxy-header trust verifiable, and it cannot be verified on the local
  cluster because there is no TLS terminating in front of the local Keycloak to forward a header
  *about*. Moving to `start` while `sslRequired` is still `none` would pair a mode that assumes a
  correct TLS posture with a realm configured as though there is none — the worst of both, and a
  change made blind.
- `--optimized` (the reason to prefer `start` at all: it skips the ~23s Quarkus augmentation each boot
  by doing it at image build time) needs a `kc.sh build` step, which means building and delivering a
  derived Keycloak image. `adr/0026`'s image delivery is `docker save` piped into the node's
  containerd, with no registry; adding a fourth locally-built image to that pipeline for ~23s of boot
  time on a demo cluster is not a trade this item is asked to make, and `15-06` is where image
  identity and delivery are being reconsidered anyway.

So `start-dev` stays, and the remaining gap is now stated as one concrete precondition instead of a
general "hardening" wish: **verify proxy-header trust end to end through the Gateway on the real node,
raise `sslRequired` to `external`, and only then consider `start`.** That is a smaller and checkable
piece of work, which is the point of writing it down this way.

### 3. A realm-settings change reaches a running realm through a script, never through a restart

Verified live rather than assumed, by reading Keycloak 26.0.8's own startup log on both paths:

```
first boot, empty database:   KC-SERVICES0030: Full model import requested. Strategy: OVERWRITE_EXISTING
                              Realm 'ago-chat' imported
every boot after that:        KC-SERVICES0030: Full model import requested. Strategy: IGNORE_EXISTING
                              Realm 'ago-chat' already exists. Import skipped
```

Keycloak picks the strategy from the state of the database it finds. This is *why* the persistent
store is safe — if `--import-realm` overwrote unconditionally, every restart would have rebuilt the
realm and taken the self-registered users with it, and this whole item would have achieved nothing.
It is also why the realm import stops being a way to change anything.

`ago-deploy/k8s/apply-realm-settings.sh` is the deliberate step. It `PUT`s
`keycloak-realm-import.json`'s realm-level fields onto the live realm through the admin API, reading
the file **from inside the running container** — the read-only mount that Keycloak itself was given,
not a copy from whatever checkout the script happens to run in. `PUT /admin/realms/{realm}` maps the
realm-level fields and ignores the representation's nested `users`/`clients`/`roles` collections,
which is exactly the split wanted: settings move, accounts do not. Verified on both targets (`k8s` and
`compose`) with a runtime-created user present throughout — the user was still there and still able to
obtain a token afterwards.

**Not `kc.sh import --override true`.** That applies the whole file, and it does so by replacing the
realm — deleting every runtime-created user with it. It is the obvious-looking answer and it is the
one thing that must never be run against this realm.

**A claim that turned out to be false, corrected in the same change.** `base/kustomization.yaml`
carried a comment stating that a brand-new top-level entity added to the realm file *is* created on the
next restart even when the realm itself is skipped. It is not: "Import skipped" skips the whole import.
Tested directly — a new realm role and a changed `accessTokenLifespan` were added to the file, the pod
was restarted, and neither reached the realm; the script then applied the lifespan change (and,
correctly, not the role). Adding or changing a client, realm role or group on an existing realm needs
its own `kcadm.sh` call in the same change that edits the JSON. The script's own header says so rather
than implying more coverage than it has.

## Consequences

- **The existing demo Keycloak's runtime state is destroyed by this change, and there is no migration
  path.** Keycloak starts against a brand-new empty `keycloak` database; the H2 file the current pod
  is using is not read, converted, or referenced. Everything created at runtime on the demo — every
  self-registered account, and the `platform-owner` realm role grant made by hand under `adr/0032` —
  is gone at the moment the new pod starts. This is a wider loss than `15-01`'s own "Out of scope"
  anticipated (it assumed nothing worth migrating existed), so it is named here rather than left to be
  discovered. It is not recoverable after the fact: passwords cannot be exported through the admin API
  (credentials are never returned), and `kc.sh export` cannot run against a live `start-dev` H2 file
  because H2 allows only one process to hold it open. `runbooks/public-deploy.md` carries the
  pre-flight capture and the post-apply re-grant an operator must do; the honest summary is that
  self-registered demo accounts must register again, and the owner grant must be re-applied by hand.
  After this change, that is the last time this class of loss is expected.
- **`KEYCLOAK_ADMIN_PASSWORD` becomes first-boot-only.** With no database that survived, the bootstrap
  admin was recreated from the environment on every boot, so editing the value and restarting rotated
  it. Now the admin account is a row that persists, and the environment variable is ignored once it
  exists. Rotating the Keycloak admin password is an admin-console or `kcadm.sh` action from here on.
- **An authentication outage is now correlated with a chat-database outage** — the accepted cost of
  the shared instance, argued above. Worth revisiting if this deployment ever stops being one node.
- **An existing deployment cannot pick this change up by restarting.** It needs `KEYCLOAK_DB_PASSWORD`
  in its `.env` and a `kubectl apply -k` of the overlay — `redeploy.sh` pulls, builds, migrates and
  restarts, but it does not apply manifests, so a manifest-only change does not reach the node through
  it. `runbooks/redeploy.md` says so now.
- **Probe delays were re-measured, not assumed to carry over** (`15-01` asked for exactly this, since
  Liquibase now runs over the network instead of against a local file). First boot into an empty
  database: schema creation plus realm import ≈19s of the boot, Quarkus `started in 29.253s`, HTTP
  listening ≈40s after container start. Restart against the populated database: import skipped in <1s,
  `started in 10.852s`, listening 35s, pod Ready 61s. The existing `initialDelaySeconds: 60` is now the
  binding constraint rather than Keycloak, so the delays are unchanged — measured, and left alone
  because the measurement said to.
- **One more thing to remember when changing realm settings.** Before this, editing the JSON was
  enough (by accident). Now it is edit, then run the script — and for clients/roles/groups, edit then
  `kcadm.sh` by hand. That is more ceremony than "restart it", and it is the correct amount for a
  realm that holds real accounts.

## Alternatives considered

- **A PersistentVolumeClaim mounted at Keycloak's data directory, keeping H2.** The smallest possible
  change, and it does make the user store survive a restart. Rejected: H2 is a single-writer embedded
  file that Keycloak's own documentation limits to development, and this deployment has already been
  bitten by that exact property — `base/keycloak.yaml` still carries the comment from the live
  2026-08-24 deadlock where a RollingUpdate briefly ran two pods against one exclusive lock and
  neither became Ready. Trading a data-loss bug for a lock-contention bug is not a fix, and `15-01`
  asked for a real database in the first place.
- **Its own Postgres instance for Keycloak.** The textbook answer, and the right one on a cluster with
  room. Rejected on this one for the memory-headroom reason above; the isolation it buys over a
  separate database in the same server is availability isolation, which a single node does not
  actually provide.
- **A separate schema in `ago_chat` rather than a separate database.** Rejected — two independent
  migration tools in one database, discussed above.
- **A Kubernetes `Job` to create the database instead of an init container.** Runs once rather than on
  every pod start, which is tidier in principle. Rejected: a Job does not gate the pod, so Keycloak
  could still start before it finished, and a Job that has already completed is not re-run when the
  cluster is rebuilt from manifests, which puts a "did you remember to run the Job" step back into
  every bring-up. The init container is idempotent and gates the thing that depends on it, which is
  what was wanted.
- **`--import-realm` with an overwrite strategy, so the realm file stays the single source of truth.**
  Superficially the cleanest answer to the reconfiguration half, and the one to reach for by reflex.
  Rejected outright: it replaces the realm, which deletes exactly the users this item exists to
  preserve. Named in the script's own header as the thing not to run.
- **Keeping the realm ephemeral (no persistence for the realm, persistence only for users).** Not
  expressible — Keycloak stores both in the same schema, and there is no "import over the top without
  touching users" mode. The realm-level `PUT` in the script is the closest thing that exists, and it
  is what was built.
