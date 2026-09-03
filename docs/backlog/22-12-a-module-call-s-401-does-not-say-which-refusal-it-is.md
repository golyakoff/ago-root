# a module call's 401 does not say which refusal it is

- **Stage**: 22
- **Status**: ready
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

- [ ] The three cases are distinguishable to whoever operates the module — on the wire, in structured logs, or both, with the choice argued.
- [ ] If the wire stays flat, the reason is recorded where the next person to ask will find it.
- [ ] A smoke or alert check can tell "not enabled" from "refused", or it is stated why it cannot.

## Context

Reported by the `22-04` worker against its own work: *"I did not realize this was worth flagging until re-checking."* Both module products behave this way.
