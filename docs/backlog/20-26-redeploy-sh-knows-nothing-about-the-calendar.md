# Teach `redeploy.sh` about the calendar

- **Stage**: 20
- **Status**: done (2026-09-03) — with both Done-when proofs demonstrated in a harness rather than
  on the node; the first real run is still owed.
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
      `/healthz/version` — which `20-24` made possible. — **not met.** The script has not been run on
      the node since it learned the calendar. Running it rebuilds and rolls every workload from
      source, which is a large action to take on a live demo for a verification nothing currently
      needs; deferred deliberately rather than forgotten.
- [x] The calendar migrator runs on that path and its failure fails the script — proven by making it
      fail, not by reading it. — proven in an instrumented harness, in **both** directions: a failing
      chat migrator or a failing calendar migrator stops the script, prints logs, exits 1, and the
      trace shows zero `set image` calls. Not proven against a real failing migration.
- [x] `docs/runbooks/redeploy.md`'s "Building from source on the node" section stops describing a
      chat-only procedure.

## Outcome

Closed 2026-09-03. `redeploy.sh` builds and imports both products, runs both migrators, and only then
moves any host.

**The implementation went further than the item asked, with a reason.** `8-08` requires each migrator
before its own hosts; what landed is *neither product's hosts move until both migrations succeed*.
The script already treats one run as moving the whole environment forward together, and the stronger
form means a failure in either migrator leaves both products untouched instead of half-moved.

The two migrator blocks became one `run_migrator` function rather than a second copy — everything in
it (delete first because the pod template is immutable, scope the apply with `-l app=<job>`, render
the overlay rather than the base file) is a property of *a* migrator Job, not of `ago-chat-migrator`.

**Found while landing this, on the node rather than in the code:**

- The node had **no `ago-calendar` or `ago-calendar-console` checkout at all**, so this script could
  not have run there whatever it said. Both cloned.
- Every other checkout was badly stale — `ago-chat` **85 commits behind**, `ago-console` 71,
  `ago-widget` 39, `ago-landing` 14. Brought to their tips, where they now match the deployed images
  exactly. Step 1 pulls five of the six, so most of that staleness self-corrects on a run.
- `ago-landing` is the sixth. Its commit is *read* but never *pulled*, which is `15-13`.
