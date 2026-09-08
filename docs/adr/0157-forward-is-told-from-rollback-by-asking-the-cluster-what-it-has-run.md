# ADR-0157: Forward is told from rollback by asking the cluster what it has already run

- **Status**: Accepted
- **Date**: 2026-09-08
- **Stage**: 23
- **Amends**: `adr/0144`'s companion guard from `22-24` — narrows what it refuses, without weakening it.

## Context

`apply-demo.sh` compares the committed manifest's pinned image tags against what the cluster is
running, and refuses when the manifest names a tag nothing is running. That guard exists for a real
and expensive incident shape: `redeploy.sh` moves the cluster forward with `kubectl set image` and
edits no file, so the committed manifest is then *behind* the cluster, and the next innocent
`apply -k` silently rolls production back.

**The comparison cannot tell that case from its opposite.** A manifest deliberately bumped to freshly
published CI images is also "a tag nothing is running" — and that is a roll-*forward*, the ordinary way
this environment is meant to be updated. Both look identical to a set difference.

So the only escape hatch, `--force-rollback`, was also the only way to perform an ordinary forward
deploy. On 2026-09-08 a deploy of three repositories' new builds had to be spelled with that flag.

**Why the naming is a defect and not a matter of taste:** shell history and runbook transcripts are
what somebody reads while reconstructing an incident. A line reading `./apply-demo.sh --force-rollback`
in the history of a day when nothing was rolled back is a false statement in the most-consulted record
there is. The guard's whole value is that a human stopped and thought; a flag that misdescribes what
they decided spends that value immediately.

## Decision

**The script asks the cluster which direction the apply is, instead of guessing from a set difference.**

An image the cluster has run before is recorded in a ReplicaSet. An image it has never run is not.
That is exactly the distinction:

- **A tag never seen in ReplicaSet history is a roll-forward.** Reported, and applied with no flag.
- **A tag found in ReplicaSet history is a rollback.** Refused unless `--force-rollback` is given —
  which is now a truthful name, because it is only ever reached when a rollback was actually detected.

An apply carrying both is refused on the rollback half, and says so.

`--check-only` is added alongside: it runs the direction check and stops, touching nothing. The guard
had never been provable before, because the only way to exercise it was to deploy.

## Consequences

**Ordinary forward deploys stop lying in the record**, and need no flag at all. The second flag the
obvious fix would have added is unnecessary: one flag, correctly named, for the one case that needs a
decision.

**The guard is now demonstrable.** All five behaviours were proved against the live cluster with
nothing applied — unchanged manifest, forward-only, rollback-only, rollback with the flag, and a mixed
apply refusing on its rollback half.

**It no longer depends on anything outside the cluster.** In particular it does not consult a git
checkout, which matters: the node's checkouts drift silently between deploys and have been 85 commits
behind before now.

**The hole, stated plainly: ReplicaSet history is bounded by `revisionHistoryLimit`.** A rollback to a
tag older than the retained revisions reads as "never seen" and passes without the flag.

**That is the right place for the hole to be**, and the argument is worth keeping. The accident this
guard exists for is a redeploy leaving the manifest a step or two behind — whose tags are by
construction *recent*, and therefore inside the retained history. A rollback past ten revisions is
deliberate archaeology, not a slip, and somebody doing it is not the person the guard protects.

**Two scripts must now stay in step on a second thing.** `check-manifest-drift.sh` shares this guard's
vocabulary and its advice text told the operator that apply refuses "while the committed pins are
behind the cluster"; that sentence is no longer true and was corrected in the same change. The two
already had to share an image-name regex (`15-22`); this adds a second coupling, and both are noted in
each file.

## Alternatives considered

**A second flag — `--roll-forward` beside `--force-rollback`.** One line, no new logic, and the
history would read correctly. Rejected because it leaves the operator to classify the deploy
themselves at exactly the moment they are least able to: the state that produces an accidental
rollback is one where the operator believes they are moving forward. A flag cannot help somebody who
is already wrong about the direction.

**Ask git whether the manifest's tag is a descendant of the running one.** The most precise answer in
principle, and it was declined on a concrete failure mode rather than on cost: it needs the node's
checkouts present and fetched, and a stale checkout makes a legitimate forward tag look "not a
descendant". Failing closed there refuses correct deploys; failing open there discards the guard. A
force-push or a rebuilt branch produces the same ambiguity.

**Change the order of operations instead** — deploy first, commit the tags afterwards, so the manifest
is never ahead. Cheapest of all, and it is what `redeploy.sh`'s own note already advises. Rejected
because it removes the ability to describe an intended state *before* applying it, which is the entire
point of a committed record: the tag bump becomes a reviewable pull request describing what is about to
run, rather than a note about what already did.
