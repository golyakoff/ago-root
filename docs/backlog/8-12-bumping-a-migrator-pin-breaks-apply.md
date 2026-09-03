# Make `apply -k` survive a migrator pin bump

- **Stage**: 8
- **Status**: done (2026-09-03) - `ago-deploy#130`
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

- [x] `apply -k` succeeds against a freshly bumped migrator pin - proven by bumping one and applying,
      not by reading. — reproduced on the local `docker-desktop` cluster in a throwaway namespace:
      the `field is immutable` refusal verbatim from the runbook's own command, then `apply-demo.sh`
      clearing it with both migrations completing for real against a live Postgres (54 chat, 11
      calendar), and `kubectl diff -k` clean afterwards.
- [x] The chosen shape is stated with its alternative. — a thin `apply-demo.sh` lifting
      `redeploy.sh`'s own fix. Two alternatives were evaluated rather than skipped: a separate
      kustomization for the Jobs alone (already tried and abandoned - the path-traversal restriction
      is recorded in `redeploy.sh`), and `metadata.generateName` (which would leave the Job with no
      stable name for `redeploy.sh`'s `wait --for=condition=complete` to address).
- [x] A failed migration still leaves something to read. — yes, and this is where the item's own
      framing turned out to be wrong: see below.

## Outcome

Closed 2026-09-03, `ago-deploy#130`.

**The item was filed on an incorrect assumption, and the correction is the useful part.** It offered
`ttlSecondsAfterFinished` as the cheap option and warned that it would cost the logs. Both Jobs
**already carry `ttlSecondsAfterFinished: 3600`**, from `8-08`/`8-10` - so the option was not
available, it was already taken, and the real question was the opposite one: whether to *shorten* it.

The answer is no, for the reason the item guessed at from the wrong direction. The failure exists only
inside that hour - which is exactly when it happens, right after the tag bump `deploy.sh` asks for -
and closing the window by shrinking the TTL would trade directly against why an hour was chosen: a
Job that deletes itself takes a failed migration's logs with it before anyone is guaranteed to have
read them. Left unchanged, with the argument recorded in both manifests rather than only the
conclusion.

`apply-demo.sh` reads `.status.active` and refuses to delete a migration still running, rather than
assuming one is finished by then. The narrow gap it cannot close - a Job created but not yet
reporting an active pod - is stated in the script.

### Scope boundary, named rather than discovered later

It covers `overlays/demo` only. The `local` overlay hits the identical refusal, and `k8s-local.md`
already carried the manual form of this fix - a third place the knowledge sat before this item
noticed the demo path had none. Widening the script to take an overlay argument is a small follow-up,
not filed, because the local path is documented and lower-stakes.
