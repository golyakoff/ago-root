# a redeploy leaves the manifest behind the cluster, and nothing says so until the next apply

- **Stage**: 15
- **Status**: done
- **Found**: 2026-09-06, by a deploy that failed rather than by reading.
- **Decision**: none needed. This is a gap between two scripts that each work.

## What happened

`23-45` added a startup validation to `Ago.Chat.Api` — a demo deployment that names no published
site refuses to start — and, in the same wave, the configuration that satisfies it, in
`overlays/demo/kustomization.yaml`.

The next `redeploy.sh` **crash-looped the API** on that validation. The configuration was present and
correct in the file; it was not in the cluster.

**Because `redeploy.sh` moves images and never applies manifests.** It builds, imports, runs the
migrators and then `kubectl set image` on each Deployment. A change to a manifest's env, spec, probe
or NetworkPolicy reaches the cluster from that path **not at all**.

Nothing was down: the old ReplicaSet kept serving while the new pod failed. That is the only reason
this was a stumble rather than an outage, and it was luck of ordering rather than design.

## The second half, which is the actual gap

`apply-demo.sh` is the path that *does* apply manifests, and it **refused** — correctly. Its own
guard compares the manifest's pins against what is running and stops when the manifest is behind,
because applying then would silently roll the whole deployment back to the previous build.

So the two scripts are each right and together leave a hole:

- `redeploy.sh` moves the cluster forward and **leaves the manifest behind**. Its closing note asks
  the operator to commit the tags it used, in prose, at the end of a thousand lines of build output.
- `apply-demo.sh` cannot run until somebody has done that.

**Which means every manifest change is blocked behind a manual step nobody is reminded of at the
moment it matters** — and on 2026-09-06 the redeploy failed at step 6, so its closing note never
printed at all, and the frontends were rolled by hand, putting the manifest behind again.

## Why this is worth an item rather than a habit

The habit is already written down and was already followed once today; the same gap reappeared within
the hour because the reminder lives in the output of a script that had already exited.

And the failure it produced is the expensive kind: a change that is **correct in the repository, absent
from the cluster, and invisible until something crashes.** `23-44` was the same shape at the image
level — an invariant asserted in a comment with nothing checking it.

## Scope, and the shapes worth weighing

- **`redeploy.sh` writes the pins itself.** It knows every tag it just built; it could edit
  `kustomization.yaml` and leave the change staged for a human to read and commit. Removes the step
  entirely. Costs a script that edits a tracked file, which is a new kind of thing for it to do.
- **Or `redeploy.sh` applies the overlay first, then moves images.** Closer to correct in principle —
  the manifest becomes the source and the images follow — but it inverts the ordering `8-12` settled
  around migrator Jobs, and that ordering exists for a reason worth re-reading before touching.
- **Or something notices.** A check that fails when the manifest's pins and the cluster's images
  disagree — `smoke.sh` is where this project puts *"what is actually true right now"*, and it already
  compares a served bundle's commit against its image tag (`23-44`).

**Whatever is chosen, the failure this must prevent is a manifest edit that never reaches the
cluster**, not merely a stale tag.

## Done when

- [x] A manifest change made in this repository reaches the cluster by an ordinary deploy, or the
      deploy says out loud that it did not.
      `check-manifest-drift.sh`, called as the last step of both `redeploy.sh` and `deploy.sh`, with a three-outcome contract — `PASS`, `DRIFT`, `UNKNOWN` — that never folds a tool failure into `PASS` (`15-24` fixed a path that did).
- [~] The pins and the cluster cannot drift apart silently.
      **Not closed, and carried out to `23-90`.** The check normalises image tags away before diffing, deliberately (`adr/0144`), so the one kind of drift that actually accumulates is invisible to it. Proven on 2026-09-07: eleven of twelve `newTag` values were stale and the check printed `PASS`. Closing this needs an answer to *when are tags meant to disagree*, which is a decision rather than a fix.
- [x] Whatever notices is shown noticing, against a real drift.
      Shown running against the real demo cluster twice on 2026-09-07, at the end of two real redeploys, returning a correct `PASS` both times — which settles the doubt this box was actually held open on. It has still not been seen printing `DRIFT` against a real non-tag drift, and `23-90` carries that.

## Out of scope

- `apply-demo.sh`'s refusal, which is correct and should stay.
- The `23-45` validation itself, which did exactly what it was written to do — it failed loudly
  instead of serving a console that quietly lied to one account.
