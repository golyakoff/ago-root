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

Since `15-07`/`adr/0051` the four frontends publish the same way, from their own repositories'
CI — but one at a time, because they come out of **three** repositories that move independently and a
single tag cannot honestly name images built from more than one of them:

```bash
./deploy.sh console     <sha>   # from ago-console
./deploy.sh demo-shop1  <sha>   # from ago-widget
./deploy.sh demo-shop2  <sha>   # from ago-widget, same commit as demo-shop1
./deploy.sh landing     <sha>   # from ago-landing
```

```bash
./deploy.sh --current              # all seven, tag beside the commit each pod reports about itself
./rollback.sh                      # undo one revision on all three hosts
./rollback.sh <sha>                # go to a specific published build of the three hosts
./rollback.sh <frontend>           # undo one revision on one frontend
./rollback.sh <frontend> <sha>     # go to a specific published build of that frontend
./rollback.sh --history            # what there is to go back to, by image, all seven
```

A frontend reports its commit from `/version.json`, written into the image at build time — a browser
bundle has no process to ask, so the artifact carries a file instead. The widget bundle additionally
carries it as `window.AgoChat.commit`, because that bundle is the one artifact that runs on an origin
we do not control, where no `version.json` of ours sits beside it.

The bare `./rollback.sh` still means the three hosts and nothing else, deliberately: during an
incident the no-argument path must stay the one thing with no decision in it.

**One trap, stated because it is easy to walk into.** `deploy.sh` uses `kubectl set image`; it edits
no file. `k8s/overlays/demo/kustomization.yaml`'s `images:` block is the committed record of what
this environment is *meant* to run, and a `kubectl apply -k overlays/demo` resets the cluster to the
tag written there. After a deploy that is meant to stick, update the `newTag` values that moved — of
seven now, three hosts and four frontends — and commit. `deploy.sh` prints the exact value;
`smoke.sh` fails if the running image tag and the commit inside the artifact disagree, for all seven.

### AGO Calendar is deployed, and none of the above covers it

**`deploy.sh` and `rollback.sh` do not mention the calendar at all.** Their `HOSTS` array is the three
`ago-chat-*` hosts and their `FRONTENDS` array is the four chat-side frontends. As of `20-20`
(2026-09-03) the cluster also runs `ago-calendar-api`, `ago-calendar-worker`, the
`ago-calendar-migrator` Job and `ago-calendar-console` — four workloads and three image pins that
neither script knows exist.

So, until `20-25` closes:

- **Moving the calendar to a new build** means editing the three `newTag` values in
  `k8s/overlays/demo/kustomization.yaml` by hand and running `kubectl apply -k k8s/overlays/demo`.
  The migrator's tag moves with the hosts and never on its own (`8-08`).
- **There is no rollback path.** `./rollback.sh` will not touch the calendar, and its no-argument form
  deliberately means the three chat hosts. Going back is `kubectl rollout undo` per Deployment, by
  hand, with the same migrator coupling to respect in reverse.

`smoke.sh` does cover the calendar, but with two of its checks skipped rather than passing: the
calendar API reports no commit, so "reports its commit" and "the image tag matches the binary" cannot
be asserted for it (`20-24`). Those are precisely the two that catch a stale image, which is the
failure this whole document exists for — so treat a calendar deploy as *unverified in that respect*
rather than as covered.

**Apply from the node, with the node's own `.env`.** Rendering the overlay anywhere else produces
`envFrom` references to a `Secret` whose name carries a hash of whatever placeholder values were used,
and that Secret does not exist on the node — three Deployments went to `CreateContainerConfigError`
this way on 2026-09-02.

## Building from source on the node

```bash
cd ~/ago/ago-deploy/k8s && ./redeploy.sh
```

It pulls every checkout, restores the executable bit the build scripts keep losing, builds the
images, imports them into containerd, applies migrations, moves the workloads onto the newly built
commit in the order that matters, and finishes by running the smoke test. It is safe to run when
nothing has changed.

Since `15-06` this is the **exception** rather than the mechanism — a hotfix that has not been
merged, or a cluster rebuilt ahead of CI. `15-07` removed the last standing reason to use it: the
four static bundles publish from their own repositories too, and
`IMAGE_REPO=ghcr.io/golyakoff IMAGE_TAG=commit ./build-static-images.sh` produces exactly the names
their CI pushes (`IMAGE_TAG=commit` means *each image takes its own repository's HEAD*, not one tag
for all four). What is built here is tagged with the commit and the GHCR path, so an image built on
the node and one pulled from GHCR are interchangeable by name.

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
  from inside the binary, and `15-07` closed it for the four static bundles the same way — the exact
  component the original incident was about. A stale checkout on the node still produces a stale
  deploy; what changed is that the running pod now says so, and `smoke.sh` reads it.
- **Migrations before the restart, not after.** Migrations here are additive, so the old code still
  running is unaffected by columns it does not know about. New code meeting an old schema is the
  failure above. A destructive migration would need a different order and its own thinking; there has
  not been one, and if there is, this note is the place to say so.
- **`8-08`: the migration step is a Job now, not `dotnet ef database update`.** `Ago.Chat.Migrator`
  is built from the same commit as the hosts and applied as a Kubernetes Job (`adr/0056`), so the
  thing that migrates and the things that serve can no longer disagree about which migrations exist,
  and the node needs no .NET SDK. `backoffLimit: 0`: a failed migration stops the deploy rather than
  retrying, and the script prints the Job's logs and exits non-zero.
- **`8-10`: a deploy that restarts Postgres needs nothing from you.** The Job and everything else are
  applied together, so the migrator can start while Postgres is still coming back — and it waits for
  it (90s) instead of failing. `backoffLimit: 0` deliberately did not change: retrying the Job would
  also retry a genuinely broken migration, which is the thing `8-08` argued must not happen. What
  changed is that "the database is not there yet" stopped counting as a failure at all.
- **`8-08`: skipping it is no longer silent, which is why this document exists.** The three hosts
  refuse to start against a schema older than the migrations they were compiled with. The incident
  this runbook was written after — every page returning 200 while every `Site` query failed — cannot
  recur in that shape: the pods do not come up, and their logs name the missing migration.
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

- **The migration Job fails**: the script stops there on purpose and prints its logs. Read them —
  `Ago.Chat.Migrator` reports the provider's own error, not a summary. **Since `8-10` the first line
  says which of three things went wrong, and they need different reactions:**
  - *`MIGRATION FAILED: …`* — the migration ran and threw. A code problem. The schema is at whatever
    the last migration to complete left it at (`__EFMigrationsHistory` is truthful about that), and
    re-running the Job will fail the same way until the migration is fixed.
  - *`WAITING FOR DATABASE FAILED: gave up after …`* — Postgres never became reachable inside the
    wait. An infrastructure problem. **No migration was attempted and the schema is unchanged**, so
    re-running the Job once Postgres is up is safe and sufficient.
  - *`CANNOT CONNECT TO DATABASE: …`* — Postgres answered and refused: a wrong credential, a database
    that does not exist, a missing grant. Reported immediately rather than waited out, deliberately —
    the alternative would report a wrong password as a ninety-second timeout. Nothing was attempted;
    fix the configuration.

  Re-running the script re-runs the Job (it deletes the previous one first, because a Job's pod
  template is immutable). The two entries that used to live here — a port-forward left behind, and a
  missing `/tmp/nuget.migrations.config` — are gone with the step that needed them: `8-08` removed
  both the port-forward and the SDK restore from the node.
- **Pods do not become ready and their logs mention `SchemaOutOfDateException`**: the migration did
  not run, or ran against a different database. This is `8-08`'s guard doing its job. Fix the
  migration step; the pods recover on their own once the schema catches up, and they wait 60s before
  giving up so a Job that finishes late does not need a manual restart.
- **A rollout does not become ready**: `./rollback.sh` — it undoes one revision on all three hosts,
  waits, prints what is running, and smokes. See "Rolling back, and what it does not roll back" below
  for the part that matters.
- **Smoke fails on a frontend's `/version.json`**: since `15-07` it says which of two things went
  wrong. *"serves no usable /version.json"* means a pre-`15-07` image is deployed. *"image tag X but
  the bundle reports Y"* means the tag is lying about its contents — the pull or the import did not
  take, and the pod is running older bytes than the manifest claims.

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

~~**The four static bundles.**~~ Closed by `15-07`/`adr/0051` on 2026-08-25, the same day `15-06`
opened it: `ago-console`, both demo shops and the landing page are published by their own
repositories' CI under the full commit SHA, each serves `/version.json`, and `deploy.sh` /
`rollback.sh` / `smoke.sh` cover them alongside the three hosts. That was precisely the component the
2026-08-25 incident was about.

**Deploying is still a thing somebody starts.** Nothing here is automatic, deliberately.
