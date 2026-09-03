# Give the calendar hosts a deploy path and a rollback path

- **Stage**: 20
- **Status**: done (2026-09-03) — with its third Done-when honestly unmet: no rollback has been
  performed, because there is not yet a second calendar image to move between.
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

- [x] `deploy.sh` can move the calendar hosts and console to a named commit, as it does the chat ones.
      — `./deploy.sh calendar <sha>` moves the api and worker together; `calendar-console` is one more
      `FRONTENDS` entry, because one static bundle addressed by name is exactly what that mechanism
      already models.
- [x] `rollback.sh` has a defined, documented behaviour for the calendar. — **separate scope.** The
      two products fail independently, so rolling one back for the other's incident is a bad trade in
      both directions. The bare no-argument form still means the three chat hosts and nothing else,
      verified rather than assumed: `TARGETS` defaults to the chat deployments and calendar is
      reachable only by name.
- [ ] The migrator's coupling holds in both directions, proven by performing a rollback rather than by
      reading the script. — **not met, and it cannot be yet.** There is no second calendar image to
      move between in recorded revision history. What was verified instead: every refusal path (a
      non-SHA tag, an unknown component, a bad tag under the new scope) exits before any `kubectl`
      call, and every dispatch shape selects the right deployments.
- [x] `docs/runbooks/redeploy.md` stops saying "three hosts" and "four frontends" where it now means
      five and five.

## Outcome

Closed 2026-09-03, the day AGO Calendar went live.

**The decision was the work.** `rollback.sh`'s narrow no-argument scope is deliberate — during an
incident it must stay the one thing with no decision in it — so the choice was between widening it
and giving calendar a name of its own. A separate scope won because the products share nothing that
would make a joint rollback correct: separate databases, separate deployments, no shared failure
domain beyond one Postgres instance and one Keycloak realm.

**Checking the migrator instead of assuming turned up something.** `Ago.Calendar.Migrator` has no
`--down`, matching `adr/0056` — but `20-14` already merged a destructive migration dropping
`calendars.buffer_minutes`. That is harmless today only because it is baked into `ee3b38a`, the first
calendar image this cluster ever ran, so nothing in revision history predates it. Both scripts now
say so, including where it stops being true: naming an explicit pre-`ee3b38a` tag.

### What this revealed as undone

- `20-26` — `redeploy.sh`, the build-from-source path, knows nothing about the calendar. It builds no
  calendar image and never runs `ago-calendar-migrator`, so `8-08`'s coupling is held there by a
  comment asking a human to remember.
