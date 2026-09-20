# 25-182 · demo-shop2.reserve-me.ru is a dead deployment

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-20, the author - `ago-landing` no longer links to `demo-shop2.reserve-me.ru`
  (confirmed: `grep -rn "demo-shop2" ago-landing/*.html ago-landing/*.js` returns nothing), so the
  second demo tenant is live, costing a TLS cert entry and a running pod, and reachable by nobody
  through the product's own front door. **The author will delete the DNS record himself once this
  item's own teardown is confirmed complete** - do not wait on that to finish this item; the DNS
  deletion is downstream of this one, not a dependency of it.

## What is actually true today

`demo-shop2.reserve-me.ru` is a full, real deployment - not a stale reference to clean up, an actually
running one:

- **`ago-deploy`** (`k8s/overlays/demo/`): `gateway.yaml` has its own `https-demo-shop2` listener
  (line 120) and its own `HTTPRoute` (`ago-demo-shop2`, line 357) naming the hostname explicitly;
  `tls.yaml` carries it in the certificate's own `dnsNames` (line 65) - removing it here is what lets
  the author's own DNS deletion happen without a dangling cert entry pointing at nothing; `demo-shop2-
  static.yaml` is the Deployment/Service itself; `kustomization.yaml` lists that file as a resource
  (line 19) and pins its image tag (line 281-282); `network-policies.yaml` names `ago-demo-shop2` in
  its own allow-list (line 47).
- **`ago-widget`**: its own CI (`.github/workflows/*.yml`) builds and publishes a second image,
  `ago-demo-shop2`, from the same `Dockerfile` with a different `DEMO_PAGE_DIR` build arg
  (`public-demo-2`) - named explicitly in at least four separate loops/lists in that workflow file, per
  the file's own line references above. `src/demo/boot.ts`/`config.ts`/`i18n/en.ts`/`ui/widget.ts` and
  the `public-demo-2/` page itself are the actual demo content this image embeds.

## Scope

- **`ago-deploy`**: remove `https-demo-shop2`'s own listener and `HTTPRoute` from `gateway.yaml`;
  remove the hostname from `tls.yaml`'s `dnsNames` (a real, one-way certificate change - once removed
  and reissued, re-adding it later means a fresh validation, not a revert); delete
  `demo-shop2-static.yaml`; remove its `resources`/`images` entries from `kustomization.yaml`; remove
  `ago-demo-shop2` from `network-policies.yaml`'s allow-list.
- **`ago-widget`**: stop building/publishing the `ago-demo-shop2` image - remove it from the CI
  workflow's own build/tag/manifest loops. Whether `public-demo-2/`'s own page content and the
  `DEMO_PAGE_DIR` build-arg mechanism itself are removed too, or just the second image nobody builds
  from them any more, is a real choice - name which is chosen rather than leaving a half-removed
  mechanism with no caller.
- **Live verification, the same discipline `25-180`'s own Done-when states for a new hostname, run in
  reverse for a removed one**: after the manifests are applied, confirm `demo-shop2.reserve-me.ru`
  genuinely serves nothing (a connection refusal or a gateway-level 404, not a stale cached response),
  and confirm every *other* hostname on the shared `ago-public-tls` certificate (`chat.`, `demo-shop1.`,
  the apex, etc.) still serves correctly after the cert is reissued without this one name - a shared
  certificate is exactly the kind of change where removing one name incorrectly can take others down
  with it.
- Tell the author explicitly, in the session, once this is confirmed live-torn-down - that is the
  signal he is waiting for to delete the DNS record himself.

## Out of scope

- Deleting the DNS record itself - the author's own action, downstream of this item.
- `ago-demo-shop1` - untouched, still linked from the landing page.

## Done when

- [ ] `demo-shop2.reserve-me.ru` no longer resolves to a running service - confirmed live (a real
      request against the real hostname), not asserted from the manifest diff.
- [ ] `ago-public-tls`'s certificate no longer lists `demo-shop2.reserve-me.ru`, and every other
      hostname on that same certificate still serves correctly after the reissue.
- [ ] `ago-widget`'s CI no longer builds or publishes `ago-demo-shop2`, and the fate of
      `public-demo-2/`'s own content (kept as dead code with a stated reason, or removed) is decided
      explicitly rather than left ambiguous.
- [ ] `k8s/overlays/demo/kustomization.yaml`'s own resource/image lists, `network-policies.yaml`, and
      every file this item's own Scope names are updated - `bash tools/queue-audit.sh`-style drift check
      (or this deployment's own `check-manifest-drift.sh`) run clean afterward.
- [ ] The author is told, explicitly, that the teardown is confirmed live and the DNS record is now
      his to remove.
