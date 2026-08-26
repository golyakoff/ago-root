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
| 0029 | Widget config is fixed fields, read at bootstrap | Accepted |
| 0030 | Design tokens and a closed hand-rolled component set for the console, not a component library | Accepted |
| 0031 | History retention: an immutable retention class in the partition key, an archive instead of deletion | Accepted |
| 0032 | The platform owner is a Keycloak realm role, deliberately outside the per-site RBAC model | Accepted |
| 0033 | A capacity claim is a receipt on the conversation, not an assumption about assignment | Accepted |
| 0034 | The realm's login-security policy, and every token lifetime, chosen rather than inherited | Accepted |
| 0040 | Keycloak's SMTP is a realm setting supplied as a Secret; a sink locally; the sending provider is the author's call | Accepted, provider sub-decision open |
| 0044 | Delivery is dimensioned by recipient kind and presence; the platform reports facts, the product names them | Accepted |
| 0045 | Alerting reaches a person by email through the node's own Postfix; Prometheus rules and Alertmanager, not Grafana | Accepted |
| 0046 | `Ago.Platform.Hosting` carries only the module seam; telemetry ships as `Ago.Platform.Observability` | Accepted |
| 0047 | Images go to GHCR under a commit-SHA tag, and a rollback is a first-class operation | Accepted |
| 0048 | Visitor sessions renew at the point of use; the token drops to seven days, sliding, with no absolute cap | Accepted |
| 0049 | AGO Calendar's time model, and no-overlap as a database exclusion constraint | Accepted |
| 0050 | Backup scope per store, the author's own machine as the destination, and a key the node does not hold | Accepted |
| 0051 | A frontend image takes no environment input from its build command; the commit determines the artifact | Accepted |
| 0052 | *(never written - the number was reserved for `17-08` and the item turned out to need no decision of its own; kept vacant rather than reused, so a reference to `0052` anywhere is a mistake rather than a different ADR)* | n/a |
| 0053 | Availability materialisation is day-granular and insert-only | Accepted |
| 0054 | Runtime hardening: what each workload is constrained to, and what is deliberately not | Accepted |
| 0055 | External channel identity, and the shape of the inbound channel port | Accepted |
| 0056 | Schema migrations are a separate deployable that runs before the hosts | Accepted |
| 0057 | How long logs, traces and metrics are kept, and what actually enforces it | Accepted |
| 0058 | Demo credentials are minted per viewer, with a tenant of their own | Accepted |
| 0059 | The booking claim is a compare-and-set, and a lost race is not an error | Accepted |
| 0061 | A message can carry structure AGO Chat does not understand | Accepted |
| 0062 | *(never written - reserved for `5-19`, which turned out to need no decision of its own: `adr/0048` already carried the precedent. Kept vacant rather than reused)* | n/a |
| 0063 | A principal's kind is answered per surface, by asking the positive question | Accepted |
| 0064 | AGO Calendar's console is its own repository; its booking UI is not | Accepted |
| 0065 | AGO Chat carries a module's steps without understanding them | Accepted |
| 0067 | One key issues, several validate, and retirement is a configured delay | Accepted |
