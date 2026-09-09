# ADR-0164: The module-provisioning secret is encrypted in transit, trusting `22-24`'s own internal CA

- **Status**: Accepted
- **Date**: 2026-09-10
- **Stage**: 23 (`23-93`)
- **Amends**: `adr/0095` — that decision's blast-radius section never mentioned transport at all, which
  read as *considered and accepted* rather than *not considered*. This ADR is the answer that gap was
  missing, not a reversal of anything `adr/0095` actually decided.
- **Depends on**: `adr/0137` (`22-24`, the internal CA and `ago-calendar-api`'s own 8443 listener) and
  `adr/0154`/`23-92` (the module entry point as one configured value, which is what this decision
  changes the scheme of).

## Context

`adr/0095` gave `Ago.Chat.Api` a deployment-wide bootstrap secret, `X-Ago-Module-Provisioning-Secret`,
and stated its blast radius plainly: a holder can register, rotate or delete the module registration
for any site the deployment serves, and (per `22-17`'s own amendment to that ADR) bring a new tenant
into existence. Nowhere in that accounting does the word "transport" appear. Once `23-92` centralised
the module entry point into deployment configuration, the entry point it produced was
`http://ago-calendar-api` — and the header above now visibly crosses the cluster in clear text every
time chat provisions, rotates or revokes a registration.

That silence was not a decision. It was an omission that reads exactly like one, which is worse: a
reader of `adr/0095`'s blast radius today has no way to tell "the author considered the wire and
accepted clear text" from "nobody asked." `23-93` exists to make that an actual answer, one way or the
other, and to write it where the blast radius is read rather than in a backlog item nobody re-opens
once the code ships.

Three readings were on the table, and none of them was free:

1. **Clear text is an acceptable posture.** `adr/0026` sizes this deployment at one node; pod-to-pod
   traffic never leaves the host, and treating in-cluster traffic as trusted is an ordinary choice for
   a deployment this shape, not a lapse. Nothing about `23-93`'s own investigation contradicts this on
   its own terms — the traffic genuinely does stay on one machine.
2. **It is not acceptable, because `22-24` already answered the general question for this exact
   product boundary.** That item built an internal CA specifically so chat's in-cluster calls to
   `ago-calendar-api` would not be clear text, and `ago-calendar-api` has served an encrypted listener
   on 8443 since. Accepting clear text for the *provisioning* secret — strictly more powerful than the
   per-call credential `22-24` already covers — while treating the weaker credential's own leg as
   worth encrypting is an inconsistency this project has no argument for, only an accident of which
   item happened to ship first.
3. **The secret is the wrong shape regardless of the wire.** A bearer string, replayable by anyone who
   observes it once, is the weakest credential design available, and `adr/0094` already uses a
   per-call signed assertion elsewhere in the identical handshake. Whether the bootstrap anchor should
   be signed rather than presented is a real question and a bigger one — out of scope here, and named
   so it is not lost: it is its own ADR, when someone picks it up.

## Decision

**Encrypt it. The provisioning leg from `Ago.Chat.Api` to a module's entry point uses TLS, trusting
`22-24`'s own internal CA, wherever that CA's listener actually exists.**

Reading 2 wins on its own terms: this deployment already paid the cost of standing up an internal CA
and a second Kestrel listener for exactly this class of traffic, and the provisioning secret is a
worse thing to leave exposed than the credential `22-24` already protects, not a better one. There is
no operational argument for encrypting the weaker secret and not the stronger one on the same wire.

Reading 3 is real and is explicitly **not** decided here — a signed provisioning credential is a
different shape of fix, orthogonal to the transport question, and inventing one inside an ADR whose
job is to close a silence would be exactly the kind of unscoped decision this project's own discipline
warns against. It stays open, named, for whoever picks it up next.

### What actually needed to move, and what already had

Two of `23-93`'s three scope items turned out to already be done by `22-24`, one day before `23-93`
itself was found:

- **`Ago.Chat.Api`'s image already trusts the CA.** `22-24` (`ac22b8f`, 2026-09-06) bakes
  `internal-ca.crt` into the build stage's OS trust store with `update-ca-certificates` and copies
  `/etc/ssl/certs` whole into the Chiseled final stage — the standard pattern for a distroless image
  with no package manager of its own. `HttpModuleRegistrationGateway` (`Ago.Chat.Infrastructure.
  Modules`) is registered against a perfectly plain `HttpClient`
  (`services.AddHttpClient<HttpModuleRegistrationGateway>()`, `ChatModule.ConfigureServices`) with no
  certificate handling of any kind, so the whole trust decision lives in the image, never in
  application code — there was nothing left to "mount" on the `Ago.Chat.*` side by the time this item
  reached it.
- **The leg is proven**, end to end, through the real production gateway class, in `ago-chat`'s own
  `Ago.Chat.Integration.Tests.ModuleRegistrationGatewayInternalTlsTests` — a real Kestrel host on a
  real loopback socket presenting a leaf certificate signed by a throwaway root, called through
  `HttpModuleRegistrationGateway.RegisterAsync` unmodified. One test proves the call is refused when
  the caller does not trust the signing root (the state a pod without `22-24`'s image change would be
  in); a second proves the identical call succeeds once the caller does — `X509ChainTrustMode.
  CustomRootTrust` standing in for what `update-ca-certificates` does to the whole process, at a scope
  a test can safely control without mutating the real OS trust store. This is not a test of the
  Dockerfile step itself (`22-24`'s own report already verified that offline, against a real built
  image) — it is proof that the application code this item touches (none) behaves correctly on both
  sides of that trust boundary.

What genuinely still needed doing, and is done by this same change:

- **`23-92`'s configured entry point changes scheme — in the overlay that can actually serve it, not
  unconditionally.** `ago-deploy`'s `k8s/base/api.yaml` set `ModuleEntryPoints__calendar` to
  `http://ago-calendar-api` for both overlays this repository ships. Investigating this item found
  that `22-24`'s encrypted listener (`internal-tls.yaml`, the 8443 patch on `ago-calendar-api`) exists
  **only** in `k8s/overlays/demo/` — `k8s/overlays/local/` has no cert-manager, no internal CA Secret,
  and no 8443 listener at all. Switching the base value unconditionally would have pointed the local
  development loop at a port nothing there ever binds, trading a solved certificate-trust question for
  an unsolved connection-refused one. The demo overlay's own `kustomization.yaml` now carries a
  strategic-merge patch overriding this one variable to `https://ago-calendar-api:443` — the identical
  "environment-specific difference over a shared base" shape that overlay already uses for
  `DemoTenant__Enabled` — while `base/api.yaml` keeps `http`, correctly, for local. `23-92`'s own
  comment claiming the address "lives in one place" is true of the variable's *name*; it was never a
  claim that every overlay needs the identical *scheme*, and this item is the first place that
  distinction mattered.
- **A stale comment corrected before it misled anyone else.** `base/api.yaml`'s own comment, written
  by `23-92` after a live probe, stated `https://ago-calendar-api:443` "would fail TLS since this host
  carries no internal-CA trust material" — true on 2026-09-07, false by the time this item re-checked
  it, because `22-24`'s image change (2026-09-06) had already landed and the comment was never
  revisited. Left as it stood, it would have told the next reader the encrypted leg was still broken
  after this item had already fixed it — exactly the "silence reads as a considered decision" failure
  mode this ADR exists to close, one level down, in a comment instead of an ADR. Corrected in the same
  change.

## Consequences

- **`adr/0095`'s blast radius no longer implies transport was considered when it was not.** This ADR
  is that answer; `adr/0095`'s own `Amended` line now points here alongside its existing pointer to
  `22-17`.
- **The provisioning secret and the per-call credential `adr/0094` protects now travel the identical
  encrypted leg**, in every deployment that has stood up `22-24`'s internal CA. Nothing about the
  secret's own shape (Reading 3) changed — it is still a bearer string, still deployment-wide, still
  replayable by anyone who reaches the wire before this change closed that wire. Encrypting the
  channel does not narrow who may hold the secret or what it authorizes; it only removes the network
  as a place to acquire it from without already being inside the cluster.
- **The local development overlay is unaffected, on purpose.** `k8s/overlays/local/` keeps `http` and
  no internal-TLS material of its own — extending that overlay to match demo's TLS setup was
  considered and set aside as a larger, separate change with no bearing on this item's own scope
  (encrypting the leg where a real deployment's blast radius is nonzero, not achieving parity between
  a throwaway local loop and a live one).
- **`NetworkPolicies` are not a substitute for this, and do not currently restrict this leg either.**
  At the time of writing, `network-policies.yaml` names ingress allowances for Postgres, Redis,
  RabbitMQ, MinIO and the static sites; `ago-calendar-api` is not among them, on its plain port or its
  encrypted one. That is a related but separate gap — this ADR does not claim to close it, and it
  should not be read as having done so.
- **The signed-provisioning-credential question (Reading 3) remains open**, named here rather than
  silently dropped a second time. Encrypting the wire makes the existing bearer secret harder to
  intercept; it does not make it a better-shaped credential.

## Alternatives considered

- **Leave clear text and record that as the decision (Reading 1).** Rejected on the argument in
  Decision above: this deployment already paid for an internal CA and a second listener to protect a
  weaker credential on the identical wire, and there is no defensible reason to protect the weaker one
  and not the stronger.
- **Redesign the provisioning secret's shape instead of encrypting the wire (Reading 3).** Rejected as
  this item's own scope, not as a bad idea — a real, bigger question, deliberately left for its own
  number rather than folded into a transport decision.
- **Switch the entry point to `https` first, everywhere, and let a certificate failure surface the
  gap.** Rejected explicitly, per this item's own text: that fails closed on a certificate error and
  presents as a broken calendar integration, exactly the confusion `23-92` exists to prevent. Mount
  (already done by `22-24`), then prove (this item's own integration test), then switch (this item's
  own `ago-deploy` change) — in that order, and only in that order.
- **Extend `internal-tls.yaml`'s CA/listener setup to the local overlay too, so both overlays could
  share one unconditional `base/api.yaml` value.** Considered while writing this item's own
  `ago-deploy` change. Rejected for scope: it is a real, larger change (a second `Issuer`/`Certificate`
  or a way to share one across overlays, plus a decision about whether local development needs
  certificate trust at all) with no bearing on the actual blast radius this ADR is about, which lives
  entirely in the demo/live deployment.
