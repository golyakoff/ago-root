# deploy.sh has the same blind spot 15-21 just closed in redeploy.sh

- **Stage**: 15
- **Status**: ready
- **Depends on**: `15-21` — hard. This is that item's mechanism pointed at the other script, and
  filing it before `15-21` lands would mean building against something not yet there.
- **Found**: 2026-09-07, while building `15-21`.
- **Decision**: none needed for the gap. One question is named below.

## What is actually true

`15-21` gave `redeploy.sh` a drift check because it moves images with `kubectl set image` and never
applies manifests. **`deploy.sh` has exactly the same shape and exactly the same gap**, and since
`15-06` it is the more commonly used of the two.

So the incident `15-21` closes — a manifest change correct in the repository, absent from the cluster,
crash-looping a host on the next roll — remains fully reachable through the path people take more
often. That is the part worth being uncomfortable about: the fix landed on the less-travelled road.

## Why it was left out

`15-21`'s own text named `redeploy.sh` and `apply-demo.sh` and nothing else, and widening a ticket to
a second script mid-flight is what `CLAUDE.md` rule 15 asks not to be done. So it was reported rather
than absorbed. This is the number that carries it.

## The question inside it

**Whether `deploy.sh` should call the same check or a different one.** They are not obviously the same
situation: `deploy.sh` builds from a checkout and may legitimately run against a cluster that has never
had this overlay applied at all, where "drift" is not drift but a first install — and a check that
shouts on a first install is the crying-wolf failure `adr/0144` argues against. Reusing the script and
reusing its *message* are separate choices.

## Scope

- `deploy.sh` reports manifest drift it cannot deliver, on the same terms `adr/0144` sets: never a
  false PASS, never fatal, and never noisy on the ordinary case.
- Whatever the answer to the question above, write it down — including if the answer is that
  `deploy.sh` genuinely does not need it, which is a legitimate outcome and would close this as
  not-planned rather than as done.

## Done when

- [ ] A manifest change that `deploy.sh` cannot deliver is reported by `deploy.sh`.
- [ ] A first install, and an ordinary image bump, both stay quiet.
- [ ] The reuse-or-not question is answered in the change rather than implied by it.
