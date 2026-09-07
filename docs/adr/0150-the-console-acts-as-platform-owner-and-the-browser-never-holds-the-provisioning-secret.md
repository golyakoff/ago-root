# ADR-0150: the console acts as platform owner, and the browser never holds the provisioning secret

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-65`, `23-66`)
- **Amends**: `adr/0095` — the provisioning secret's holder, not its purpose.

## Context

`PUT` and `DELETE /api/v1/owner/sites/{siteId}/modules` require the deployment-wide provisioning
secret **in the request body** (`adr/0095`). That is why granting a product is a runbook
(`module-grant-and-revoke.md`) and not a screen: a console form would put a deployment-wide secret
into a browser.

`decisions.md` §6 decided this in two halves, openly: **runbook for now, and chat holding the secret in
its own configuration later, so the screen becomes possible.** The author asked for the second half on
2026-09-07, in their own terms — *я как владелец могу с ролью platform-owner выставлять и забирать
опции теннантам, менять лимиты и прочее… я придумал эту систему и хочу чтобы она работала так.*

Today this is not a convenience question. `enabled_modules` on the live deployment holds **zero rows**
against **seventeen** sites: nobody has the calendar, because the only way to give it to them is a
hand-made request carrying a secret. The product that exists cannot be reached by the customers who
have accounts.

## Decision

**The console calls the owner API with the platform owner's own authorisation, and chat supplies the
provisioning secret from its own configuration.** The browser never sees it, never holds it, and never
sends it.

- Authorisation is the realm role that already gates every owner route — the one **no write in this
  codebase grants** (`flows.md` 5.2). That property is unchanged and is what makes this safe to do at
  all.
- The secret moves from the caller to `Ago.Chat.Api`'s configuration, inventoried in `secrets.md` like
  every other secret it holds.
- **Every grant and revoke is recorded** — who, when, which tenant, which module, what expiry, and for
  a revoke of a tenant's own purchase, the reason `adr/0118` already demands.
- **`expiresAt` stays required.** The API refuses a body that omits it, deliberately, and a screen must
  not quietly default it. *A grant with no expiry is a discount nobody remembers giving* — the person
  choosing "never" must choose it.

## Why this is not a weakening, and where it genuinely is

`decisions.md` §6's own argument stands and is the main one: **the platform owner can read that secret
from the cluster anyway.** Requiring them to paste it protects nothing against an identity already
authenticated by a realm role nothing in this codebase can grant. It is not a second lock; it is a
second inconvenience.

**Where it is a real change, stated rather than glossed:** the secret stops being something a person
holds for a moment and becomes something a running service holds permanently. That widens what a
compromise of `Ago.Chat.Api` yields — today it does not yield module provisioning, and afterwards it
does. That is accepted because the same process already holds the channel-credential cipher key and the
database credentials: this adds a secret to a set, rather than creating the first one.

**It becomes clearly right rather than merely convenient if `22-04` ever makes the secret per-site.**
Then a browser form would be asking a person to handle a different secret for every tenant they touch,
which is unmanageable, and this decision would have to be taken anyway.

## Why not the alternatives

**Keep the runbook.** Rejected by the author, and the count above is why: seventeen sites, no modules,
because the mechanism has a human bottleneck. A product nobody can be given is not a product.

**Prompt for the secret in the browser at the moment of use.** Rejected outright and already rejected
in §6: a secret a person carries in a clipboard stops being a secret at about the third use.

**A separate owner-only service holding the secret.** Rejected as a deployable to operate for one
capability, with its own authentication surface — the thing `adr/0013`'s own reasoning about splitting
hosts by failure profile argues against when the profile is the same.

## Consequences

**Positive.** The platform owner can give and take a product from the console, which is what the
system was designed to do and what its own `flows.md` 5.2 describes. The runbook remains valid for the
day the console is unavailable, which is worth keeping rather than deleting.

**Negative.**

- **`Ago.Chat.Api` now holds a secret it did not hold**, and rotating it is a restart of that host —
  `secrets.md` gains a row and `secret-rotation.md` gains a paragraph.
- **A screen makes a rare act easy.** The runbook's friction was doing some work: it forced a person
  to stop and choose an expiry. The screen must carry that weight instead of inheriting the ease.
- **What counts as "a tenant option" is now an open question**, and deliberately not answered here.
  Modules and quantity limits are concrete and have tables behind them. Beyond those, the author's
  *«другие опции теннантов»* is a category rather than a list, and building a screen for a category
  produces a settings page nobody can explain. `23-65` and `23-66` take the two that exist; a third
  needs somebody to name what is actually in it.
