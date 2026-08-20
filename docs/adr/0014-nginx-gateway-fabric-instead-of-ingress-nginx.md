# ADR-0014: NGINX Gateway Fabric (Gateway API) instead of ingress-nginx

- **Status**: Accepted
- **Date**: 2026-08-21
- **Stage**: 0

## Context

`edge.md` and the `local-cluster` skill named `ingress-nginx`, installed from its static manifests,
as the edge component for both the local Docker Desktop cluster and (eventually) the Stage 8 public
deploy. `kubernetes/ingress-nginx` was archived in March 2026: best-effort maintenance ended, no
further releases, bugfixes or security patches, and the project itself recommends Gateway API
implementations for anything new. This was discovered while verifying `0-03-local-infrastructure`'s
runbook, before the controller was ever installed - nothing beyond one `Ingress` resource with a
`least_conn` annotation exists on top of it yet, which makes this the cheapest point in the project
to make this call, rather than the most expensive one (Stage 8, real TLS, real traffic).

## Decision

Use **NGINX Gateway Fabric** (NGF) as the edge component, configured through the Gateway API
(`Gateway`, `HTTPRoute`) instead of the legacy `Ingress` resource. NGF is the direct, vendor-endorsed
successor to `ingress-nginx` - same NGINX data plane, Gateway API instead of an annotation-heavy
`Ingress`. The edge principles already established in `edge.md` (TLS termination, coarse rate
limits, `least_conn`, no business logic at the edge) carry over unchanged; only the object types and
their exact fields change.

## Consequences

- Gateway API is actively maintained (v1.4+ production-ready since October 2025, CNCF) - security
  patches and new features keep arriving, unlike a frozen, archived repository.
- Two resource kinds (`Gateway` + `HTTPRoute`) replace one (`Ingress`) - marginally more to read for
  a reviewer unfamiliar with Gateway API, though the same conceptual pieces (host, path, backend,
  TLS) still exist, now as separate typed objects instead of one annotation-heavy blob.
- `least_conn` moves from an `ingress-nginx` annotation to an NGF `NginxProxy` policy attachment;
  nothing about how the behaviour is tested (`adr/0010`) changes.
- Every doc that named `ingress-nginx` (`CLAUDE.md`, `edge.md`, `k8s-local.md`, the `local-cluster`
  skill) needed updating in this same change - done here, so no downstream session inherits a doc
  naming a controller nothing in the repository installs.
- Cost: a newer API some reviewers will not have used, and a rewrite of the one `Ingress` resource
  that existed - both cheap right now; neither would have been at Stage 8.

## Alternatives considered

- **Stay on `ingress-nginx` (pin `v1.15.1`)** - works today, zero migration cost, and is what most
  reviewers have actually operated. Rejected: "works today" on an archived, patch-frozen component
  is not a defensible steady state for a project whose point is demonstrating sound engineering
  judgment, and the migration only gets more expensive the longer it is deferred.
- **A different Gateway API implementation** (Envoy Gateway, Kong, Cilium, Traefik) - all real,
  conformant options. Rejected in favour of NGINX Gateway Fabric specifically because it is the
  direct successor to what this project had already chosen and reasoned about in `edge.md`;
  switching data planes and APIs at once would bundle two decisions as one.
- **Defer the decision to Stage 8** - moves it to the most expensive point (public deploy, real
  TLS, real traffic) instead of the cheapest one available (Stage 0, one unexercised `Ingress`
  resource, no live traffic to break).
