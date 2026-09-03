# Give the calendar hosts a deploy path and a rollback path

- **Stage**: 20
- **Status**: ready
- **Found**: 2026-09-03, landing `20-20`. The runbook was being updated to describe the newly deployed
  calendar hosts, and the scripts turned out not to know they exist.

## The gap

`k8s/deploy.sh` and `k8s/rollback.sh` do not mention the calendar at all — zero occurrences in either.

```
HOSTS=("ago-chat-api:api" "ago-chat-worker:worker" "ago-chat-webhooks:webhooks")
FRONTENDS=("console:ago-console" "demo-shop1:ago-demo-shop1" "demo-shop2:ago-demo-shop2" "landing:ago-landing")
```

Five .NET hosts run in this cluster and three are listed; five frontends are served and four are
listed. `ago-calendar-api`, `ago-calendar-worker`, `ago-calendar-migrator` and `ago-calendar-console`
are reachable only through `kubectl apply -k` against whatever the overlay happens to pin.

## Why it matters

**No version-pinned deploy.** Moving the calendar to a new build means editing three image pins by
hand and applying. `deploy.sh` exists precisely because that kept going wrong — its own header records
a console bundle a week stale with nobody able to say which commit was in it. The calendar is in that
state now.

**No rollback at all**, and this is the serious half. `rollback.sh` undoes one revision on "all three
hosts", deliberately and by name — its no-argument form is meant to be the one thing with no decision
in it during an incident. If a calendar deploy goes bad there is no scripted way back: it is
`kubectl rollout undo` per Deployment, by hand, while remembering that the migrator's image moves with
the hosts and never independently (`8-08`).

The calendar went live on 2026-09-03, so this gap is open on a running product rather than waiting for
a first deploy.

## The decision this needs

Appending two entries to an array is not the answer, because `rollback.sh`'s narrow scope is
deliberate:

- **One `rollback.sh` for both products, or a separate scope for the calendar?** Rolling back AGO Chat
  because AGO Calendar is broken is a bad trade, and so is the reverse.
- **The migrator has no equivalent in the chat rollback path today.** `8-08`'s rule has to hold in
  reverse too, and a rollback that leaves a newer schema behind is its own failure mode.

State the choice and what it replaced.

## Done when

- [ ] `deploy.sh` can move the calendar hosts and console to a named commit, as it does the chat ones.
- [ ] `rollback.sh` has a defined, documented behaviour for the calendar — "included", "separate
      scope" or "deliberately excluded, here is why" are all acceptable; silence is not.
- [ ] The migrator's coupling holds in both directions, proven by performing a rollback rather than by
      reading the script.
- [ ] `docs/runbooks/redeploy.md` stops saying "three hosts" and "four frontends" where it now means
      five and five. (Its calendar section, added by `20-20`, describes the gap in the meantime.)
