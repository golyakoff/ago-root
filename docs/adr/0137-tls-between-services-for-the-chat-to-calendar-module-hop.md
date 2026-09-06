# ADR-0137: TLS between services, scoped to the chat -> calendar module hop, on a bring-your-own internal CA

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 22

## Context

`22-18` took the module channel off the public internet: chat reaches `ago-calendar-api`'s module
endpoints over the cluster network (Service DNS, never a public hostname), and the public routes for
that channel now answer nothing from outside. Its own closing note recorded a question it correctly
refused to answer - whether the traffic on that now-internal hop should be encrypted - and carried it
out to `22-24` rather than closing it silently. `22-24` laid out three readings and took none; the
author has now chosen.

**Reading B: TLS between services, certificates issued in-cluster.** cert-manager already runs here
for the public certificate (`adr/0026`, `ago-deploy/k8s/overlays/demo/tls.yaml`), so the machinery for
issuing and renewing certificates exists. What `22-24` named as the real cost of choosing this over
reading A (plain HTTP, written down as a decision) does not disappear by being chosen: certificate
lifecycle for a name with no public DNS record and no ACME path, one more thing that expires, and a
failure mode where an expiry takes down a path no user-facing check watches - the chat-to-calendar
call is exactly such a path, since nothing a visitor or an operator does touches it directly.

## Decision

### 1. Scope: one hop, named explicitly, and nothing wider

This ADR covers **only** chat's calls to `ago-calendar-api`'s module endpoints
(`/api/v1/module-tasks`, `/api/v1/module-registrations` - `adr/0065`, `adr/0095`), made from
`Ago.Chat.Api` (registration/provisioning, `EnableModuleForSite` and its siblings) and
`Ago.Chat.Worker` (the task channel, `ModuleTaskConsumer` -> `HttpModuleGateway`). Every other
in-cluster hop - Postgres, Redis, RabbitMQ, MinIO, Keycloak - **stays on plain HTTP/TCP, on purpose,
not by omission.** `22-18`'s own text is about the module channel specifically; doing every hop at
once is exactly how a change like this becomes unlandable, and doing one hop while implying all of
them would be worse than doing nothing - a checklist line ticked falsely. If a future item wants a
second hop encrypted, it is a second, smaller version of this same decision, not an extension read
into this one.

This is **not** a replacement for `17-05`'s NetworkPolicies, and the two answer different questions
that must not be blurred: a NetworkPolicy says *who may open a connection*; this ADR says *whether the
bytes on a connection that is allowed are readable in transit*. `17-05` already restricts which pods
may reach the stateful backends; nothing here widens or narrows that. The public edge is equally
untouched - `adr/0014`/`edge.md`'s "TLS terminates at the Gateway, plain HTTP behind it" stands exactly
as it did; `ago-calendar-api`'s Gateway-routed public traffic (console, embed, `/api/v1/me`) keeps
going over the same plain-HTTP-behind-the-Gateway path it always has. What this ADR adds is a second,
independent Kestrel listener that only a caller inside the namespace has any reason to open.

### 2. A second Kestrel endpoint on `ago-calendar-api`, config-driven, no code change

`ago-calendar-api` gains `Kestrel:Endpoints:Https` (port 8443) alongside the existing
`Kestrel:Endpoints:Http` (port 8080, now stated explicitly rather than left to the base image's
`ASPNETCORE_HTTP_PORTS` default - see `ago-deploy/k8s/overlays/demo/kustomization.yaml`'s own comment
for why stating both is what keeps this safe). This is Kestrel's own configuration-driven endpoint
binding, present since ASP.NET Core 5 and never overridden by `Ago.Calendar.Api/Program.cs` (checked
against the source, not assumed) - no C# change, in either repository. The certificate is read from
two files (`Certificate:Path`/`Certificate:KeyPath`) mounted from a Secret cert-manager populates and
renews; the pod never sees a private key it did not already have mounted read-only.

The Gateway's own HTTPRoute is untouched and still targets port 80/8080. Port 8443 exists purely for
the module channel.

### 3. A bring-your-own CA, not cert-manager's own self-signed-Certificate pattern

cert-manager can generate a private root entirely inside the cluster (a `SelfSigned` `Issuer`
bootstrapping one `isCA: true` `Certificate`). That pattern was considered and rejected here for a
reason specific to this project's own delivery pipeline: the caller that has to trust this root is
`Ago.Chat.Api`/`Ago.Chat.Worker`'s own **compiled container image**, and CI builds that image before
any cluster or Certificate object exists. A root generated at cluster-apply time cannot be baked into
an image published earlier.

Instead, the CA is generated **offline, once**, with the same primitives cert-manager itself would
use (EC P-256, a 10-year self-signed root, `openssl req -x509`). Its public certificate
(`internal-ca.crt`) is committed - real, not a placeholder in the security sense, because **a
certificate is not a secret**, the identical reasoning `secrets.md` already applies to a site's own
public key - in two places that need it for two different reasons:

- `ago-deploy/k8s/overlays/demo/internal-ca.crt`, the public half of the `kubernetes.io/tls` Secret a
  namespaced cert-manager `Issuer` (kind `ca`) reads to sign the one leaf this item scopes to.
- `ago-chat`'s own `Dockerfile`, embedded into the build stage's trust store via `update-ca-certificates`
  - the identical mechanism already used for `14-02`'s Russian Trusted Root CA, one `COPY` and one
  `RUN` added beside it, with the same final-stage `COPY --from=build /etc/ssl/certs /etc/ssl/certs`
  already carrying it into the Chiseled image with no image-shape change.

**The private key is the one thing that never enters a repository.** It is generated by whoever
deploys, following the bootstrap sequence in `ago-deploy/k8s/overlays/demo/internal-ca.key.example`,
and supplied as a gitignored file consumed by kustomize's own `secretGenerator` - the identical shape
`.env` already has for every other real credential in that overlay. `disableNameSuffixHash: true` is
set on that generator, found necessary by rendering the overlay: cert-manager's `Issuer.spec.ca.
secretName` is a CRD field kustomize's built-in name-reference transformer does not know to rewrite,
so a content-hashed Secret name would leave the `Issuer` pointing at a name that never exists. A fixed
name is also the honest shape for what this Secret is - not something a routine content change should
roll automatically, since changing it is a rare, coordinated, "Breaking"-class operation (see
Consequences), the same class `secrets.md` already gives cert-manager's own ACME account key.

**Why a namespaced `Issuer`, not a `ClusterIssuer` like `letsencrypt-prod`.** `letsencrypt-prod` is
cluster-scoped because ACME account state genuinely is - one account, and cert-manager expects a
`ClusterIssuer`'s own secrets in one fixed namespace (`--cluster-resource-namespace`, defaulting to
the `cert-manager` namespace, not `ago-chat`). This CA has no such reason: both its Secret and the one
Certificate it signs live in `ago-chat`, exactly where a namespaced `Issuer` looks by default.
`ClusterIssuer` would only add a cross-namespace question this decision does not need.

### 4. Demo overlay only, matching this repository's own existing precedent

Neither cert-manager nor `Issuer`/`Certificate` CRDs are installed on the local Docker Desktop cluster
(`docs/runbooks/k8s-local.md` never installs cert-manager; `docs/runbooks/public-deploy.md` step 5
installs it only on the VPS). This mirrors `17-05`'s own NetworkPolicies, which are demo-overlay-only
for the identical reason - a mechanism this repository has not verified works on the local cluster is
not something to ship there as apparent protection. `k8s/base/` and `k8s/overlays/local/` are
untouched; the local dev loop keeps working exactly as it does today, on plain HTTP, unaffected.

## Consequences

**What this buys**: the one hop `22-18` made internal, and named as still carrying the module
provisioning secret and the per-call credential in clear text across the pod network, no longer does.
`22-18`'s own residual (TLS inside the cluster, listed as a smaller-but-real exposure) is closed for
that specific hop.

**What this costs, stated rather than hidden, per `22-24`'s own demand**:

- **A private key with no rotation automation, and a real coordinated-rotation procedure if it is ever
  needed.** The leaf certificate (90 days, cert-manager's own default) renews unattended and costs
  nothing a caller has to react to, because renewal re-signs with the *same* root key - nothing a
  trust bundle depends on changes. The root does not have that property: if it is ever rotated
  (compromise, or simply reaching the end of its stated 10-year life), every step in section 3 repeats
  - new key, new committed certificate in *both* repositories, a rebuilt and republished `ago-chat`
  image, and a re-created `ago-internal-ca` Secret - before any module call succeeds again. This is
  `secrets.md`'s **Coordinated** class at its most expensive: the two repositories' copies must change
  together, and a live deployment is not calling the module channel correctly in between.
- **The root CA's own expiry has no automated alert, and this is a real, named gap, not an oversight
  papered over.** The leaf's expiry is fully covered by the *existing* `TlsCertificateRenewalOverdue`
  Prometheus rule (`adr/0045`) with **zero changes to the rule itself** - its `expr` already carries no
  `name=`/`issuer_kind=` matcher (the rule's own test file already proved this generically, with a
  `some-healthy-cert` series, before this item existed), so `ago-calendar-api-internal-tls` is covered
  by construction. This item adds a second series to that same test
  (`ago-deploy/k8s/overlays/demo/prometheus-alert-rules.test.yml`) proving it fires for a
  namespaced-`Issuer`-backed certificate exactly as it does for the public one, run for real with
  `promtool test rules` (not merely rendered). The **root**, by contrast, is a plain
  `kubernetes.io/tls` Secret this overlay populates directly, never a cert-manager `Certificate`
  object - deliberately, per section 3, because pointing a managed `Certificate` at a `secretName`
  kustomize's own `secretGenerator` already fills would make cert-manager treat it as foreign and try
  to reissue over it, silently replacing the offline-generated root with one nothing else trusts. That
  same choice means cert-manager exports **no** `certmanager_certificate_expiration_timestamp_seconds`
  series for the root at all, so the generic rule cannot see it. The honest mitigation is the root's
  10-year duration, deliberately long enough that this project's own lifetime is unlikely to see it
  expire, plus a human-readable date in the bootstrap runbook step - weaker than the leaf's mechanism,
  and stated as such rather than left for a reader to discover. Building real machinery to watch a
  decade-out date on a single-tenant portfolio deployment would be exactly the "invented number,
  alerting on noise" `prometheus-alert-rules.yml`'s own design note already argues against for other
  rules.
- **A certificate that nothing trusts fails closed, and that is by design, but it is still a new way
  for the module channel to go down.** If the two repositories' copies of `internal-ca.crt` ever
  disagree - a botched rotation, a partial deploy - `HttpModuleGateway`'s calls throw
  `ModuleUnreachableException` (its own existing, uniform failure boundary) rather than silently
  succeeding over an unverified channel. That is the correct failure direction, and it was chosen
  over the alternative of a callback that skips validation - but it is still a new dependency the
  module channel did not have before this change, on top of the database, the broker and the two
  processes it already needed.
- **Left in plaintext, by explicit decision, and revisited only if a reason to reach further
  appears**: Postgres, Redis, RabbitMQ, MinIO, Keycloak. None of them is this item's subject, and
  `22-18`'s own text never named them.

## Alternatives considered

- **Reading A (plain HTTP, written down as a decision)** - `22-24`'s own reading, and the one the
  author declined. Cheaper, and defensible for a single-node deployment, but leaves
  `compliance-checklist.md`'s section F answerable only with "the perimeter is the cluster boundary,"
  which stops being sufficient the moment a real tenant's module credential is asked about in the
  same conversation as a form.
- **Reading C (a service mesh)** - rejected in `22-24` itself and not revisited here: a mesh is a
  deployable to operate, on a one-node cluster, for one call between two services.
- **cert-manager's own in-cluster `SelfSigned` root** - see section 3. Rejected specifically because
  the trusting side is a container image built before the cluster exists, not because the pattern is
  wrong in general; a project whose CI could build after a bootstrap CA exists would have no reason
  to prefer the offline-generated root this ADR chose.
- **A ConfigMap/init-container trust bundle at runtime** (`SSL_CERT_FILE`/`SSL_CERT_DIR` set on
  `ago-chat-api`/`-worker`, assembled from a mounted CA cert at pod start) - prototyped and abandoned
  in favour of the Dockerfile approach. Two real problems, not just inconvenience: `SSL_CERT_FILE`
  replaces the process's entire trust source, and a bundle assembled from an unrelated init image's
  own roots would **silently drop the Russian Trusted Root CA** `14-02` already depends on for
  MaxApiClient's outbound calls - a regression nothing in this change should risk. `SSL_CERT_DIR`
  avoids that by being additive, but OpenSSL's directory lookup requires each file to be named by its
  own subject-hash symlink, which needs `openssl`/`c_rehash` tooling this project's own images
  deliberately do not carry (Chiseled, no shell). The Dockerfile route reuses a mechanism already
  proven in this exact repository, needs no new image, and was verified directly (see below) rather
  than argued from documentation.
- **A leaf certificate covering more names than `ago-calendar-api`'s own** (a shared internal
  wildcard, or one certificate per future internal hop) - not built, because there is exactly one hop
  to name today. `internal-tls.yaml`'s own `Issuer` can sign a second `Certificate` the day a second
  hop is decided, with no change to this one.

## What was demonstrated, and what was not

`22-24`'s own brief asks that trust be demonstrated rather than asserted, and that the expiry
mechanism be shown rather than claimed. Both were checked with tools this task's own constraints
allow - Docker and `openssl`, run locally, no cluster, no `kubectl apply`, no `ssh`:

- **A .NET client on the exact Chiseled base image `Ago.Chat.Api`/`-Worker` ship on trusts a leaf
  certificate signed by this CA, by default, with no code change and no environment variable** - a
  minimal `SslStream` client (no custom validation callback, the same posture `HttpModuleGateway`'s own
  registered `HttpClient` already has) connected to a server presenting a certificate for
  `ago-calendar-api` signed by an offline-generated instance of this CA, both running inside an image
  built from `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` with only the Dockerfile change this
  ADR describes. Result: `TLS_TRUSTED`, hostname validation against `ago-calendar-api` included. The
  identical setup with the Dockerfile's CA step removed produced the fails-before: `TLS_REJECTED -
  ... PartialChain`. The real `ago-chat` `Dockerfile` (not a stand-in) was then built for
  `Ago.Chat.Api` with this item's actual one-line change, and the resulting image's `/etc/ssl/certs`
  was inspected directly: `ago-internal-ca.pem` present, with the correct OpenSSL subject-hash symlink
  (`0ba830de.0`) pointing at it - the same mechanism the client-trust test exercised, confirmed present
  in the real artifact.
- **The expiry alert fires for a namespaced-`Issuer` certificate exactly as it does for the public
  one, run for real.** `promtool test rules prometheus-alert-rules.test.yml` (via
  `docker run --entrypoint promtool prom/prometheus`), against the test file this item extends with a
  second `certmanager_certificate_expiration_timestamp_seconds` series aged to 20 days remaining:
  `SUCCESS`. Also found and fixed in the same change: the rule's `first_check` annotation was a
  hardcoded `kubectl describe certificate -n ago-chat ago-public-tls` regardless of which certificate
  actually fired - harmless while only one certificate existed, actively misleading with two. Now
  templated on the alert's own `namespace`/`name` labels.
- **`kubectl kustomize` on the demo overlay, with the throwaway `.env`/`internal-ca.key` files this
  item's own instructions call for, renders cleanly** - both Kestrel endpoints, both Service ports
  (named, since a Service with more than one port must name every one), the `Issuer` resolving the
  *unhashed* Secret name correctly (checked directly in the rendered output; the first attempt, with
  the hash suffix left enabled, did not, and that is documented in the `secretGenerator` entry's own
  comment). This proves the manifests render and cross-reference correctly. **It does not prove they
  work on a live cluster** - no `kubectl apply` was run, cert-manager's actual behaviour under this
  exact `Issuer`/`Certificate` pair, the real renewal timing, and Kestrel's own behaviour serving two
  endpoints from one process are none of them demonstrated here, only argued from documented behaviour
  and this repository's own existing, working use of every individual piece (Kestrel config-driven
  endpoints, cert-manager `ca`-type issuers, `update-ca-certificates` in this exact base image).
- **Not demonstrated, and said so rather than assumed**: cert-manager's actual renewal of the leaf
  under this `ca`-type `Issuer` on a real cluster; whether Kestrel picks up a renewed certificate file
  without a pod restart (relevant only at the leaf's 90-day renewal, not to first issuance); the real
  root's own bootstrap sequence, which this item deliberately did not run for real - the CA generated
  to prove the mechanism was destroyed after the demonstration and never committed, exactly because a
  key generated by this session is not one the author should be trusting a live deployment to.
