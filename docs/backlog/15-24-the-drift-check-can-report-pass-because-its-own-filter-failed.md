# the drift check can report PASS because its own filter failed

- **Stage**: 15
- **Status**: done (2026-09-07), `ago-deploy#160`. Filed and closed the same morning it was found.
- **Depends on**: nothing. `15-21` built the script; this is a hole in it.
- **Found**: 2026-09-07, reading `check-manifest-drift.sh` while doing `15-23`.

## What is wrong

`check-manifest-drift.sh`'s header promises it never folds an unanswerable comparison into a `PASS` —
an unreachable cluster reports `UNKNOWN`, and that part is real and demonstrated.

**But the promise only covers the cluster being unreachable.** The script runs under `set -uo
pipefail` and **not** `-e`. Two of its internal steps have no failure check of their own: the `awk`
that keeps only Deployments and NetworkPolicies, and the `sed` that normalises image tags against what
is running.

If either failed, `$filtered` would be empty, and `kubectl diff` against an empty manifest reports **no
difference** — which the script then prints as `PASS`. A tool failure would be indistinguishable from a
clean cluster.

The probability is low. The consequence is the exact thing the script exists to prevent, arriving
through the script itself.

## Why it is worth a number

`15-21` was filed because a deploy said nothing about a change it could not deliver. A `PASS` produced
by a broken filter is worse than silence: silence prompts somebody to look, and a green line stops
them.

`kubectl kustomize` and the empty-`sed_script` case **are** checked explicitly — so the discipline is
already in the file, applied to two steps out of four. That is what makes this an omission rather than
a design choice.

## A second, smaller thing found at the same time

**Every path through the script ends in `exit 0`**, including `DRIFT` and the internal-error branch.
So the `|| true` on both callers is currently decorative — the script cannot make a caller see a
non-zero status today. That is consistent with "advisory, never fatal" and is not itself a defect, but
it means the callers' `|| true` documents an intent the script does not currently test. Decide whether
the script should exit non-zero on `DRIFT` and let the callers keep swallowing it (so the intent is
real and the behaviour is deliberate), or say plainly in the script that its exit code is always zero.

## Scope

- Every internal step that can produce an empty or partial manifest fails loudly, as `UNKNOWN`, rather
  than flowing into a comparison that will find nothing.
- Shown biting: break the filter deliberately, and see `UNKNOWN` rather than `PASS`.
- Settle the exit-code question above, either way, in the script's own text.

## Done when

- [x] A failure inside the script reports `UNKNOWN`, never `PASS`, and is shown doing so — for the
      `awk` filter and the `sed` normalisation separately, and re-proven at landing against the
      **old** script, which prints `PASS` and exits 0 under the identical broken `awk`.
- [x] The exit-code intent is either implemented or stated — implemented: `PASS` 0, `DRIFT` 1,
      `UNKNOWN` 2, matching `check-theme-tokens.sh` and `deploy.sh` in the same directory. Neither
      caller changes; advisory-never-fatal is `adr/0144`'s decision. The `|| true` now swallows a
      real status rather than one that could never have been anything else.

## Out of scope

- The cluster half of the check, which has never run against a real API server and is `15-21`'s own
  named gap rather than this item's.
