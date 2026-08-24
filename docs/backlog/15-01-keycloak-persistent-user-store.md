# Keycloak: a user store that survives a pod restart

- **Stage**: 15
- **Status**: ready
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
- Keycloak high availability, clustering, or an external user federation — one node, one Keycloak
  (`adr/0026`), unchanged by this item.
- Changing `adr/0022`'s shared-realm, resolve-claims-at-request-time model in any way.

## Done when

- [ ] Keycloak on the demo deployment runs against a persistent database, with credentials from the
      existing Secret mechanism and nothing new committed.
- [ ] A user registered at runtime through `10-01`'s flow is still able to log in after
      `kubectl delete pod` — verified live on the demo deployment, not only locally.
- [ ] Realm-import proven idempotent against a non-empty database, by an actual second boot.
- [ ] The `start-dev`-vs-`start` decision is recorded in an ADR or in `adr/0026`'s update section.
- [ ] `docs/runbooks/k8s-local.md` and the demo runbook reflect the new database dependency and its
      startup ordering.

## Open questions

None. The two decisions this item contains (which database, which Keycloak mode) are implementation
choices a session can make and defend from the constraints listed above — not questions needing the
author, per `README.md`'s own bar for `blocked`.
