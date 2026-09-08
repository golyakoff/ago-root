# Granting and revoking a product for a tenant

`23-15`, 2026-09-06. This is the procedure for putting a product — AGO Calendar, AGO FAQ — on a
tenant's account, checking that it worked, and taking it away again.

**It is not the ordinary path to having a product.** Tenants buy products themselves. This page (and
the console screen below) exist for the sales conversation and the support ticket, and `flows.md` 5.2
records that the *only* thing gating either is a Keycloak realm role which **no write in this codebase
grants** — that is the answer, not an omission.

## The ordinary route is now the console — this page is the fallback

**`23-65`/`adr/0150`: `/owner`'s tenant detail screen grants and revokes a module.** That screen calls
the identical two routes this page describes, with the identical rules — an expiry has to be chosen,
revoking a purchase demands `force` and a reason — and it is where a platform owner should do this in
the ordinary case.

**This page still exists for the day the console is unavailable.** The two routes below work exactly
the same way from a terminal as they do from the screen; nothing here was removed, only made unnecessary
in the common case. If you can reach `/owner`, use it — reserve this procedure for when you cannot.

**What changed under this page since it was written:** both routes used to require the deployment-wide
provisioning secret *in the request body*, which is exactly what made a console screen impossible
(`decisions.md` §6's own argument — a secret a person carries in a clipboard stops being a secret at
about the third use). `23-65` moved that secret into `Ago.Chat.Api`'s own configuration
(`secrets.md`, `secret-rotation.md`). **Neither route below takes it from the caller any more** — not
from the console, and not from this page's own curl calls. The person running this procedure now needs
only their own platform-owner authorisation, nothing else to fetch or paste.

**`23-92`/`adr/0154` removes a second field the identical way.** The grant used to also take
`entryPoint` — where the module is reached — as a caller-supplied URL. That value is the deployment's
own fact, not the person granting's: it is now resolved server-side from `ModuleEntryPoints:<moduleKey>`
(`secrets.md`'s neighbouring configuration, `ago-deploy`'s own manifest), and a module this deployment
has not declared an address for is refused outright, naming the missing key, rather than accepted and
failing later against whatever address you happened to type.

## What you need before you start

- The `siteId` of the tenant. Get it from `/owner` in the console, not from a person's memory.
- The **module key** (`calendar`, `faq`) — this is also the *only* thing that decides where the module
  is reached; there is no address for you to look up or supply.
- Whether this grant has an end date, and if not, that you have decided it has none.
- Your own platform-owner bearer token. There is nothing else to hold — the deployment's own
  provisioning secret is `Ago.Chat.Api`'s own configuration now, never something a caller supplies
  (`secrets.md`).

## Granting

```
PUT /api/v1/owner/sites/{siteId}/modules
```

Every field is required, deliberately — including the expiry, which is `required` **and** nullable:

| Field | What it is |
|---|---|
| `moduleKey` | `calendar`, `faq` |
| `triggerWords` | what a visitor types to reach the module |
| `credential` | the module's own per-site credential. Never echoed back |
| `expiresAt` | an instant, **or explicitly `null`** |

There is no `entryPoint` field any more — see `adr/0154`. If you send one anyway (an old note, a stale
script), it is silently ignored; the address actually used always comes from this deployment's own
`ModuleEntryPoints:<moduleKey>` configuration. A `503 Module.EntryPointNotConfigured` here means exactly
that: this deployment has not declared where that module lives yet, a `ago-deploy` manifest gap, not
something you can work around by typing an address.

**`expiresAt` is the field this whole page exists to slow you down on.** The endpoint refuses a body
that omits it entirely, so you cannot forget it by accident — but you can still send `null` without
thinking. Sending `null` is a decision that this grant never ends. `flows.md` 5.2 puts it plainly: *a
grant with no expiry is a discount nobody remembers giving.* Write down which of the two you chose, in
the ticket or the deal note, at the moment you choose it.

### What an expiry binds, and what it does not

**Chat stops offering the module the instant the grant lapses. The module itself is never told.**

So an expired calendar grant means the tenant's visitors stop being routed to booking — it does not
mean the calendar deployment forgets the tenant, deletes their data, or stops serving a request that
reaches it another way. If you are granting a trial and somebody asks "what happens on day 31", that
is the honest answer, and it is worth saying at the point of granting rather than at the point of
disappointment.

## Verifying

**Verify against the read, not against the write's own response.** A `200` from the grant tells you
the call succeeded; it does not tell you what the tenant now has.

```
GET /api/v1/owner/sites/{siteId}
```

That is `23-14`'s per-tenant detail read, and it is the same thing the `/owner` console screen shows.
Confirm three things: the module is listed, its expiry is what you intended (including *absent* if you
meant absent), and its provenance says the platform owner granted it.

## Revoking

```
DELETE /api/v1/owner/sites/{siteId}/modules/{moduleKey}
```

**Check provenance first.** `/owner` tells you whether this module is there because *we* granted it or
because the *tenant bought it*. That distinction decides everything below, and you cannot recover it
after the row is gone.

**Revoking something we granted** needs nothing beyond your own platform-owner authorisation. Taking
back what we gave away must not be made harder.

**Revoking a tenant's own purchase is refused** unless the request states `force: true` **and** a
`reason` that is not blank. That asymmetry is the decision in `adr/0118`, and the refusal is not a
safety rail you route around — it is the system asking whether you know which of the two cases you are
in.

Before you set `force`:

1. Confirm on `/owner` that this really is a tenant purchase and not a grant.
2. Decide whether you are willing to override a thing somebody paid for.
3. **Write the reason you would be willing to show that tenant.** It is stored verbatim in
   `module_revoke_overrides` and it is free text on purpose — `adr/0118` chose free text over an
   enumerated code specifically because a justification that cannot name what happened is not one.

"Cleanup", "test" and "asked to" are not reasons. "Tenant reported double billing under ticket 412 and
asked for the calendar add-on to be removed pending the refund" is.

## The standing limit

Nothing in this codebase can grant the realm role that lets these two calls through. That means this
procedure cannot be delegated by writing code — only by a realm operation
(`realm-operations.md`), performed by a person, deliberately.

Keep it that way. `flows.md` 5.2's "must never happen" clause is that a product arrives on an account
without anyone being able to say who put it there and why; every step above exists to keep the answer
to that question written down somewhere other than one person's memory.

## Related

- `docs/design/decisions.md` §6 — why this used to be a runbook-only path, and the amendment recording
  that it no longer is
- `docs/adr/0150-*` — the console calling the owner API and `Ago.Chat.Api` supplying the provisioning
  secret from its own configuration; the decision that made the console screen possible
- `docs/adr/0154-*` — the identical reasoning applied to the module's own entry point; removes
  `entryPoint` from the grant body entirely
- `docs/design/flows.md` 5.2, 5.3 — the two "must never happen" clauses this procedure serves
- `docs/adr/0095-*` — the provisioning secret and its blast radius, amended by `adr/0150`
- `docs/adr/0118-*` — the revoke asymmetry and the recorded reason
- `docs/architecture/secrets.md` — where the secret lives now, on both sides; `docs/runbooks/secret-rotation.md` — rotating it
- `docs/runbooks/realm-operations.md` — granting the realm role in the first place
