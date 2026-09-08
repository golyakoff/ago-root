# a locally-built image the cluster evicts cannot be pulled back

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `15-21`/`adr/0144` built the drift check that cannot see this, and `23-90` is
  the neighbouring blindness in the same mechanism.
- **Found**: 2026-09-08, by a deploy stopping. **Cause established 2026-09-08** — the first draft of this
  item guessed wrong, and that is recorded below rather than replaced.

## What happened

`apply-demo.sh` created the chat migrator `Job` at the tag the manifest records, and it sat in
`ImagePullBackOff`:

> `ghcr.io/golyakoff/ago-chat-migrator:255cbea…: not found`

A `Job` stuck active also refuses the *next* apply, since `apply-demo.sh` reads `.status.active` and
declines rather than killing a migration that might be running. So one evicted image blocks the next
deploy, not merely its own.

## The cause, established rather than assumed

The first draft of this item offered two possibilities — the script printed a tag it never built, or
built one later collected — and said the distinction had to be settled first. It has been:

- **`build-images.sh` does build it.** `Ago.Chat.Migrator` is in its project loop, and `redeploy.sh`
  runs under `set -euo pipefail`, so a failed build would have aborted the run.
- **`docker images` on the node still holds `ago-chat-migrator:255cbea…`.** It was built and it is
  still there, in Docker.
- **`crictl images` holds no migrator at all** — neither product's. containerd, which is what the
  kubelet actually reads, does not have them.
- **The disk was at 86%**, and the kubelet's image garbage collector begins evicting at 85%.

So the image was built, imported, and then **evicted by containerd's own garbage collector under disk
pressure**. It evicted precisely the images no running workload references — both migrators — while
every host image survived because a `Deployment` holds it.

**And these images exist nowhere else.** They are built on the node and imported locally; `ghcr` has
never had them, and `imagePullPolicy: IfNotPresent` means the kubelet's fallback is a pull that cannot
succeed. **An evicted local-only image is unrecoverable without another build.**

## What is actually filling the disk

`docker system df` on the node: **images 54.5 GB (48 GB reclaimable), build cache 53.8 GB (51.5 GB
reclaimable)**, on a 79 GB volume. Docker's only job here is to *build* an image and hand it to
containerd; nothing prunes what it leaves behind, so every deploy adds layers that will never be read
again.

That is the pressure, and the eviction is its symptom.

## A second instance, found 2026-09-08

`build-images.sh` builds `Ago.Chat.RoleAssignmentBackfill`. **`redeploy.sh`'s import loop does not
import it** — that loop names `ago-chat-api`, `ago-chat-worker`, `ago-chat-webhooks` and
`ago-chat-migrator`, and stops there. So the image is built on every deploy and has never reached
containerd at any tag but one stale copy from 2026-09-04.

`run-backfill.sh` picks the tag `ago-chat-api` is currently running, deliberately, so that the backfill
runs the same commit as the hosts. That is the right choice and it is exactly what turns this omission
into a failure: the tag it picks is the one that was never imported, so the Job cannot start.

Found by needing the backfill to repair `23-104` — imported by hand to unblock a live tenant. **This is
the same defect as the migrator's, not a second one**: an image that is built, never imported, and only
discovered when somebody tries to run it.

## Scope

- **Reclaim, and keep reclaiming.** A build host that never prunes will cross the threshold again
  whatever else changes.
- **Decide what happens to an evicted migrator image.** Three readings, none chosen here: push these
  images to `ghcr` so a pull is possible; re-import from Docker at apply time, which is cheap because
  Docker still has them; or accept it and make the failure legible, since a stuck `Job` blocking the
  next apply is worse than the eviction itself.
- **A `Job` that cannot start should not block the next apply indefinitely.** Whatever else is decided,
  `apply-demo.sh`'s refusal is correct for a *running* migration and wrong for one that never started.

## Where this is likely to go wrong

- **Do not fix it by including Jobs in the drift check.** They are excluded for a stated reason
  (`8-08`: a migrator's tag legitimately lags its host's between a deploy and its commit), and firing on
  every ordinary deploy is the fastest way to make a check ignored — `23-90`'s whole subject.
- **Pruning is destructive on a live node.** Whatever reclaims space must be able to say what it will
  delete before deleting it, and must not remove an image a running workload holds.
- **A deploy that fails loudly is the good case.** The bad one is an apply that silently rolls a host
  back; keep whatever fails closed, failing closed.

## Done when

- [ ] The node has headroom, and something keeps it that way rather than a one-off cleanup.
- [ ] What happens to an evicted migrator image is decided and written down.
- [ ] A `Job` that can never start does not block the following apply.
