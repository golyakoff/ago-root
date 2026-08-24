# Architecture Decision Records

One file per decision a reviewer could reasonably argue with. Numbered, and immutable once accepted:
a decision that changes gets a **new** ADR superseding the old one, and the old one stays with its
status updated. Rewriting history here destroys the only artefact showing how the design was reasoned about.

Write an ADR when a technology is chosen over an alternative, a guarantee is weakened or strengthened,
a boundary is crossed deliberately, or a reviewer would ask "why on earth". Do not write one for
naming, formatting, or anything a convention doc already covers.

| # | Decision | Status |
|---|---|---|
| 0001 | Record architecture decisions | Accepted |
| 0002 | Clean Architecture layering and the dependency rule | Accepted |
| 0003 | Platform/product split, modular monolith, two hosts | Accepted — host count amended by 0013 |
| 0004 | PostgreSQL, EF Core for writes, Dapper for reads | Accepted |
| 0005 | Transactional outbox for reliable publishing | Accepted |
| 0006 | Broker abstraction at topic + partition key + at-least-once | Accepted |
| 0007 | Connection registry instead of a SignalR backplane | Accepted |
| 0008 | Presigned direct-to-storage uploads | Accepted |
| 0009 | Redis is a cache and coordination store, never truth | Accepted |
| 0010 | No sticky sessions at the edge | Accepted |
| 0011 | All instants are UTC `DateTimeOffset`, rendered per request | Accepted |
| 0012 | Multiple repositories, platform published as packages | Accepted |
| 0013 | Three deployables split by failure profile; webhooks as a bulkhead | Accepted |
| 0014 | NGINX Gateway Fabric (Gateway API) instead of ingress-nginx | Accepted |
| 0015 | `ago-chat`'s CI packs `ago-platform` from source, no hosted feed yet | Accepted |
| 0016 | Granular permissions (RBAC), scoped per tenant, as the authorization model | Accepted |
| 0017 | Outbox/inbox writer is generic over `DbContext`, not per-product | Accepted |
| 0018 | `ago-platform` publishes to GitHub Packages; `ago-chat`'s CI restores from it | Accepted |
| 0019 | Partitioning `messages` widens its unique index to include `created_at` | Accepted |
| 0020 | Node-delivery fan-out publishes directly, bypassing the outbox | Accepted |
| 0021 | Operator assignment: `SKIP LOCKED` (default) vs. a per-operator Redis lock | Accepted |
| 0022 | OIDC via Keycloak replaces the operator dev-auth stub | Accepted |
| 0023 | React for `ago-console` | Accepted |
| 0024 | Webhook HMAC-SHA256 signing; secret stored as AES-256-GCM ciphertext, not hashed | Accepted |
| 0025 | Direct OTLP export to Jaeger, no collector | Accepted |
| 0026 | k3s VPS hosting, `*.reserve-me.ru` domain plan, VM sizing, and TLS | Accepted |
| 0027 | Operator identity across products: separate entities, unified only through Keycloak | Accepted |
| 0028 | Keycloak-native self-registration; `RequireKeycloakIdentity` stays distinct from `RequireOperatorIdentity` | Accepted |
