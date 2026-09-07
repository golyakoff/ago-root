# ADR-0144: `redeploy.sh` warns on manifest drift it cannot apply; it does not apply manifests itself

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 15
- **Specifies**: `backlog/15-21-a-redeploy-leaves-the-manifest-behind-and-nothing-says-so.md`

## Context

`redeploy.sh` (and `deploy.sh`, the more commonly used path since `15-06`) move the cluster forward
with `kubectl set image` alone. Neither edits a file, neither applies the overlay. That is
deliberate — `redeploy.md`'s own "What it does not apply: manifests" section has said so since it was
written — and it means a change to a Deployment's env, probe, resources, replica count, or a
NetworkPolicy's spec, committed to `ago-deploy` but never separately applied, does not reach the
cluster through either script, however many times it is run.

That gap was theoretical until `23-45`: a startup validation was added to `Ago.Chat.Api` together
with the manifest configuration that satisfies it. The configuration was correct in
`overlays/demo/kustomization.yaml` and absent from the cluster. The next `redeploy.sh` moved the
image forward and crash-looped the API. Nothing was down only because the old ReplicaSet kept
serving — ordering luck, not a property of either script.

`apply-demo.sh` (`8-12`, `22-24`) is the tool that *does* apply the overlay, and it already refuses
correctly when the overlay's image pins are behind the cluster — exactly the state a redeploy leaves
behind until an operator commits the tags `redeploy.sh` prints at the end. That refusal is not this
item's to touch; it is the second half of the trap this decision has to avoid walking into.

## Decision

**`redeploy.sh` gains a drift check, not a manifest apply.** A new script,
`k8s/check-manifest-drift.sh`, runs as the last step of `redeploy.sh` (after the closing "commit
these tags" note, with its own exit code discarded) and:

- Renders the named overlay with `kubectl kustomize` and drops every `Job` document — the two
  migrators legitimately run a different image tag than the file between a redeploy and the operator
  committing it (`8-08`), and a `Job`'s `spec.template` is immutable, so a dry-run apply against a
  changed one does not report a diff, it errors.
- Rewrites every remaining image reference to whatever tag the same repository is running right now,
  read from the live Deployments — neutralising the one difference `redeploy.sh` already reports and
  `apply-demo.sh` already guards (`22-24`), so this check never fires on the routine, expected gap
  between "images moved imperatively" and "the file got committed."
- Runs `kubectl diff` against what remains (Deployments and NetworkPolicies only) and prints PASS,
  DRIFT with the diff, or UNKNOWN if the comparison itself could not be made — never folding "could
  not tell" into "clean."

It is advisory. A DRIFT banner tells the operator: commit the tags named above, then run
`./apply-demo.sh` — in that order, because `apply-demo.sh`'s own guard would otherwise refuse on the
still-uncommitted pins. `redeploy.sh`'s own exit code is unaffected either way: the deploy that
already happened (images moved, migrations applied, smoke green) does not become undone by a check
that runs after it, and a check that can only warn must never look like the thing it warns about.

## Consequences

- The failure `23-45` produced — a manifest change correct in the repository and silently absent from
  the cluster — is now named out loud at the end of every `redeploy.sh` run, for the two resource
  kinds most of that risk lives in (Deployments, NetworkPolicies).
- It costs a new script whose correctness this decision now depends on. `kubectl diff`'s three-way
  merge (against `kubectl.kubernetes.io/last-applied-configuration`) is what avoids false positives
  from server-defaulted fields; a bespoke structural comparison would have had to reinvent that, badly.
- **It still does not apply anything.** An operator who reads the warning and does nothing is exactly
  as unprotected as before this ADR — the check reports the fact, it does not act on it. That is
  accepted, not overlooked: see "redeploy.sh applies manifests too," below.
- **It covers Deployments and NetworkPolicies, not the whole overlay.** ConfigMaps, Secrets, Services,
  Certificates and the namespace itself can still drift unnoticed. Widening the comparison without a
  second incident to justify each addition is exactly the "generic check nobody can explain" this
  project's own `smoke.sh` argues against (see that script's own header).
- **`deploy.sh` has the identical blind spot and does not get this check.** It is the more commonly
  used path since `15-06`, and the same `kubectl set image`-only shape applies to it exactly as much
  as to `redeploy.sh`. Left out of this item's scope because the backlog item named `redeploy.sh` and
  `apply-demo.sh` specifically; extending the same check to `deploy.sh` is a small follow-up, not a
  reason to hold this one.
- **The check needs a reachable cluster to mean anything**, and was verified only against rendered
  manifests and fabricated fixtures standing in for live cluster state — never against a real
  `kubectl diff`. That verification gap is inherent to this item's own no-live-systems constraint, and
  is not closed by this decision; the commit-prep block names it as what remains to prove.

## Alternatives considered

- **`redeploy.sh` applies the overlay too**, becoming one operation. The straightforward fix, and the
  one item's own text raised first. Rejected because it makes every image roll a bigger action than
  the operator asked for: an `apply -k` pulls in whatever else has drifted into the file since the
  last deliberate apply, so a routine redeploy could also silently roll out an unrelated,
  half-finished manifest edit sitting in the tree — a hazard `redeploy.md`'s own existing text already
  names as the reason this was never done. It would also have to solve `apply-demo.sh`'s immutable-Job
  problem a second time, inside a script with a different failure-handling shape (`set -euo pipefail`
  across a much longer run, where an apply failing mid-script is costlier to reason about than at the
  end of a short, focused wrapper).
- **Invert the ordering: apply the overlay before moving images**, so the manifest becomes the source
  of truth and the images follow. Closer to correct in principle. Rejected without a prototype because
  it inverts the ordering `8-12` and `8-08` settled around migrator Jobs on purpose (migrations before
  hosts, images and manifest moving together) — re-deriving that ordering under "manifest first" is a
  bigger change than this item's own incident justifies, and the existing ordering has not caused a
  problem `23-45` didn't already predate.
- **A hand-rolled structural comparison** (walk both YAML trees, ignore a named allowlist of fields).
  Rejected in favour of `kubectl diff` specifically because of the false-positive hazard: a bespoke
  comparison has to independently rediscover every field the API server defaults, and getting that
  wrong produces exactly the "cries wolf, gets `--force`d past" failure mode this item's own brief
  warns about. `kubectl diff`'s three-way merge already solves it, for the price of needing a real
  cluster to run against at all.
- **Put the check in `smoke.sh` instead of `redeploy.sh`.** `smoke.sh` is genuinely where this project
  puts "what is actually true right now" (its own header), and it already does the analogous thing for
  image tags (binary-reported commit vs. running tag). Not chosen for scope discipline, not principle:
  `smoke.sh` is called from more places than `redeploy.sh` and reused by `deploy.sh` too, so putting a
  new, only-partly-proven check there risks failing (or, worse, silently degrading) an existing,
  trusted signal. `check-manifest-drift.sh` as its own script keeps the blast radius of "this check
  turns out to be wrong somewhere" to the one caller that opts into it.
