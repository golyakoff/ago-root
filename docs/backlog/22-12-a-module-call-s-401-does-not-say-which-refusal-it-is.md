# a module call's 401 does not say which refusal it is

- **Stage**: 22
- **Status**: done (2026-09-04), `adr/0099` — one Done-when met by description rather than by a
  built check. See Outcome.
- **Found**: 2026-09-03

## The gap

After `22-04`, a module call is refused with **401** in every case, and the cases are not the same problem:

| what happened | what the caller sees |
|---|---|
| the site has no registration — the module was never enabled for it | `401` |
| the credential is forged, or signed with another site's secret | `401` |
| the credential expired | `401` |

The first is a **configuration** state that an operator fixes by enabling the module. The second is an **attack** or a genuine key mismatch. They are answered identically, so nothing downstream — a log, an alert, a smoke check, a person — can tell "not set up yet" from "someone is trying it on".

## Why this is worth its own item

`20-24` already paid for the neighbouring lesson: a refusal has to be distinguishable from an unmapped route, and that one **is** handled — a nonsense sibling path returns `404`, and both suites keep a control asserting it. This is the same principle one level in, and it was found the same way: by asking what a check could actually conclude from the response.

It also compounds with `22-11`. While nothing provisions registrations, *every* call is the first case — so an operator debugging a dead module and an operator being probed read exactly the same thing.

## The tension to resolve rather than assume

**Saying more to the caller is not automatically right.** The module channel is machine-to-machine and its caller is chat, not the public — but the route is reachable from the internet, and an unauthenticated prober learning "this site exists but is not enabled" is a small disclosure that would not otherwise be free.

So the answer may well be *"the wire stays a flat 401; the distinction lives in the module's own logs and metrics"*. That is a legitimate outcome and it should be **chosen and written down**, not arrived at by leaving things as they are.

## Done when

- [x] The three cases are distinguishable to whoever operates the module — with the choice argued.
      — six reasons, in logs; the wire stays flat, and `adr/0099` carries the argument including the
      half-measure that was tried and rejected because the same signal returns through timing.
      `22-11` added a fourth case and it is classified with them.
- [x] If the wire stays flat, the reason is recorded where the next person to ask will find it. —
      `adr/0099`, which also records the **premise**: if `22-18` moves this channel inside the cluster,
      the anonymous-prober argument weakens and the decision is worth revisiting.
- [ ] A smoke or alert check can tell "not enabled" from "refused", or it is stated why it cannot.
      — **described precisely, not built.** `smoke.sh` lives in `ago-deploy`, out of this item's lane.
      And one fact only a look at the live deployment could supply: production logs are **plain text**,
      with no JSON console formatter, so the two values render into the message string rather than
      surviving as fields. A grep-based check works; field-level alerting does not exist for this.

## Context

Reported by the `22-04` worker against its own work: *"I did not realize this was worth flagging until re-checking."* Both module products behave this way.

## Outcome

Done 2026-09-04. `ago-calendar#36` and `ago-faq#4`, then `adr/0099`.

**The conservative answer, chosen rather than defaulted to.** The item warned that "the wire stays
flat" must not be arrived at by leaving things as they are. It was argued: the route is reachable from
the internet, so a distinguishable response would tell an anonymous caller whether a site exists —
and that the only legitimate caller is chat does not help, because nothing on the route checks it.

**The half-measure was tried and rejected**, which is the part worth keeping. Enriching the response
only for almost-authenticated callers returns the same signal through timing; it would have looked
like protection without being it.

**The decision records its own premise.** If `22-18` lands and this channel moves inside the cluster,
the prober argument weakens and this is worth revisiting. An ADR that says when it stops applying is
more useful than one that only says what was decided.

**The credential constraint is a test, not an intention.** "Log which case it was" must never become
"log the presented value", and a test asserts across every refusal case that no logged message carries
the raw header or any credential material. Checked independently at merge: the file contains exactly
two log calls, both structured, carrying exactly the reason and the claimed site id.

**Built in both products**, as `22-11` was, for the same reason: doing only the deployed one lets a
product-shaped seam into a contract that has to stay generic, with nothing to catch it.

`22-15`'s dead `access.*` mappings were deliberately **not** folded in — asked for as a judgement and
answered honestly: this refusal bypasses `ToProblem` entirely, so it is a different edit in a
different place.
