# 26-131 · [ago-deploy] Host the Android design mini-site at android-design.reserve-me.ru

- **Stage**: 26 — hosting for `26-130`, mirrors the brand-book deploy.
- **Status**: ready — **blocked on DNS**: `android-design.reserve-me.ru` is being provisioned by the author;
  the gateway route + TLS only go live once it resolves to the node and cert-manager can issue.
- **Found**: 2026-09-25.

## Scope (mirror `brandbook-static.yaml` + its gateway/TLS)
- `k8s/overlays/demo/android-design-static.yaml`: Deployment + Service serving
  `ghcr.io/golyakoff/ago-android-design:<sha>` (same shape as `brandbook-static.yaml`).
- `gateway.yaml`: a listener + HTTPRoute for `android-design.reserve-me.ru`; `tls.yaml`: the hostname added
  to the cert.
- Image pin + `deploy.sh`/FRONTENDS entry so it deploys the brand-book way.
- Public, unadvertised (no auth gate — same as brand-book), but not linked from anywhere.

## Done when
- [ ] Manifests prepared (route/TLS/service/pin). When DNS resolves: the site answers at
      `https://android-design.reserve-me.ru`, TLS valid, smoke shows it serving.
