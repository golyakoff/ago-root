# Teach `redeploy.sh` about the calendar

- **Stage**: 20
- **Status**: ready
- **Found**: 2026-09-03, landing `20-25`. The worker flagged the missing migrator step; checking it
  independently showed the gap is wider — the script builds no calendar image at all.

## The gap

`k8s/redeploy.sh` — the build-on-the-node path — handles AGO Chat only.

```
line 106:  for img in ago-chat-api ago-chat-worker ago-chat-webhooks ago-chat-migrator; do
line 158:  kc delete job ago-chat-migrator ...
line 164:  kc wait --for=condition=complete job/ago-chat-migrator ...
```

No calendar image is built, none is imported into containerd, and **`ago-calendar-migrator` never
runs**. There is no calendar step anywhere in the script.

## Why it matters

`20-25` gave the calendar a deploy path and a scoped rollback, but both move *already-published*
images. `redeploy.sh` is the other path — a hotfix that has not been merged, or a cluster rebuilt
ahead of CI — and on that path the calendar does not exist. Running it today builds and rolls the
three chat hosts and silently leaves the calendar on whatever it was, schema included.

**The migrator half is the sharp end.** `8-08`'s rule is that the migrator's image moves with the
hosts and never independently. For AGO Chat that rule is *enforced by this script*. For AGO Calendar
it is enforced by a comment in `kustomization.yaml` asking a human to remember — the same rule with
none of the mechanism, on a product that is now live.

`Ago.Calendar.Migrator` has no `--down` (`adr/0056`), and `20-14` already merged a destructive
migration dropping `calendars.buffer_minutes`. A build-from-source path that skips the migrator
entirely is how a host meets a schema it does not match.

## Why it is not part of `20-25`

Different promise. `20-25` is "the calendar can be moved to a published build and moved back"; this is
"the calendar can be built from source on the node like everything else". Each lands green on its own,
and `20-25` closed honestly without this.

## What this must produce

- `redeploy.sh` builds, imports and rolls the calendar hosts and console alongside the chat ones — or
  states in the script why it deliberately does not.
- **`ago-calendar-migrator` runs before the calendar hosts**, in the shape the chat migrator already
  has: delete the Job, apply it at the built tag, wait for completion, print its logs on failure.
- The ordering rule holds across both products rather than being restated per product.

## Done when

- [ ] `./redeploy.sh` on the node leaves the calendar running the commit it just built, proven by
      `/healthz/version` — which `20-24` made possible.
- [ ] The calendar migrator runs on that path and its failure fails the script — proven by making it
      fail, not by reading it.
- [ ] `docs/runbooks/redeploy.md`'s "Building from source on the node" section stops describing a
      chat-only procedure.
