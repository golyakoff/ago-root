# Runbook: redeploying the demo environment

`public-deploy.md` is the record of the **first** bring-up. Its steps are marked "done 2026-08-24",
which is accurate and is exactly why it should not be used as a redeploy procedure: a step marked done
does not read like a step. On 2026-08-25 a redeploy followed that document, skipped its step 9
(migrations), and left the API running against a schema three migrations behind — every query loading
a `Site` failed, the widget was dead, and every page still returned 200 because nginx was serving
files perfectly well.

So the procedure is a script, not a list. A list can be read selectively; that is what happened.

## Deploying a build CI already published — the normal path since `15-06`

```bash
cd ~/ago/ago-deploy/k8s && ./deploy.sh <40-character-commit-sha>
```

`ago-chat`'s CI publishes `ghcr.io/golyakoff/ago-chat-{api,worker,webhooks}:<sha>` on every push to
`main` (`adr/0047`), so most deploys no longer build anything on the node at all: this moves the three
Deployments onto an artifact that already exists, waits for the rollouts, prints the tag *and* the
commit each pod reports about itself, and runs the smoke test.

It refuses any tag that is not a full commit SHA — `main` and `latest` name a moment rather than a
build, and cannot be rolled back to.

```bash
./deploy.sh --current      # what is running, and what each pod says it is
./rollback.sh              # undo one revision on all three hosts
./rollback.sh <sha>        # go to a specific published build
./rollback.sh --history    # what there is to go back to, by image
```

**One trap, stated because it is easy to walk into.** `deploy.sh` uses `kubectl set image`; it edits
no file. `k8s/overlays/demo/kustomization.yaml`'s `images:` block is the committed record of what
this environment is *meant* to run, and a `kubectl apply -k overlays/demo` resets the cluster to the
tag written there. After a deploy that is meant to stick, update those three `newTag` values and
commit. `deploy.sh` prints the exact value; `smoke.sh` fails if the running image tag and the commit
inside the binary disagree.

## Building from source on the node

```bash
cd ~/ago/ago-deploy/k8s && ./redeploy.sh
```

It pulls every checkout, restores the executable bit the build scripts keep losing, builds the
images, imports them into containerd, applies migrations, moves the workloads onto the newly built
commit in the order that matters, and finishes by running the smoke test. It is safe to run when
nothing has changed.

Since `15-06` this is the **exception** rather than the mechanism — a hotfix that has not been
merged, a cluster rebuilt ahead of CI, or the four static bundles, which are still built here because
their repositories do not publish images yet. What it builds is tagged with the commit and the GHCR
path, so an image built on the node and one pulled from GHCR are interchangeable by name.

Its step 6 no longer does `kubectl rollout restart`. A restart was the only option while every image
wore the same mutable `:local` tag — the manifest never changed, so only a restart made the kubelet
re-read what the tag now pointed at. Now the tag *is* the commit, so the manifest changes and
Kubernetes records a revision, which is exactly what gives `rollback.sh` something to go back to.

## Why each step is where it is

- **Checkouts first, and they are the usual cause of "the fix is not live".** Merging on GitHub
  changes nothing here; the box has its own clones. On 2026-08-25 `ago-console` was six commits behind
  and had been serving a pre-`11-05` bundle for a day, with nothing anywhere reporting it — the image
  tag is `:local`, unversioned, so nothing about the running pod says which code is in it. `15-06`
  closed that for the three .NET hosts: their tag is the commit and `GET /healthz/version` reports it
  from inside the binary. **It is still open for `ago-console` and the other three static bundles** —
  the exact component the original incident was about — so for those, the pull step is still the only
  mitigation there is.
- **Migrations before the restart, not after.** Migrations here are additive, so the old code still
  running is unaffected by columns it does not know about. New code meeting an old schema is the
  failure above. A destructive migration would need a different order and its own thinking; there has
  not been one, and if there is, this note is the place to say so.
- **The API restarts before the console**, because `12-03`'s owner view calls `12-02`'s endpoint, and
  a console newer than its API shows a screen wired to something that does not exist yet.
- **The smoke test runs last and is part of the deploy**, not a thing to remember afterwards.

## The smoke test on its own

```bash
cd ~/ago/ago-deploy/k8s && CHAT_REPO=~/ago/ago-chat ./smoke.sh
```

Run it from anywhere for the HTTP checks; the migration comparison needs cluster access and is skipped
with a warning without it, so run it on the node to get the check that matters most. Every check names
the incident it exists for, which is the only way a check list stays honest instead of accumulating
items nobody can justify.

It creates one real visitor row per run. That is stated in the script too — a smoke test is not free
of consequence, and pretending otherwise is how a harmless check becomes somebody else's data problem.

## What to do when a step fails

- **Migration step fails to connect**: the port-forward it starts needs a moment, and a previous run
  may have left one behind — `pkill -f "port-forward svc/postgres"` and run again. The connection
  string is built from the live Secret, whose name is hash-suffixed by kustomize, so it is looked up
  by label rather than hardcoded.
- **`dotnet restore` fails**: `/tmp/nuget.migrations.config` is a host-only file (`public-deploy.md`
  step 9 explains why neither committed nuget config works here) and `/tmp` does not survive a reboot.
  Recreate it from that step.
- **A rollout does not become ready**: `./rollback.sh` — it undoes one revision on all three hosts,
  waits, prints what is running, and smokes. See "Rolling back, and what it does not roll back" below
  for the part that matters.
- **Smoke fails on the console CSS check**: the bundle is stale, which means either the pull or the
  import did not take. Check the pod's start time against the commit you expected.

## What it does not apply: manifests

`redeploy.sh` pulls, builds, imports, migrates and restarts. It never runs `kubectl apply -k`. That is
defensible — a redeploy is usually about new *code*, and applying an overlay that also carries a
half-finished manifest change is its own hazard — but it means **a change that lives only in
`ago-deploy/k8s/` does not reach the node through this script**, no matter how many times it is run,
and nothing in its output says so.

**The same is true one level further out, for anything under `k8s/backup/`** (`15-02`). Those are
systemd units on the node, not Kubernetes objects at all, so neither `redeploy.sh` nor
`kubectl apply -k` reaches them: `k8s/backup/install-node.sh` is the only thing that does. Re-run it
after any `git pull` that touches that directory. [`backup-and-restore.md`](backup-and-restore.md) has
the detail.

`15-01` is the first change of that shape: Keycloak's move onto a persistent database is entirely
manifest plus one new `.env` key. `public-deploy.md`'s "Applying `15-01` to this deployment" section is
the procedure, and it starts with `kubectl apply -k k8s/overlays/demo` for exactly this reason. The
same applies to any future resource-limit, probe, route or env change. If the fix is in a `.yaml` under
`k8s/`, `./redeploy.sh` is not the tool.

`10-05` adds a second shape of the same problem, one step further removed: a change that does not
reach the node through `kubectl apply -k` either. The realm's `smtpServer` — and every realm-level
setting since `15-01` — is state inside Keycloak's database, not a manifest. Applying the overlay
updates the Secret; it does not update the realm. `k8s/apply-smtp-settings.sh` (SMTP, from the Secret)
and `k8s/apply-realm-settings.sh` (everything in `keycloak-realm-import.json`) are the tools, and
neither is run by anything automatic. If mail stops sending after a credential rotation, this is why:
the `.env` changed, the Secret changed, the realm did not.

## Rolling back, and what it does not roll back

```bash
cd ~/ago/ago-deploy/k8s && ./rollback.sh
```

`kubectl rollout undo` on all three hosts. It reads the Deployment's own revision history, stored in
the cluster, so it still works when the reason for the rollback is that GHCR is unreachable — which
is why it is the no-argument path. `./rollback.sh <sha>` goes to a named build instead.

**It does nothing whatsoever to the database, and neither does anything else here.** Schema only moves
forward. That is survivable only because every migration so far has been additive — code from an
earlier commit runs unharmed against a later schema, ignoring columns it does not know about — and
that is a property to keep deliberately:

> A migration must remain compatible with the image immediately before it. Expand now, contract in a
> later release.

A destructive migration — a dropped or renamed column, a narrowed type — **breaks rollback outright**.
If one is ever written, recovery from a bad deploy stops being "roll the image back" and becomes
"restore from backup" (`15-02`). Say so in that migration's own review, because afterwards is too
late to find out.

Two smaller things a rollback leaves behind:

- `kubectl rollout undo` prints a warning about `kubectl.kubernetes.io/last-applied-configuration` not
  being updated. It is accurate — a later `kubectl apply -k` reconciles against a stale record. The
  `images:` block in the overlay settles it in practice, which is another reason to keep that block
  matching reality.
- The overlay still names whatever tag was last committed. Update it, or a future `apply -k` quietly
  undoes the rollback.

## What this does not solve

**The four static bundles.** `ago-console`, both demo shops and the landing page are still built on
the node under a mutable `:local` tag, still have no published artifact, and still cannot say which
commit they carry — which is precisely the component the 2026-08-25 incident was about. `15-06` could
not change those repositories; `adr/0047` names what each of them needs. Until then, for the
frontends, this script's pull step remains the mitigation rather than the fix.

**Deploying is still a thing somebody starts.** Nothing here is automatic, deliberately.
