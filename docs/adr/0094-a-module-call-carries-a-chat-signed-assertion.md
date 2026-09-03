# ADR-0094: A module call carries a short-lived assertion chat signs, not a bearer secret

- **Status**: Accepted
- **Date**: 2026-09-03
- **Stage**: 22
- **Extends**: `adr/0065` (the module contract this adds a field to). Amends nothing.

## Context

`adr/0065` gave AGO Chat a product-agnostic way to hand work to a module: a registry row naming a
`ModuleKey`, its trigger words and an `EntryPoint` URL, and an HTTP call to `/api/v1/module-tasks` at
that entry point. Two products consume it — `ago-calendar` (`20-07`) and `ago-faq` (`19-03`).

**Neither call was authenticated.** Both products mapped that route `AllowAnonymous()` and read the
site id **from the request body**. The site's identity was asserted by the caller and believed.
Probed from outside the cluster on 2026-09-03: an unauthenticated POST reached the handler, while a
nonsense sibling path returned 404 — so the route was live and anonymous, not merely untested.

What limited the damage was an accident rather than a control. `ago-calendar` resolves its tenant
from `ChatModule:TenantPublicKey`, a deployment setting, so an anonymous caller could not choose
*which* tenant to act on. **`22-04` removes that pin** and makes the request body the tenant selector,
which is why this decision has to land first: per-site resolution over an anonymous channel hands
tenant selection to the internet.

Three constraints bound the answer. Chat must not learn a product's name — the registry is generic
and stays so (`adr/0027`). `Ago.Platform.*` ships as packages and holds no product concept, so a
shared implementation would have to be a new package with two consumers and no third in sight
(`clean-architecture.md`'s own warning about extracting from too few callers). And a refusal must
stay distinguishable from an unmapped route, or no check built on it can tell "protected" from
"unreachable" — the lesson `20-24` already paid for.

## Decision

**Chat mints a short-lived assertion per call and signs it; the module verifies the signature and
cross-checks the site the assertion names against the work being asked for.**

- The registry row (`EnabledModule`) gains a `Credential` beside its `EntryPoint`, supplied by
  whoever enables the module — the same way the entry point already is. No new provisioning
  handshake is invented.
- `HttpModuleGateway` sends `X-Ago-Module-Credential`: `base64url(payload).base64url(HMAC-SHA256(...))`
  over `{siteId, iat, exp}`, 60-second TTL. The signature covers the **transmitted bytes** of the
  payload segment rather than a re-serialisation, so the two hand-kept copies of the format cannot
  disagree through JSON canonicalisation.
- Each product implements verification in **its own code** — constant-time comparison
  (`CryptographicOperations.FixedTimeEquals`), a five-second skew allowance on expiry, and a
  cross-check of the assertion's site against the request's.
- The route keeps `AllowAnonymous` and validates inside the handler. This is a machine-to-machine
  header, not a user principal, and the refusal is a **401** that stays distinguishable from a 404.
- `RequireCredential` defaults to **true**. Setting it false admits a *missing* header for the length
  of a rollout where the two images cannot move together; a *wrong* one is refused either way.

## Consequences

- **A site id is no longer enough to act.** Forging a call needs the secret, and an assertion signed
  for one site is refused against another's work — proven, in both products, by tests that failed
  before the check existed.
- **The secret is per module deployment, not per site.** This is the honest limit and it is stated
  rather than smoothed over: the *token* cannot cross sites, but whoever holds the raw secret can
  mint one for any site that deployment serves. Harmless while a deployment serves exactly one
  tenant by configuration — and **it stops being harmless in `22-04`**, which is the item that must
  give each registry row an independently generated secret. Recorded here so that is not discovered.
- **The wire format is duplicated in three places** — minted in chat, verified in two products — with
  no compile-time or CI check that they agree. Deliberate, for the reason above, and the cost is a
  real drift risk. Each copy carries a comment naming its twins; a fixed known-good token asserted
  identically in all three would close it and is not built.
- **`ago-calendar`'s reply route is authenticated but not site-scoped**, because `ChatBookingTask`
  carries no site id at all while that deployment is single-tenant. `ago-faq`'s reply route *is*
  scoped, because its task carries the site. Same contract, different products, different current
  shape — named so a reader does not take the asymmetry for an oversight. It closes in `22-04`.
- **A new secret to operate.** It must exist in the node's environment, be referenced by the
  manifests, and match the value on the registry row — three places, one value, and rotating it means
  all three. `secrets.md` gains an entry.

## Alternatives considered

- **A per-site pre-shared secret, chat-generated at enable time.** The stronger answer, and where this
  ends up: it removes the shared-secret limit above outright. Rejected *now* because it needs a
  provisioning handshake that does not exist — something must carry the generated secret to the
  module deployment — and building that is `22-04`'s work, where per-site resolution makes it
  necessary anyway. Doing it here would have been the larger half of another item.
- **mTLS between chat and the module hosts.** Strongest, and what a larger deployment would use.
  Rejected on operational weight: certificate issuance, distribution and rotation for two workloads
  on one node, against a threat this closes with a header. Naming it as the pragmatic production
  answer we did *not* take is the point of recording it.
- **A shared NuGet package for the token format.** Rejected: `Ago.Platform.*` holds no product
  concept, this is not a technical port in the `ICache` sense, and extracting an abstraction from two
  callers with no third in sight is the guess `clean-architecture.md` warns against. The duplication
  is the accepted cost, above.
- **Joining ASP.NET Core's authentication pipeline** with a custom scheme. Rejected as more machinery
  than a single header check, and it would have made the refusal a 401 from middleware rather than
  from the handler that also owns the site cross-check — splitting one decision across two places.
