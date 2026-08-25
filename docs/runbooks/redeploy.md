# Runbook: redeploying the demo environment

`public-deploy.md` is the record of the **first** bring-up. Its steps are marked "done 2026-08-24",
which is accurate and is exactly why it should not be used as a redeploy procedure: a step marked done
does not read like a step. On 2026-08-25 a redeploy followed that document, skipped its step 9
(migrations), and left the API running against a schema three migrations behind — every query loading
a `Site` failed, the widget was dead, and every page still returned 200 because nginx was serving
files perfectly well.

So the procedure is a script, not a list. A list can be read selectively; that is what happened.

## The whole thing

```bash
cd ~/ago/ago-deploy/k8s && ./redeploy.sh
```

It pulls every checkout, restores the executable bit the two build scripts keep losing, builds the
images, imports them into containerd, applies migrations, restarts the workloads in the order that
matters, and finishes by running the smoke test. It is safe to run when nothing has changed.

## Why each step is where it is

- **Checkouts first, and they are the usual cause of "the fix is not live".** Merging on GitHub
  changes nothing here; the box has its own clones. On 2026-08-25 `ago-console` was six commits behind
  and had been serving a pre-`11-05` bundle for a day, with nothing anywhere reporting it — the image
  tag is `:local`, unversioned, so nothing about the running pod says which code is in it. This is the
  cost `15-06` was written about, and until it lands the pull step is the mitigation.
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
- **A rollout does not become ready**: `kubectl rollout undo deployment/<name> -n ago-chat` returns
  the previous ReplicaSet. Note what this does *not* undo — a migration already applied. That
  asymmetry is real, and `15-06`'s own scope names writing down the migration-versus-rollback
  interaction as part of its work.
- **Smoke fails on the console CSS check**: the bundle is stale, which means either the pull or the
  import did not take. Check the pod's start time against the commit you expected.

## What it does not apply: manifests

`redeploy.sh` pulls, builds, imports, migrates and restarts. It never runs `kubectl apply -k`. That is
defensible — a redeploy is usually about new *code*, and applying an overlay that also carries a
half-finished manifest change is its own hazard — but it means **a change that lives only in
`ago-deploy/k8s/` does not reach the node through this script**, no matter how many times it is run,
and nothing in its output says so.

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

## What this does not solve

Everything `15-06` covers: images are still built on the node under a mutable `:local` tag, there is
still no registry, and there is still no way to tell from a running pod which commit it came from.
This script makes the sequence repeatable and verified; it does not make it identifiable. Both of the
2026-08-25 failures were symptoms of that, and the script is the mitigation, not the fix.
