# AGO Calendar still has no tenant, and nobody has ever signed in to one

- **Stage**: 20
- **Status**: ready — **the grant half is proven; the sign-in half is blocked on `23-102`**
  `23-87`'s third are all closed by the same demonstration: grant, sign in, create a first worker.
- **Depends on**: nothing new. `20-27` built the path; `22-06` moved the screens. Both shipped.
- **Carried out of**: `20-27`, whose last two Done-when boxes this is. Filed under CLAUDE.md rule 14 —
  a remainder gets its own number rather than sitting inside a finished item.
- **Decision**: none needed. The inputs are the author's to supply, not a session's to invent.

## What is still owed

`20-27` closed with two boxes unmet and said so plainly: *"the mechanism exists and is merged. **No
tenant has been created yet**, and the owner's first sign-in — the whole point — is still owed."*
Three days later that is still true, and nothing has removed the need.

- **A tenant exists in `ago_calendar` on the live node.** `Ago.Calendar.Provisioner` is still on
  `main` and is still the only path to one. It has deliberately no input for a Keycloak subject, so it
  cannot invent an identity; it takes the shop's real name and the owner's real email, and those are
  inputs the author supplies.
- **That owner signs in and reaches a screen with their own data on it.**

## These are one item, not two

Neither is worth anything alone. A row in `ago_calendar` that nobody has ever signed in against
proves the `INSERT` ran and nothing else, and `20-27` already named the reason: *"every layer beneath
it has been proven individually, and today has repeatedly shown that is not the same thing."* One
promise, landing green as a whole.

## One thing changed since `20-27` was written

**The screen is not this product's own console any more.** `22-06` retired
`ago-calendar-console` and moved the five surviving screens into `ago-console` at
`office.reserve-me.ru`. So the sign-in goes through the `ago-console` client, and the calendar
permissions come from the account side — which is why the second half of this is entangled with
`22-16`'s projection and with `22-28`, the count that was never taken.

`22-06`'s own first Done-when is this same wall seen from the other side, and it is settled `[~]`
there rather than met: every mechanical part proven — `office.` serves, its bundle carries the
deployed commit, the calendar screens are green in the gate — and *"what no check replaces is a human
reaching them signed in."*

## Done when

- [x] A tenant exists in `ago_calendar` on the live node, created by the system rather than by
      **Proven 2026-09-08.** `ago_calendar` holds exactly one tenant, `01a06262-d4f0-7fb6-94e0-9ff702db8a43`, "АГО тест теннант", created 06:17:47 UTC by the platform owner's grant — auto-provisioned by `RegisterChatModuleHandler`, not typed. `enabled_modules` carries the matching row with `granted_by_owner = t`.
      hand-written SQL.
      **Amended 2026-09-07.** This box named `Ago.Calendar.Provisioner` as the mechanism, and that
      wording is stale: `22-17`/`adr/0098` shipped after `20-27` was written and made
      `RegisterChatModuleHandler` **auto-provision a missing `Tenant`** via
      `Tenant.AutoProvisionForChatModule` the moment a platform owner grants the calendar module to a
      site, with `TenantId` set to the site's own account id. So the first calendar tenant now comes
      into existence as a side effect of the grant `23-65` built.
      The standalone tool is also the harder path today rather than the sanctioned one: `ago-deploy`
      carries no Job or manifest that runs it in-cluster at all. The requirement the box was written to
      express — *by the system, not by somebody typing SQL* — is unchanged and is what it now says.
- [~] Its owner signs in through the `ago-console` client and reaches a calendar screen showing that
      **Not reached, and blocked on `23-102`.** The owner signed in and got a truthful refusal: their account holds both seeded roles and neither carries a calendar permission, because `22-05` added them to the seeded sets and roles are seeded once at registration. Four of ten sites on the stand are in that state.
      A second obstacle sits behind it and would have stopped the same attempt anyway: `worker_quota` is **0** for this tenant, so even with the permission there is no worker to show. Raising it is `23-66`'s own route, a separate grant of a quantity.
      tenant's own data — not a fixture, and not an empty state that would look identical if the
      account did not exist.
- [x] Whatever it took is written down where the next tenant's setup will look for it, so the second
      Written into `docs/runbooks/module-grant-and-revoke.md` — the grant, the entry point, and the two things that stop a tenant using what was granted.
      one is a procedure rather than a rediscovery.
      What it will say differs from this item's original assumption: not *run the provisioner*, but
      *grant the calendar module to the site*, plus `23-92`'s entry-point value and whichever way
      `23-93` was decided.

## Out of scope

- **Self-service signup.** Still the larger item `20-27` deliberately declined to rush; this remains
  the one-shot admin path.
- Fixing anything the sign-in turns up. If it breaks, that is a finding and gets its own number —
  this item is the act of trying, and the trying is what has never been done.
