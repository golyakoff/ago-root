# the drift check normalises away the only drift that actually happens

- **Stage**: 23
- **Status**: done — `ago-deploy#199`. Live-cluster confirmation of the DRIFT case (rather than the
  local `docker-desktop` proof this PR shipped with) is carried to the redeploy this item is batched
  with.
- **Depends on**: `15-21` built the check; `adr/0144` is its decision. This is the gap that item's own
  second Done-when names and could not close.
- **Found**: 2026-09-07, by watching the check pass on a cluster that had drifted eleven ways.

## What happened, exactly

`check-manifest-drift.sh` renders the demo overlay, **rewrites every image tag in the rendered
manifest to whatever tag is actually running**, and then diffs. The normalisation is deliberate and
`adr/0144` explains it: `deploy.sh` moves images imperatively, so between a deploy and the commit that
records it, tags are *meant* to disagree, and a check that fired on that would fire on every deploy.

The consequence is the part nobody had seen until today. On 2026-09-07 the committed manifest pinned
`1af00f8` for four chat images, `3137f98` for the console and `f97ab10` for three calendar images,
while the cluster ran `255cbea`, `971e0f6` and `b82e084`. **Eleven of twelve `newTag` values were
stale.** The check ran, on the real cluster, at the end of a real redeploy, and printed:

> `PASS - the manifest and the cluster agree (Deployments and NetworkPolicies, image tags aside).`

Which is true, and is the problem. *Image tags aside* is where all of the drift was.

## Why this is not a bug in `15-21`

`15-21` delivered what it promised: a manifest change that a deploy cannot carry is now reported, and
the check is wired into both entry points. Its **second** box — *the pins and the cluster cannot drift
apart silently* — is the one this item carries out, because closing it needs something the tag
normalisation structurally cannot provide.

**And the normalisation is not simply wrong.** Removing it would make the check fire at the end of
every single deploy, which is the fastest known way to make a check ignored. The question this item
has to answer is narrower and harder: *when are tags meant to disagree, and when have they merely been
left disagreeing?*

## The shape of an answer, not a decision

Three readings, none chosen here:

- **Time.** Tags may disagree during a deploy and not an hour later. Needs something durable to
  compare against, and a clock in a check is a new failure mode.
- **The next run.** A deploy records the tags it used somewhere the *next* deploy reads, so a second
  deploy that finds unrecorded tags from the first says so. Cheap, and catches exactly today's case,
  which was two deploys and no commit.
- **The apply side only.** Leave the deploy path silent and put the whole burden on `apply-demo.sh`,
  which already refuses a backwards apply (`22-24`). This is close to today's real safety: that guard
  is why today's stale manifest was harmless, not the drift check.

## What is now known that was not

- **The check works against a real API server.** `15-21`'s and `15-23`'s third boxes were held open on
  exactly that doubt; it ran twice today and returned a correct `PASS` both times. That doubt is
  settled, and only this gap remains.
- **`22-24`'s rollback guard is the mechanism that actually protects the stand**, not the drift check.
  It correctly did not fire on 2026-09-07 because the cluster and the manifest agreed at apply time —
  the eleven-way drift was created by the two redeploys that came *after* the apply.

## Answered, 2026-09-13

**Reading B — the next run.** A deploy records what it actually rolled out somewhere durable; the next
deploy (or the next drift-check run) reads that record and says so if what's currently running was
never recorded as committed. Chosen over the other two, for stability specifically:

- **A (time-based) was rejected as a net addition of instability, not a fix.** It still needs the same
  durable record B needs — there is no way to say "this tag has been running longer than expected"
  without persisting when it started — and it adds a threshold on top that has to be tuned, tripping on
  an ordinary slow deploy or a maintenance window. It pays B's own cost and adds a second, flakier one.
- **C (apply-side only, demote the check) was rejected as leaving the actual problem unaddressed.**
  `22-24`'s rollback guard is real protection, but it only refuses a *backwards* apply — drift between
  two forward deploys with no commit between them, exactly 2026-09-07's own case, can still accumulate
  silently and indefinitely under C. Demoting the check to informational is an honest description of
  what protects the cluster today; it is not a check that notices what this item exists to notice.
- **B catches exactly the observed failure, deterministically, with no new failure mode of its own** —
  no clock, no threshold, nothing to tune. It is a pure addition: the tag normalisation, and `apply-
  demo.sh`'s own existing rollback guard, are both unchanged by this.

## Done when

- [x] Tags left unrecorded after a deploy are noticed by something, and the item says which of the
      three readings above it took and why. — **reading B, see Answered above.** "Noticed by
      something" is not yet built; the remaining two boxes cover that.
- [~] Whatever notices is shown noticing, against a real recorded-versus-running gap. — **proven
      against a real Kubernetes API server (a local `docker-desktop` cluster, scratch namespace and
      overlay), not yet against the live demo cluster.** A simulated two-deploy sequence with no
      commit between them reproduced 2026-09-07 exactly and was caught. The live-cluster confirmation
      is carried to the redeploy this item is batched with.
- [x] The normal case — a deploy in progress — stays quiet, so the check does not become one more
      banner nobody reads. — proven live: an ordinary single deploy followed by committing the moved
      tags produces no warning on the next run.
