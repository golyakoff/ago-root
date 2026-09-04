# granting and revoking a product has a written procedure

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-14` — the runbook's verification step is "look at the tenant on `/owner` and
  confirm what you just granted is there"; without that read there is nothing to verify against but a
  second curl. `23-13` — the revoke section documents the override and its recorded reason.
- **Decision**: `docs/design/decisions.md` §6

## Goal

Whoever is handling a sales conversation or a support ticket can grant a product to a tenant, see
that it worked, and revoke it — from a written procedure, without inventing the commands and without
writing SQL against a live tenant, which `flows.md` 5.3 names as the remedy today.

## Why a runbook and not a screen

§6, and the reasoning is the whole item: both `PUT` and
`DELETE /api/v1/owner/sites/{siteId}/modules` require the deployment-wide provisioning secret in the
request body (`adr/0095`), so a console grant screen would put that secret into a browser form. **A
secret a person carries in a clipboard stops being a secret at about the third use.**

§6 also records what changes later — chat holding the secret in its own configuration, so the screen
becomes possible — and why that is a move of responsibility rather than a weakening: the platform
owner can read that secret from the cluster anyway, so requiring them to paste it adds no protection
to an identity already authenticated by a realm role that no write in this codebase grants. That is
an amendment to `adr/0095`, made openly, and it is **not** this item. This item is the procedure for
the world as it is.

## Context to read first

- `docs/design/decisions.md` §6 in full, both halves
- `docs/design/flows.md` 5.2 and 5.3 — both "must never happen" clauses land here
- `docs/adr/0095-*`, `docs/adr/0098-*`
- `docs/runbooks/realm-operations.md` — the nearest neighbour in tone and in blast radius
- `docs/architecture/secrets.md` — where the provisioning secret lives and what rotating it costs
- `Ago.Chat.Api/Owner/OwnerModuleEndpoints.cs`

## Scope

A new page in `docs/runbooks/`, beside `realm-operations.md`, covering:

- Where the provisioning secret is read from, and the rule that it is read at the moment of use and
  not kept. **No secret, no token and no real endpoint in the file** — `<node-ip>` and named
  placeholders only.
- The grant: which site, which module key, with an end date **or an explicit statement that there is
  none**. The endpoint already refuses a body that omits `expiresAt` entirely, so the procedure's job
  is to make the operator *write down which of the two they chose* — `flows.md` 5.2: a grant with no
  expiry is a discount nobody remembers giving.
- **What expiry actually binds.** Chat stops offering the module the instant it lapses; the module is
  never told. The runbook says so at the point of granting, because that is where somebody forms the
  wrong belief.
- The verification step, against `23-14`'s read rather than against the write's own response.
- The revoke, and **the asymmetry**: revoke works on a tenant's own purchase as readily as on a
  grant. After `23-13` the endpoint refuses that case unless the caller says they mean it and says
  why, so the procedure's step is *check the provenance on `/owner` first, then decide whether you
  are about to use the override, then write the reason you would be willing to show the tenant.* Not
  a sentence at the end.
- The standing limit: this must never become the ordinary path to having a product. Nothing but a
  Keycloak realm role gates it, and no write in this codebase grants that role — `flows.md` 5.2
  records that this is the answer, not an omission.
- Pointers to `secrets.md` for rotation and to `23-14` for the read.

## Out of scope

- A console grant screen, and the `adr/0095` amendment that would make one possible. Doing either
  here would be doing the deferred work under a runbook's number.
- Automating the procedure into a script that holds the secret.
- Any change to `OwnerModuleEndpoints` or to the wire contract. That is `23-13`.

## Done when

- [ ] The runbook exists and a reader who has never granted a module can follow it end to end against
      a local cluster.
- [ ] It contains no secret, no token and no real hostname or address.
- [ ] It states, at the grant step, what expiry binds and what it does not.
- [ ] Its revoke section requires checking provenance before acting, names the override, and says
      what the recorded reason is for.
- [ ] `CLAUDE.md`'s "Where to look" table and `docs/runbooks/`'s own index name it.

## Open questions

None.
