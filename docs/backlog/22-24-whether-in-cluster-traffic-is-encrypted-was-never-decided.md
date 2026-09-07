# whether in-cluster traffic is encrypted was never decided, and something is waiting on the answer

- **Stage**: 22
- **Status**: done (2026-09-07), `adr/0137`, `ago-chat`/`ago-deploy`. Was: **answered by the author,
  2026-09-06: TLS between services.** Reading B, not A.
- **Depends on**: nothing. Carried out of `22-18`, which named it and correctly refused to answer it.
- **Decision**: none taken. The readings are below and the choice is the author's.

## Where this came from

`22-18` took the module channel off the public internet: chat reaches the calendar's module endpoints
over the cluster network, and both routes now answer nothing from outside — asserted both ways in
`smoke.sh`, refused inside without a credential and absent outside.

Its fourth Done-when read *"whatever was decided about in-cluster TLS is written down"*, and recorded
plainly that **nothing was decided**. The item was then closed with that box open, which left the
queue implying a decision exists somewhere. It does not. This is that decision, with a number.

## What is actually true today

The chat→calendar module call is **plain HTTP inside the cluster** — `http://ago-calendar-api`, not
`https://`. `22-18`'s own closing note is explicit that `EnableModuleForSite` takes the entry point
from its caller, so nothing in the code forces the in-cluster form; the first row written has to use
it, and there is no such row yet.

So the question is live *now*, before the first module row exists, and it is gated on the same step —
whoever issues the provisioning secret.

## The readings

**A — plain HTTP inside the cluster, written down as a decision.** What ships today. The traffic never
leaves the node; the perimeter is the cluster boundary and the NetworkPolicies `17-05` added. Cheapest,
and defensible for a single-node deployment. Its cost is that "we chose this" and "nobody thought
about it" look identical afterwards — which is the entire reason this item exists.

**B — TLS between services, certificates issued in-cluster.** cert-manager already runs here for the
public certificate, so the machinery is present. Real cost: certificate lifecycle for internal names,
one more thing that expires, and a failure mode where an expiry takes down a path no user-facing
check watches.

**C — a service mesh.** Rejected in advance and named only so the next reader knows it was considered:
a mesh is a deployable to operate, on a one-node cluster, for one call between two services.

**Note what none of them changes.** The call carries the provisioning secret, and that secret's
protection is `secrets.md`'s subject, not this one. This item is about the transport.

## Why it matters more once there is a real tenant

`docs/compliance-checklist.md`'s section F is about the protection level and the measures it requires.
*"How is traffic between components protected"* is a question that gets asked with a form in hand, and
the answer **"we never decided"** is worse than either A or B — including when A would have been the
right answer all along.

## Done when

- [x] The author has chosen, and the choice is recorded where somebody reading about the deployment
      will find it — `architecture/edge.md` or an ADR, not only here.
- [~] If A, the reasoning is written down as a decision rather than left as a default. **Not
      applicable: the answer was B.** `adr/0137` records it, including that the scope is one hop and
      that doing one while implying all of them is how a compliance line gets ticked falsely.
- [~] If B, in-cluster certificates have an expiry story and something notices before they lapse.
      **Half true, and the half that is missing is named rather than glossed.** The leaf needs no new
      alert — `TlsCertificateRenewalOverdue` has no per-certificate matcher, proven with a real
      `promtool` run. **The root's expiry has no automated alert at all**, because pointing a
      cert-manager `Certificate` at that Secret would make it reissue over an offline root.
- [~] `compliance-checklist.md`'s F row points at the answer. **It cannot yet, and the reason is not
      ours to fix.** The F rows are the personal-data protection level: F4 is *the measures the level
      requires are implemented and evidenced*, and it reads **cannot start before F1** — the level
      determination, which is a lawyer's document. TLS between services is a measure that will be
      evidenced there once F1 exists; until then the record of it is `adr/0137`.

## Out of scope

- The provisioning secret itself and its rotation (`secrets.md`, `docs/runbooks/secret-rotation.md`).
- Public-edge TLS, which is settled and working.

## The answer (author, 2026-09-06)

**Reading B: TLS between services, with certificates issued in-cluster.** cert-manager already runs
here for the public certificate, so the machinery exists.

**The cost this buys is named in the reading and does not go away by being chosen**: certificate
lifecycle for internal names, one more thing that expires, and a failure mode where an expiry takes
down a path no user-facing check watches. So the expiry story is not a nice-to-have in the
implementation - it is the half that makes this choice safe rather than worse than plain HTTP.

Reading A - plain HTTP written down as a decision - is now closed, and `architecture/edge.md` should
say what was chosen rather than leaving the next reader to infer it from a manifest.
