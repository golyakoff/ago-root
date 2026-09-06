# Granting and revoking a product for a tenant

`23-15`, 2026-09-06. This is the procedure for putting a product — AGO Calendar, AGO FAQ — on a
tenant's account by hand, checking that it worked, and taking it away again.

**It is not the ordinary path to having a product.** Tenants buy products themselves. This exists for
the sales conversation and the support ticket, and `flows.md` 5.2 records that the *only* thing gating
it is a Keycloak realm role which **no write in this codebase grants** — that is the answer, not an
omission. If this page starts being used weekly, the thing to build is self-service, not a shortcut.

## Why this is a runbook and not a screen

Both routes require the deployment-wide **provisioning secret in the request body** (`adr/0095`), so a
console grant screen would put that secret into a browser form. `decisions.md` §6 is where the argument
lives; the short version is that a secret a person carries in a clipboard stops being a secret at about
the third use.

§6 also records what would change that — chat holding the secret in its own configuration, which makes
the screen possible and is an open amendment to `adr/0095`. Until that is decided, this page describes
the world as it is.

## What you need before you start

- The `siteId` of the tenant. Get it from `/owner` in the console, not from a person's memory.
- The **module key** (`calendar`, `faq`).
- The **provisioning secret** for the module deployment you are granting.
- Whether this grant has an end date, and if not, that you have decided it has none.

### Reading the provisioning secret

Read it **at the moment of use, and do not keep it.** It lives in the module deployment's own
environment; `secrets.md` names it (`ModuleProvisioning:Secret`) and says what rotating it costs.

Do not paste it into a chat message, a ticket, a note or a shell history you keep. If your shell
records history, read it into a variable in a way your shell does not log, or type it into the request
at the moment you send it.

**If you believe it has been seen by somebody who should not have seen it, that is
`secret-rotation.md`, immediately** — a holder of this secret can register, rotate or delete the
registration for any site that deployment serves.

## Granting

```
PUT /api/v1/owner/sites/{siteId}/modules
```

Every field is required, deliberately — including the expiry, which is `required` **and** nullable:

| Field | What it is |
|---|---|
| `moduleKey` | `calendar`, `faq` |
| `triggerWords` | what a visitor types to reach the module |
| `entryPoint` | where the module is reached |
| `credential` | the module's own per-site credential. Never echoed back |
| `provisioningSecret` | above |
| `expiresAt` | an instant, **or explicitly `null`** |

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

**Revoking something we granted** needs only the provisioning secret. Nothing else. Taking back what we
gave away must not be made harder.

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

- `docs/design/decisions.md` §6 — why this is a runbook rather than a screen, and what would change it
- `docs/design/flows.md` 5.2, 5.3 — the two "must never happen" clauses this procedure serves
- `docs/adr/0095-*` — the provisioning secret and its blast radius
- `docs/adr/0118-*` — the revoke asymmetry and the recorded reason
- `docs/architecture/secrets.md` — where the secret lives; `docs/runbooks/secret-rotation.md` — rotating it
- `docs/runbooks/realm-operations.md` — granting the realm role in the first place
