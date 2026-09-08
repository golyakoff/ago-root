# what the deploy path does when an image is simply not there

- **Stage**: 23
- **Status**: ready — **and it opens with a choice, not with work**
- **Depends on**: nothing. Carried out of `23-98`, whose first box shipped and whose other two are these.
- **Found**: 2026-09-08, carried out at landing rather than left implied by a closed ticket.

## What `23-98` established, and what it left open

`23-98` found both migrator images gone: built locally on the node, never pushed anywhere, and
evicted by containerd's image garbage collector when the disk crossed its 85% threshold. It fixed the
cause of the pressure — a 53.8 GB BuildKit cache, now pruned with a retention window after every
import — and it fixed the drift that let one image be built and never imported. The node sits at 36%.

**Neither of those answers what happens the next time an image is missing**, and the next time is not
hypothetical: the eviction threshold is a property of the node, not of that week's disk usage.

## The first question: an evicted local-only image

An image built on the node and never pushed has no source to be pulled back from. When GC takes it,
the artifact is gone, and the first symptom is a `Job` in `ImagePullBackOff` — a message about a
registry, for an image that was never in one, which is why it read as a network problem for a while.

Three readings, and a fourth the implementing worker proposed:

1. **Rebuild on demand.** The deploy path notices the image is absent and builds it. Simplest, and it
   keeps the current "the node builds its own migrators" model — but it makes a deploy's duration
   depend on what GC happened to take, and a rebuild is only reproducible if the checkout is at the
   right commit, which `redeploy.sh` pulls and `deploy.sh` does not.
2. **Publish the migrators to the registry**, like every other image since `15-06`. Then eviction is
   ordinary and recoverable, and `imagePullPolicy` does the work. Costs two more CI publish jobs and
   makes the migrators' provenance identical to the hosts', which is arguably where it belonged.
3. **Pin the images against GC** so containerd will not evict them. Smallest change and directly
   targets the failure, but it makes the disk-pressure story worse rather than better: pinned images
   are exactly the ones GC cannot reclaim when the node is genuinely full.
4. **Accept it and detect it**, treating an absent image as an expected state the deploy path reports
   clearly instead of one it prevents. Cheapest, and it converts a confusing symptom into a plain
   one — but it leaves a human doing the recovery every time.

## The second question: a Job that can never start

When the migrator's image was gone, its `Job` sat in `ImagePullBackOff` indefinitely. `apply-demo.sh`
reads `.status.active` and **refuses to delete a Job with active pods**, which is right — it exists so
a running migration is never killed. A pod stuck pulling an image that does not exist is active by
that test and never stops being active, so the refusal is permanent and the next apply is blocked by
a migration that is not running.

**These two are one promise, not two tickets.** They are the same sentence — *what the deploy path
does when an image is missing* — and any fix for the first changes what the second should do. Splitting
them would leave each half unable to close green on its own, which is rule 15's own test.

## Where this is likely to go wrong

- **Distinguishing "stuck" from "slow" is the whole difficulty.** A migration against a large table is
  legitimately active for a long time, and the guard exists because killing one is worse than waiting.
  Whatever replaces "has active pods" has to tell a pod that is working from a pod that cannot start —
  the container's own state (`ImagePullBackOff`, `ErrImagePull`) rather than the Job's, most likely.
- **Do not make the refusal conditional on a timeout.** A migration that takes longer than the timeout
  is precisely the case the guard was written for.
- **`23-98`'s import fix reduces how often this bites but does not close it**, because eviction is not
  caused by anything the import loop does.

## Done when

- [ ] The reading for an evicted local-only image is chosen by the author and recorded.
- [ ] A `Job` that can never start does not block the following apply, and a `Job` that is genuinely
      running still does.
- [ ] Whatever distinguishes the two is proved against both cases, not only the broken one.
