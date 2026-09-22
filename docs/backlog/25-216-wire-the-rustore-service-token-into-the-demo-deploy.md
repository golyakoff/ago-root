# 25-216 · Wire the RuStore service token into the demo deployment

- **Stage**: 25
- **Status**: done — `ago-deploy#257`
- **Found**: 2026-09-22. The author created a real RuStore Console push project and its service
  token while scoping `26-06`. `docs/architecture/secrets.md` §C already documents
  `RUSTORE_PUSH_SERVICE_TOKEN` as a real row (added when `26-04`/`adr/0180` landed), but the actual
  `ago-deploy` manifest wiring for it was never written — `Ago.Chat.Infrastructure.RuStore`'s
  `RuStorePushSender`/`RuStoreOptions` have shipped since `26-04`, unable to receive a real
  configuration value in any live deployment until this item.
- **Verified**: 2026-09-22 — `Ago.Chat.Worker/Program.cs` binds `Push:RuStore:*`
  (`RuStoreOptions.SectionName`) with `.ValidateOnStart()` and **two** required checks:
  `Push:RuStore:ProjectId must be set` and `Push:RuStore:ServiceToken must be set`. Both are
  mandatory — the Worker will not start with only one supplied. `.env`'s real value for
  `RUSTORE_PUSH_SERVICE_TOKEN` was captured by the managing session directly onto the demo node
  (`~/ago/ago-deploy/k8s/overlays/demo/.env`, never through this repository, never through a
  Bash argument) the same session this item was filed. `RUSTORE_PUSH_PROJECT_ID` is not yet supplied —
  the author has not yet handed it over; this item's own manifest wiring does not need the real value
  to be written correctly, only the real value's *name*.

## What this item is

The one thing standing between `26-04`'s already-shipped RuStore adapter and an actually-configured
live deployment: the `.env.example` entry, the `worker.yaml` environment mapping, and confirming the
overlay still renders. **Not** the real value going in — that already happened, by hand, outside this
repository, the same way every other row in `secrets.md`'s table does.

## Scope

- **`k8s/overlays/demo/.env.example`**: add `RUSTORE_PUSH_SERVICE_TOKEN=<generate-a-real-secret-do-not-commit>`
  and `RUSTORE_PUSH_PROJECT_ID=<the RuStore Console push project's own id>`, in the same style every
  other row in this file already uses — a comment stating what it protects and why it lives here,
  matching `RUSTORE_PUSH_SERVICE_TOKEN`'s own row in `docs/architecture/secrets.md` §C almost verbatim
  (that row already exists; this is porting it into the file kustomize actually reads).
- **`k8s/base/worker.yaml`** — `Ago.Chat.Worker`'s own container **only** (never `api.yaml`, never
  `webhooks.yaml`; `secrets.md`'s own row states this isolation explicitly and `NotifyOperatorDevicesHandler`'s
  registration lives in the Worker alone, `26-05`'s own precedent): two new `env:` entries mapping the
  raw `.env` key names (already available to every container via the blanket
  `envFrom: secretRef: name: infra-credentials`, so `$(RUSTORE_PUSH_SERVICE_TOKEN)`/
  `$(RUSTORE_PUSH_PROJECT_ID)` kustomize var substitution works the identical way
  `CHANNELS_CREDENTIAL_ENCRYPTION_KEY`'s own row in this same file already does) into the
  double-underscore names ASP.NET Core's configuration binder expects:
  ```yaml
  - name: Push__RuStore__ServiceToken
    value: "$(RUSTORE_PUSH_SERVICE_TOKEN)"
  - name: Push__RuStore__ProjectId
    value: "$(RUSTORE_PUSH_PROJECT_ID)"
  ```
- **Confirm the overlay still renders** — `kubectl kustomize k8s/overlays/demo` (or the local overlay,
  whichever this repository's own convention checks without a live cluster) succeeds and the rendered
  `infra-credentials` Secret carries both new keys once a real `.env` supplies them (a local `.env`
  built from the example plus throwaway values is enough to prove the rendering; no live redeploy is
  this item's own job — see Out of scope).

## Out of scope

- **Actually redeploying the demo cluster.** This item lands the manifest change; applying it against
  the live node (`docs/runbooks/redeploy.md`) is a separate, deliberate action the managing session
  takes with the author present, not bundled into this PR merging.
- **The Android client's own registration flow** — `26-06`, unblocked by this item existing but not
  performed by it.
- **`RUSTORE_PUSH_PROJECT_ID`'s real value** — supplied by the author whenever the RuStore Console push
  project's own id is in hand; this item's `.env.example` change is correct with or without it already
  known.
- **A second push project for a second build type.** `25-215` unifies debug and release under one
  signing key, so RuStore Console needs exactly one project for this app, not two.

## Done when

- [x] `.env.example` documents both new keys, in this file's own established comment style.
- [x] `worker.yaml` maps both raw `.env` keys into the two `Push__RuStore__*` names
      `RuStoreOptions`/`Program.cs` actually bind, on the Worker container only.
- [x] The demo overlay renders with a local, throwaway `.env` supplying both keys — proven by
      actually rendering it and inspecting the `infra-credentials` Secret's own keys, not by reading
      the YAML and assuming it is correct. Confirmed independently by the managing session too, not
      only the implementing worker: rendered a second time from a fresh throwaway `.env`, grepped the
      full ~5000-line output, found the two keys in the Secret and the two `env:` lines exactly once.
- [x] `api.yaml` and `webhooks.yaml` are confirmed unchanged — the isolation `secrets.md`'s own row
      states is real, not accidentally widened. Confirmed by grep on the rendered output: zero
      occurrences outside `ago-chat-worker`.

## Outcome

Landed as `ago-deploy#257`. `RUSTORE_PUSH_SERVICE_TOKEN` and `RUSTORE_PUSH_PROJECT_ID` now render into
the demo overlay's `infra-credentials` Secret and map to `Push__RuStore__ServiceToken`/
`Push__RuStore__ProjectId` on `ago-chat-worker` only, mirroring `CHANNELS_CREDENTIAL_ENCRYPTION_KEY`'s
own established shape. Both real values already live on the real demo node's own `.env` — placed there
directly by the managing session the same session this item was filed, never through this repository.
`RUSTORE_PUSH_PROJECT_ID`'s real value (`1Q8iLXwwBZViuznG6eCTHgkzrTE9Bto6`, the author's own real
RuStore Console "AGO Chat Production" push project) arrived and was added the same way shortly after.

**Verified independently, beyond the implementing worker's own report**: read both diffs directly;
re-rendered the overlay myself from a fresh throwaway `.env` and confirmed the same result the worker
reported, rather than trusting the report alone.

**Still out of scope, deliberately**: actually redeploying the demo cluster with these real values —
a separate, deliberate action for the managing session to take with the author present.

**Update, same day**: that redeploy has now happened. The author asked for the latest of everything
to go to the demo stand; the managing session applied `ago-deploy`'s `kustomization.yaml` image-pin
change (`ago-deploy#258`) via `apply-demo.sh` against the real node, and `smoke.sh` (run over SSH,
against the real cluster) passed 43/43. `RUSTORE_PUSH_SERVICE_TOKEN`/`RUSTORE_PUSH_PROJECT_ID` are
therefore live in the cluster now, not merely rendered into a throwaway overlay — the "not yet
performed" framing above describes a state that no longer holds.
