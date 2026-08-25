# Keycloak: a user store that survives a pod restart

- **Stage**: 15
- **Status**: done (locally verified) — one step left that only the node can close, see Outcome
- **Depends on**: nothing new architecturally — `5-05-operator-oidc-authentication.md`'s realm-import
  mechanism and `adr/0022`'s shared-realm claims model both stay exactly as they are; this item changes
  where Keycloak keeps its own rows, not how AGO Chat authenticates against it

## Goal

Keycloak's user store outlives its own pod. Today it does not: `deploy/k8s/base/keycloak.yaml` runs
`start-dev` with no `KC_DB` set anywhere in `ago-deploy` (a repository-wide `grep` finds zero
occurrences) and no volume mounted at its data directory, so the embedded H2 database lives in the
container's ephemeral writable layer and is destroyed by every restart, redeploy, eviction and node
reboot. Only what `keycloak-realm-import.json` re-imports on boot comes back — the seeded demo
operators. Everything created at runtime does not. After this item, a user who registers through
`10-01`'s self-registration flow is still there tomorrow.

## Context to read first

`deploy/k8s/base/keycloak.yaml` in full — the `args` line, the absent `KC_DB*` env, and the fact that
the only `volumeMounts` entry is the read-only realm-import ConfigMap. `deploy/k8s/overlays/demo/
kustomization.yaml`'s Keycloak patch — it replaces `args` to add `--hostname`/`--proxy-headers` for
public TLS termination and deliberately does *not* add the `imagePullPolicy: Never` its neighbours
carry (that mistake is already documented inline as a real live bug); it does not touch persistence
either way. `docs/backlog/10-01-self-registration-identity-flow.md` — the flow whose whole premise is
runtime-created users. `docs/backlog/5-05-operator-oidc-authentication.md` — the realm-import
mechanism this item must keep idempotent against a database that is no longer empty on second boot.
`adr/0026`'s "Consequences" — it already names `start-dev` on the public deployment as a stated,
deliberate gap; this item closes the half of that gap that turned out to have a data-loss consequence,
which the ADR did not anticipate.

## Scope

- Point Keycloak at a real, persistent database (`KC_DB`, `KC_DB_URL`, credentials from the existing
  `infra-credentials` Secret — no new secret mechanism). Whether that is a separate logical database
  inside the existing Postgres Deployment or its own instance is this item's decision to make and
  state; the one-node reality (`adr/0026`) argues for reuse, and "Keycloak's schema must never share a
  database with the application's own migrations" argues for at least a separate database, not merely
  a separate schema.
- Decide and record whether the public deployment moves off `start-dev` to production `start` mode.
  This is a real decision with real consequences (build-time augmentation, strict hostname/TLS
  requirements, `--optimized`), not a cleanup — it gets an ADR, or an explicit paragraph in `adr/0026`'s
  own update section saying why it stays on `start-dev` even with a persistent database.
- Prove realm-import idempotency against a *non-empty* database: boot once, register a user at runtime,
  restart the pod, confirm both the seeded realm objects and the runtime-created user are present and
  the import did not overwrite or duplicate anything.
- Apply the same change to `overlays/local` and `docker-compose`, so local dev and the demo deployment
  do not diverge in a way that hides this class of bug locally — the reason it survived until now is
  precisely that a local Keycloak pod boots once and stays up for weeks.
- Keycloak's own first-boot timing is already documented in `keycloak.yaml`'s probe comments (~23s
  Quarkus augmentation plus a Liquibase migration, measured live). A Postgres-backed first boot runs
  the same migration against a remote database — re-verify the probe delays still hold rather than
  assuming they carry over.

## Out of scope

- Migrating the existing demo users out of the current H2 store — there is nothing worth migrating; the
  seeded operators come from realm-import on every boot, and any self-registered demo account has
  already been lost or will be before this ships. Say that plainly in the runbook rather than building
  an export path for data that is not there.

  **Amended while doing the work (2026-08-25):** the premise turned out to be too optimistic. The demo
  realm does hold state worth naming — runtime-created accounts, and a `platform-owner` grant made by
  hand under `12-01`/`adr/0032`, which the realm import does not restore. Migration stays out of scope,
  and for a stronger reason than "there is nothing there": there is no path. The Admin API never returns
  credentials, so an export would produce users without passwords, and `kc.sh export` cannot run against
  a live `start-dev` H2 file because H2 permits one process to hold it open. So the deliverable is what
  this bullet asked for — the runbook says it plainly — but it says "this destroys the following, here
  is what to record first and what to re-apply after", not "there is nothing to lose".
- Keycloak high availability, clustering, or an external user federation — one node, one Keycloak
  (`adr/0026`), unchanged by this item.
- Changing `adr/0022`'s shared-realm, resolve-claims-at-request-time model in any way.

## Done when

- [x] Keycloak runs against a persistent database, with credentials from the existing Secret mechanism
      and nothing new committed. `KC_DB`/`KC_DB_URL`/`KC_DB_USERNAME`/`KC_DB_PASSWORD` in
      `k8s/base/keycloak.yaml`, one new `KEYCLOAK_DB_PASSWORD` key in the same `.env` →
      `secretGenerator` → `infra-credentials` chain every other credential already uses. Applies to the
      demo overlay too — that overlay patches `args` only, so it inherits the change from base. **Not
      yet applied on the node**: see the last box.
- [x] Realm-import proven idempotent against a non-empty database, by an actual second boot — and the
      mechanism read off Keycloak's own log rather than assumed: `Strategy: OVERWRITE_EXISTING` /
      `Realm 'ago-chat' imported` on the first boot into an empty database, `Strategy: IGNORE_EXISTING`
      / `Realm 'ago-chat' already exists. Import skipped` on every boot after. Nothing was duplicated
      and nothing was overwritten.
- [x] The `start-dev`-vs-`start` decision is recorded — `adr/0036`, which re-opens `adr/0026`'s gap
      (one of its justifications had expired) and keeps `start-dev` with the reasoning stated, reducing
      the remaining gap to one checkable precondition.
- [x] `docs/runbooks/k8s-local.md`, `local-dev.md`, `public-deploy.md` and `redeploy.md` reflect the new
      database dependency, its startup ordering, and the fact that a manifest-only change does not
      reach the node through `redeploy.sh`.
- [ ] A user registered at runtime is still able to log in after a pod restart — **verified live on the
      local cluster, not yet on the demo deployment.** Deliberately left open: the demo deployment was
      not touched by this work (a running public deployment is not a place to test a store migration
      from a session that cannot watch it), and closing this box means running
      `public-deploy.md`'s "Applying `15-01` to this deployment" section on the node.

## Outcome

**What was built.** Keycloak's realm and users live in their own `keycloak` database, owned by its own
`keycloak` role, inside the Postgres Deployment that already holds `ago_chat` (`adr/0036` argues the
shared-instance/separate-database/separate-role split, including the cost it accepts: an authentication
outage is now correlated with a chat-database outage, which on a one-node cluster is close to free).
Postgres's image only creates `POSTGRES_DB`, and only on the first initialisation of an empty data
directory, so an `initdb.d` script would never fire on a cluster whose PVC already has data — an
idempotent **init container** creates the role and the database instead, and doubles as the
Postgres-must-be-up-first dependency. `docker-compose` gets the identical script as a one-shot
`keycloak-db-init` service gated by `service_completed_successfully`, so the compose loop and the
cluster no longer differ in a way that hides this class of bug locally.

**The bug was reproduced before it was fixed.** On the local cluster: create a user through the admin
API, `kubectl rollout restart deployment/keycloak`, list users — the account was gone, only the seeded
operators remained. After the change, the same sequence (plus a real password grant, `200` with a live
access token) survives the restart, and survives a full container recreate on the compose loop too.

**The realm-import half.** Persistence took away the accidental reconfiguration mechanism, because the
only reason editing `keycloak-realm-import.json` ever reached a running realm was that the store was
being destroyed on every boot. `--import-realm` picks `OVERWRITE_EXISTING` against an empty database and
`IGNORE_EXISTING` once the realm is there, and `Import skipped` skips the *whole* file. So
`ago-deploy/k8s/apply-realm-settings.sh` is the deliberate step: it PUTs the realm-level fields of the
file Keycloak actually has mounted onto the live realm and leaves users and clients untouched —
demonstrated end to end (change `accessTokenLifespan` in the file → restart → still the old value →
run the script → new value, with the runtime-created user present and still able to log in throughout),
on both the `k8s` and `compose` targets.

**Two documented facts turned out to be false and were corrected in the same change**, both of them
consequences of nobody having had a persistent Keycloak to test against:

- `ago-deploy/k8s/base/kustomization.yaml` claimed a brand-new top-level entity added to the realm file
  *is* created on the next restart even when the realm is skipped. It is not — tested with a new realm
  role and a changed lifespan; neither arrived.
- `public-deploy.md` recorded `8-05`'s finding that adding a user to the JSON and restarting reaches an
  already-provisioned realm. The observation was real, the conclusion was not: the restart was wiping
  the H2 store, so there was no already-provisioned realm to reach.

**What an operator must do about the existing demo state — this is not free.** The demo's Keycloak
currently holds runtime-created users and a hand-granted `platform-owner` role. Applying this change
starts Keycloak against an empty database and **all of that is destroyed**; the seeded realm, client
and operators come back from the import, nothing else does. There is no migration path worth building
(the Admin API never returns credentials, and `kc.sh export` cannot run against a live `start-dev` H2
file), which is wider than this item's own "Out of scope" anticipated, so it is spelled out rather than
left to be discovered. `public-deploy.md`'s new section is the procedure: capture the user list and the
`platform-owner` members first, add `KEYCLOAK_DB_PASSWORD` to the node's `.env`, `kubectl apply -k`,
re-grant the owner role by hand, and tell self-registered accounts to register again — once.

**Not verified, and honest about it.** Nothing was run against the VPS. Whether Keycloak trusts the
`X-Forwarded-Proto` header the Gateway sets still cannot be checked locally (there is no TLS
terminating in front of the local Keycloak), so `sslRequired: "none"` was left exactly as `17-06` left
it rather than changed blind — `adr/0036` names raising it as the concrete precondition for ever
considering production `start` mode, instead of the open-ended "hardening" gap `adr/0026` carried.

## Open questions

None. The two decisions this item contains (which database, which Keycloak mode) are implementation
choices a session can make and defend from the constraints listed above — not questions needing the
author, per `README.md`'s own bar for `blocked`. Both are recorded in `adr/0036`.
