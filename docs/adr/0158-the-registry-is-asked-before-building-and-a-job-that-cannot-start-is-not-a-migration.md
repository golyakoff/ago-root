# ADR-0158: The registry is asked before building, and a Job that cannot start is not a running migration

- **Status**: Accepted
- **Date**: 2026-09-08
- **Stage**: 23

## Context

On 2026-09-08 both migrator images were gone from the node — containerd's image garbage collector had
evicted them at its 85% disk threshold — and `23-98` recorded the diagnosis that they were *"built
locally, never pushed to a registry, so unrecoverable without another build"*.

**That diagnosis was an inference, and it is false.** Checked rather than reasoned:

- Both backend CI workflows push their migrator on every commit to `main`
  (`for n in api worker webhooks migrator`, and the calendar's equivalent).
- The packages are **public** — no pod in this deployment carries an `imagePullSecrets`.
- `imagePullPolicy: Never` was removed everywhere by `15-06`, so the default applies.
- GHCR holds **101 tags** of `ago-chat-migrator`, and an arbitrary one resolves with HTTP 200 to an
  anonymous caller.

So an evicted image whose tag is in the registry is re-pulled by the kubelet with nobody doing
anything. Three of the four readings `23-109` opened with were answering a question that does not
exist.

**What is genuinely exposed is narrow and real**: `redeploy.sh` builds from the node's own checkout and
tags with that commit, so a commit whose CI run failed — or has not finished — produces images that
exist on this node and nowhere else.

The second half is unrelated to the first and shares only its symptom. `apply-demo.sh` refuses to
delete a migrator `Job` that has active pods, which is right: killing a running migration is worse
than waiting. But a pod whose image does not resolve is **active by that measure and stays active
forever**, so the refusal became permanent and the next apply was blocked by a migration that was not
running.

## Decision

**1. The build asks the registry first.** In `build-images.sh` and `build-calendar-images.sh`, per
image and not per repository: if the registry already holds that name and tag, pull it; otherwise
build it **and say that it now exists only on this node**.

The per-image granularity is the load-bearing part. `build-images.sh` builds five images while CI
publishes four — `ago-chat-roleassignmentbackfill` is a hand-applied corrective with no Deployment
(`22-26`) and is not published. Skipping a repository's build wholesale because *most* of it is in the
registry would have stopped building that fifth image entirely, which is precisely the failure `23-98`
had just fixed in the import step.

`registry_has` (`k8s/lib-registry.sh`) returns three answers, not two: present, absent, and **could not
ask**. A caller treats "could not ask" as *build it* — a network failure must never be read as "the
registry has it".

**2. A Job whose container cannot start is not a running migration.** `apply-demo.sh` reads the
container's own waiting reason and treats `ImagePullBackOff`, `ErrImagePull` and `InvalidImageName` as
"this will never start", deletes the Job, and lets the apply recreate it at the tag the manifest pins.
Anything else keeps the old refusal.

**The distinction is "working" versus "cannot start", never "slow" versus "quick".** A migration
against a large table is legitimately active for a long time, and that is the case the guard exists
for. A timeout would get exactly it wrong; the container's waiting reason answers without guessing.

## Consequences

**A redeploy stops rebuilding what already exists.** At `main`'s tip, seven of eight backend images are
pulled and one is built — measured, not estimated. That is faster, and more importantly it means an
image that *is* built is built because nothing else holds it, and the operator is told so at the moment
it happens rather than a week later when GC takes it.

**One image remains genuinely node-only: `ago-chat-roleassignmentbackfill`.** It is now visible instead
of silent. Whether CI should publish it is a separate question and deliberately not answered here — it
is a hand-applied corrective, and publishing it would make a tool that is meant to be deliberate look
like part of the deployment.

**The stuck-Job fix is proved against a real unstartable pod, not argued.** A scratch Job with an
unresolvable image reported `1 active pod(s)` — exactly what the old guard read and would have refused
on forever — while its container reported `ImagePullBackOff`, which is what the new check reads.

**A new dependency, stated: the build path now needs outbound HTTPS to `ghcr.io` to decide.** It
already needed it to pull. `registry_has`'s third answer is what keeps a network failure from silently
changing the decision.

**`23-98`'s recorded diagnosis is left standing and wrong**, because ADRs and closed items are not
edited (`adr/0156`). This ADR is where a reader learns the correction, which is the arrangement that
split is for.

## Alternatives considered

**Pin the images against containerd's GC.** Smallest change and directly targets the symptom, but it
makes the disk story worse rather than better: a pinned image is exactly the one GC cannot reclaim when
the node is genuinely full, and the node had reached 86%.

**Rebuild on demand when an image is found missing.** Keeps the current model and needs no registry
call, but makes a deploy's duration depend on what GC happened to take, and a rebuild is only
reproducible when the checkout is at the right commit — which `redeploy.sh` guarantees and `deploy.sh`
does not.

**Warn after building rather than pull instead of building.** The honest minimum, and it was the other
option put to the author. It leaves every image still built on the node and the exposure intact, merely
visible. Rejected because the exposure is cheap to remove rather than merely observe.

**A timeout on the Job refusal.** Rejected above: a long migration is the case the guard was written
for, and a timeout is wrong precisely there.
