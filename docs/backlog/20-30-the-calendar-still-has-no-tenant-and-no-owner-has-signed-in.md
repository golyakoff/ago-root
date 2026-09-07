# AGO Calendar still has no tenant, and nobody has ever signed in to one

- **Stage**: 20
- **Status**: ready
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

- [ ] A tenant exists in `ago_calendar` on the live node, created through `Ago.Calendar.Provisioner`
      rather than by hand-written SQL.
- [ ] Its owner signs in through the `ago-console` client and reaches a calendar screen showing that
      tenant's own data — not a fixture, and not an empty state that would look identical if the
      account did not exist.
- [ ] Whatever it took is written down where the next tenant's setup will look for it, so the second
      one is a procedure rather than a rediscovery.

## Out of scope

- **Self-service signup.** Still the larger item `20-27` deliberately declined to rush; this remains
  the one-shot admin path.
- Fixing anything the sign-in turns up. If it breaks, that is a finding and gets its own number —
  this item is the act of trying, and the trying is what has never been done.
