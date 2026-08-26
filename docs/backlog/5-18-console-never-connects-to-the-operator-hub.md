# The operator console never connects to the operator hub, so nobody can answer

- **Stage**: 5
- **Status**: ready — and this is the most severe open defect on the live deployment
- **Depends on**: nothing.

## What is broken

**On the public demo, an operator signs in, the console shows "Operator hub: Offline — Not connected
to the operator hub", and it never becomes connected.** Because no operator ever holds a connection,
the assignment engine has nobody to assign to, so every visitor conversation sits in `Waiting`
forever and no operator can answer it.

That is the README's headline promise — *send a message from the widget, answer it from the console* —
and the second half of it does not work.

## How it was found, and what was ruled out

Walked end to end on the live deployment on 2026-08-26, as a stranger would: minted a demo tenant
from the button, signed into the console with the credentials it handed out, sent a message through
the widget on the tenant's own page.

Everything except the console's hub connection works, and each was checked rather than assumed:

- **The visitor side is fine.** The message was sent, persisted, and the visitor's own presence is in
  Redis (`presence:visitor:…`).
- **Identity is fine.** `GET /api/v1/operators/me` returns `200` with the right `operatorId`,
  `siteId` and six permissions. The `operators` row's `external_subject_id` equals the token's `sub`.
- **The hub itself is fine.** `POST /hubs/operator/negotiate` returns `200` and offers all three
  transports. **A `WebSocket` opened by hand from the console's own page, to the negotiated
  connection id, with the same token, reaches `OPEN`.** So the Gateway, the TLS termination, the
  WebSocket upgrade and the authentication all work.
- **It is not the minted tenant.** Redis holds **zero** operator connections (`conn:*` contains only
  the visitor's), and the worker log shows the seeded operators repeatedly having "no connections for
  the full grace period" — every operator, not just this one.
- **The `403`s in the browser console are a red herring.** They are
  `GET /api/v1/owner/sites?limit=1` — `12-03`'s platform-owner eligibility probe, which correctly
  refuses a non-owner so the console hides the link. Expected behaviour, and the first thing that
  looks like a cause.

So: the console negotiates, and then the connection never completes — not over WebSockets, and not
by falling back to Server-Sent Events or long polling, because either would have registered a
connection in Redis and none exists.

## Why nothing caught it

`smoke.sh` passes 12/12 against this deployment. It checks that the **visitor** hub negotiates with a
visitor token — negotiate only, and only for the other hub. **Nothing in it, or anywhere else,
asserts that an operator ever holds a connection.**

That is the more important half of this item: a check that would have caught it does not exist, and
adding one is worth more than the fix, because this failure is invisible from every signal the
project currently collects. The pods are healthy, the API answers `200`, the smoke test is green, and
the product does not work.

**How long it has been broken is unknown.** Do not guess in the fix; find out if it is cheap to, and
say so plainly if it is not.

## Context to read first

`ago-console/src/realtime/` — the connection provider and its protocol primitives. `docs/backlog/5-07`
and `5-16` — the console's realtime behaviour and a previous token-renewal defect that orphaned an
open conversation, which is adjacent and may share a cause. `docs/architecture/realtime.md` and
`adr/0007` — the connection registry is what "connected" means here, and it is the thing that is
empty. `docs/architecture/concurrency.md`'s assignment section — why no presence means no assignment,
which is the mechanism that turns this from an indicator bug into a product outage.

## Scope

- **Find out why the connection does not complete**, given that a hand-rolled WebSocket to the same
  endpoint with the same token succeeds from the same origin. The difference between those two is the
  whole bug.
- **Fix it**, and prove the fix by an operator actually holding a connection — `conn:*` in Redis is
  the observable, not a green indicator in the UI.
- **Add a check that fails when this breaks again.** `smoke.sh` is the obvious home: sign in as an
  operator, connect, and assert the connection exists. It needs a credential, and `8-07`'s minted
  demo tenant is exactly a disposable one — which is a better answer than adding a fixture.
- **Consider whether the console should say more than "Offline".** It currently tells the operator to
  reload, which does not help, because reloading reproduces it exactly.

## Out of scope

- The `403` from the owner-eligibility probe. It is correct.
- Anything about the assignment engine, which is behaving correctly given no operators are present.
- The demo-credential flow, which works.

## Done when

- [ ] An operator signing into the console on the live deployment holds a connection, verified in
      Redis rather than in the UI.
- [ ] A visitor message on that tenant is assigned to that operator and can be answered, end to end,
      in a browser.
- [ ] A check exists that fails if no operator can hold a connection, and it has been seen to fail.
- [ ] The report says when this broke, or says plainly that it could not be established.

## Open questions

**Whether the indicator is honest.** It says "Offline", which was correct here — but a UI that
reports the connection state it *believes* it has is a different thing from one that reports what the
server thinks. If those can disagree, the fix should say which one an operator is looking at.
