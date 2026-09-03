# Make `apply -k` survive a migrator pin bump

- **Stage**: 8
- **Status**: ready
- **Found**: 2026-09-03, immediately after pinning the deployed builds. `kubectl diff` reported a
  difference, the difference turned out not to exist, and the real message was this.

## What happens

A `Job`'s `spec.template` is immutable. The migrator images move with their hosts (`8-08`), so the
moment a host pin changes, the recorded overlay describes a Job Kubernetes will not update:

```
The Job "ago-chat-migrator" is invalid: spec.template: ... field is immutable
```

`kubectl apply -k k8s/overlays/demo` fails, and so does `kubectl diff -k`. Both stay broken until
somebody deletes the completed Job by hand.

## Why it is a ticket rather than a note

The trap sits in the seam between two things that are each correct on their own:

- `deploy.sh` uses `kubectl set image`, edits no file, and **closes by telling the operator to update
  the `newTag` values and commit** — exactly right, because the overlay is the record of what this
  environment is supposed to run, and `smoke.sh` compares the two.
- Following that instruction is what breaks the next `apply`.

So the documented happy path leads directly into the failure. And the failure presents as a wall of
serialised pod spec ending in `field is immutable`, which reads like a manifest bug rather than
"delete a Job that finished". `redeploy.sh` already does the right thing — `kc delete job` before
applying — so the knowledge exists in this repository; it is simply not on the path anybody follows
after a `deploy.sh`.

## Options

1. **A thin `apply-demo.sh`** that deletes completed migrator Jobs and then applies, so the ordinary
   path cannot hit this. The logic already exists in `redeploy.sh` and would be lifted, not invented.
2. **Leave `apply -k` alone and document it** in `redeploy.md`, beside `deploy.sh`'s own closing note —
   where somebody who just followed that note is actually standing.
3. **`ttlSecondsAfterFinished` on both Jobs**, so a completed migrator removes itself and the next
   apply recreates it. Cheapest, and it changes behaviour rather than describing it.

Option 3 has a cost worth naming rather than discovering: a Job that deletes itself takes its logs
with it, and the migrator's logs are what a failed migration leaves behind to read. `redeploy.sh`
prints them on failure precisely because they matter.

## Done when

- [ ] `apply -k` succeeds against a freshly bumped migrator pin — proven by bumping one and applying,
      not by reading.
- [ ] The chosen shape is stated with what it replaced.
- [ ] A failed migration still leaves something to read.

## Out of scope

- `20-26` — `redeploy.sh` not knowing about the calendar at all. Different path, different promise.
