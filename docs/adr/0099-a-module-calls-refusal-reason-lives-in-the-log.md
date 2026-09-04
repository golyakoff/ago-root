# ADR-0099: A module call's refusal reason lives in the log, not on the wire

- **Status**: Accepted
- **Date**: 2026-09-04
- **Stage**: 22
- **Extends**: `adr/0094` (the per-call credential whose refusal this classifies) and `adr/0095` (the
  provisioning mechanism whose absence is one of the classified cases). Amends neither.

## Context

`22-04`'s `HmacModuleCallCredentialValidator` — identical in `ago-calendar` and `ago-faq` — answers
every refusal with `IsAuthenticated: false`, and the endpoints turn that into a flat `401` regardless
of cause. Three named cases:

| what happened | what the caller sees |
|---|---|
| the site has no registration — the module was never enabled for it | `401` |
| the credential is forged, or signed with another site's secret | `401` |
| the credential expired | `401` |

The first is a **configuration** state an operator fixes by enabling the module. The second is an
**attack** or a genuine key mismatch. Answered identically, nothing downstream — a log, an alert, a
smoke check, a person — can tell "not set up yet" from "someone is trying it on".

`22-11` added a fourth: a credential that was legitimate until a rotation's grace window closed.

## Decision

**The wire answer stays a flat `401`. Each product's validator classifies every refusal into a
`ModuleCallRefusalReason` and logs it, structured, before returning.**

Six reasons: `NoCredential`, `Malformed`, `SiteNotRegistered`, `InvalidSignature`, `AssertionExpired`,
`CredentialRotatedOut`. The first two log at **Debug** — they cannot be attributed to any site, so
nothing downstream can act on them, and they are the highest-volume shape a random prober produces.
The other four log at **Warning** with the *claimed* site id.

The reason is carried on the validator's own result and **never reaches the endpoints**, which are
unchanged by this item — so "the wire stays flat" is enforced by the diff rather than by intention.

`CredentialRotatedOut` is possible because a rotation does not null `PreviousCredential`; it only
stops `ActiveCredentials` yielding it. A failed match is therefore re-checked against the raw
previous value **purely to classify, never to authenticate**.

**Only the reason and the claimed site id are logged.** The site id is not a secret — it is already in
request bodies and console URLs. The raw header, the decoded payload and every credential value are
never logged in any branch, and a test asserts that across every refusal case rather than a comment
claiming it.

## Why not put the reason on the wire

**The route is reachable from the internet.** A distinguishable response would let an anonymous caller
learn *"this site exists, the module just is not enabled"* versus *"this site does not exist"* — a
disclosure this channel does not currently pay for. That the only legitimate caller is chat does not
help, because nothing on the route checks that.

The half-measure — enriching the response only for callers that are almost authenticated — was tried
and rejected: **the same signal returns through timing.** A partial defence here would have looked
like protection without being it.

**This decision is conditional, and the condition is written down rather than left implicit.**
`22-18` (`ago-root#402`) keeps this channel inside the cluster, where chat and the module products
already share one. If that lands, the anonymous-prober premise weakens considerably and this decision
is worth revisiting. It has not landed and may not.

## Consequences

- An operator debugging a dead module and an operator being probed now read differently **in logs**,
  though still identically on the wire.
- **A check for "not enabled" versus "refused" must read logs, not status codes** — by construction.
  What such a check asserts is described in `22-12`'s own outcome for `ago-deploy` to implement.
- **Production logs are plain text.** Verified on the live deployment rather than assumed: no JSON
  console formatter is configured, so `{Reason}` and `{ClaimedSiteId}` are rendered into the message
  string rather than surviving as separate structured attributes. A grep-based check works because the
  template renders predictably; **field-level alerting does not exist for this**, and would need a
  formatter change that is not part of this decision.
- The reason taxonomy is one more hand-kept pair between the two module products, beside the wire
  format, the credential shape and the provisioning contract — the same accepted duplication, for the
  same reason `adr/0094` gave: no shared package, because `Ago.Platform.*` holds no product concept.
- `CredentialRotatedOut` costs one extra comparison against the previous credential on every failed
  match, whether or not its grace window is still open.

## Alternatives considered

- **Distinguish on the wire**, by status code or a body field. Rejected on the disclosure argument
  above, and the timing objection kills the narrowed version of it too.
- **Log the reason but never the site id.** Rejected: the site id is not secret, and without it
  neither a log line nor an alert can be scoped per site — which is the capability the item asks for.
