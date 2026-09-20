# 25-188 · Removing a resource from the demo overlay leaves it running

- **Stage**: 25
- **Status**: done — `ago-deploy#245` (`f37eeb3`), `ago-root#1264` (`0052651`). Built the reverse
  existence check in `check-manifest-drift.sh` rather than `kubectl apply -k --prune` -
  `overlays/demo` has no common label a prune selector could scope to today, and introducing one
  risks colliding with a Deployment's immutable `spec.selector.matchLabels` on a live object, a
  one-way risk the worker had no cluster to prove safe against. **Independently re-verified against
  the real cluster before merging** (the worker's own report explicitly flagged this as unverified) -
  found and fixed a real false positive: `ago-chat-gateway-nginx` (NGINX Gateway Fabric's own
  auto-provisioned data plane for the `ago-chat-gateway` Gateway object, confirmed via its own
  `ownerReferences`) would have reported DRIFT on every single run; excluded by exact name. Re-ran
  the exact `25-182` incident as a scratch case against the real cluster's own resource list with the
  exclusion in place: zero false positives, the real orphan shape still caught. `docs/runbooks/
  redeploy.md` updated with the real removal procedure, including the manual `kubectl delete` step
  that still remains.
- **Depends on**: nothing
- **Found**: 2026-09-20, the managing session, applying `25-182`'s own demo-shop2 teardown live.

## What is actually true today

`apply-demo.sh` runs `kubectl apply -k overlays/demo` with no `--prune` flag. `kubectl apply -k`
without pruning only ever adds or updates whatever the manifest currently lists - it never deletes a
resource that used to be listed and no longer is. `25-182` removed `demo-shop2-static.yaml` from
`kustomization.yaml`'s own `resources` and deleted its own `HTTPRoute` block from `gateway.yaml`, and
`apply-demo.sh` ran clean and reported nothing wrong - but the real `Deployment`, `Service` and
`HTTPRoute` for `ago-demo-shop2` were all still running in the cluster afterward, found only because
the managing session checked for them by hand rather than trusting the apply's own silence.

**This is a standing, repeatable gap, not a one-off mistake in `25-182`.** Any future item that
removes a resource from `k8s/overlays/demo/` - deletes a static-site file, drops an `HTTPRoute`, folds
two Deployments into one - will hit the identical silent orphan unless whoever lands it happens to
check for it by hand, the way this session did only because `25-182`'s own Done-when explicitly asked
for a live check. Nothing currently in `apply-demo.sh`, `check-manifest-drift.sh`, or their own
runbooks names this risk or catches it.

## Goal

Make a removed resource's own continued existence in the cluster either impossible to miss or
impossible to happen, decided explicitly rather than left as "whoever removes something next
remembers to check":

- **Option A - `kubectl apply -k --prune`.** The mechanically complete fix, but Kustomize's own prune
  needs a label selector scoping exactly what it is allowed to delete, and getting that scope wrong
  is a real, one-way risk in the other direction (pruning something a *different* overlay or a
  hand-created resource still needs). Needs real care, not a default flag flipped on blind.
- **Option B - `check-manifest-drift.sh` gains a reverse check**: enumerate every `Deployment`/
  `Service`/`HTTPRoute` actually running in the namespace and flag any whose name has no matching
  resource anywhere in `kubectl kustomize overlays/demo`'s own rendered output - the same "manifest
  and cluster must agree" posture that script already states for image tags, extended to existence
  rather than only version.
- Name which is chosen (or both), and update `docs/runbooks/redeploy.md`'s own procedure to state
  whichever manual step remains, if any.

## Out of scope

- Re-litigating whether `demo-shop2`'s own removal (`25-182`) was correct - it was, and it is already
  live-confirmed torn down (the managing session deleted the three orphaned resources by hand while
  landing that item).
- Any other overlay (`local`) - this item is scoped to `overlays/demo`, the only one `apply-demo.sh`
  targets.

## Done when

- [x] A decision is made and implemented (prune with a correctly-scoped selector, a drift-check
      addition, or both) so that a future resource removal from `overlays/demo` either deletes the
      live resource automatically or is caught loudly by an existing check - not silently missed.
- [x] The chosen mechanism is proven against a real, deliberate test case (a scratch resource added
      and then removed from the overlay, confirmed gone/flagged after the real apply/drift-check runs)
      - not asserted from reading the script. — proven against the real cluster's own live resource
      list, not only a local simulation.
- [x] `docs/runbooks/redeploy.md` states the real, current procedure for removing a resource, matching
      whatever this item actually built.
