# The operator console never connects to the operator hub, so nobody can answer

- **Stage**: 5
- **Status**: **fixed, not deployed** (2026-08-26). Cause found and corrected, a check that fails on it added and seen to fail. The end-to-end demonstration needs a deploy.
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

## The cause

`OperatorHub.OnConnectedAsync` validated the operator's connection `Origin` against **the tenant's own
`AllowedOrigins`** — the list of pages allowed to embed that tenant's *widget*. An operator does not
connect from a tenant's page; they connect from the console. Any tenant whose list did not happen to
contain the console origin therefore had every operator connection aborted by `Context.Abort()`
immediately after a successful SignalR handshake.

That abort is a **clean close**, which is why every signal was silent: nothing logged (SignalR only
logs failures, and this was a success followed by a close), nothing fell back to another transport
(the transport worked perfectly), and nothing registered in Redis (`OnConnectedAsync` aborted before
`connectionRegistration`).

**The hand-rolled WebSocket did not actually differ.** It reached `OPEN` and the observation stopped
there. The server's close arrives one frame later: an instrumented capture of the console's own socket
shows `open` → `{}` (handshake ack) → `{"type":7}` (SignalR close) → `close code=1000 clean=true`.

## When it broke

**The wrong check is as old as `5-01`** (`d2f268a`, per-site CORS from the database) — latent, because
it only refuses a tenant whose origins lack the console. The seeded `8-05` tenants *do* list it, which
was verified rather than assumed: a visitor-session POST from `https://console.reserve-me.ru` answers
`201` for `demo_site` and `demo_site2`. So every operator anybody had ever signed in as worked, and
`5-07`, `5-16` and `11-06` were all built and observed against a working connection.

**The outage is hours old.** It began when `8-09` turned `DemoTenant__Enabled` on (`4a9869d`,
2026-08-26): from that moment the README's front door hands a stranger a *minted* tenant, whose
`AllowedOrigins` is exactly `["https://demo-shop1.reserve-me.ru"]`. The same visitor-session probe
answers `403 origin-not-allowed` for a freshly minted key and `201` for a seeded one — the two halves
of the same experiment.

This corrects one thing this item ruled out: **it *is* the minted tenant.** The worker log line about
seeded operators having no connections is the disconnect sweep listing operators nobody was signed in
as, not evidence that they could not connect.

## Done when

- [ ] An operator signing into the console on the live deployment holds a connection, verified in
      Redis rather than in the UI.
      *Needs the deploy. The mechanism is fixed and covered by tests, and the smoke check below fails
      against the current deployment and is expected to pass after.*
- [ ] A visitor message on that tenant is assigned to that operator and can be answered, end to end,
      in a browser. *Same reason.*
- [x] A check exists that fails if no operator can hold a connection, and it has been seen to fail.
      *`smoke.sh` gained an "Operator hub" section: mint a tenant (`8-07`), sign in through Keycloak,
      negotiate, hold a **Server-Sent Events** stream open, complete the handshake, and fail if the
      stream carries SignalR's close frame. Run against the live deployment it prints
      `FAIL the operator hub accepted the handshake and then closed the connection`.*
- [x] The report says when this broke, or says plainly that it could not be established. *Above.*

## Why SSE, and why not negotiate

Negotiate succeeded throughout the outage, so any check that stops there is blind to this by
construction — which is exactly what the existing visitor check is, and why 12/12 stayed green.

Server-Sent Events is the one transport that carries a real hub connection (`OnConnectedAsync` runs
for it) while staying pure HTTP, so `curl` alone can tell the two apart. Measured against the live
deployment before the check was written: an allowed origin holds the stream open until the client
times out; a refused one flushes `data: {}` then `data: {"type":7}` within about a second.

Two earlier attempts were **discarded for being false passes**, which is worth recording because both
looked right: a long-polling probe returned an empty body whether the connection was healthy, refused,
or never established at all; and a follow-up POST answered `200` in every case. A check that cannot
tell "alive" from "never started" is worse than none.

**The check uses a minted tenant deliberately.** Built on the seeded credential it would have stayed
green through the entire outage.

## Open questions

**Whether the indicator is honest** — answered: **yes, and that was not the problem.** The badge
reports the client's own view of its connection, which is the only thing a browser can know, and here
the client and the server agreed completely: the server closed the connection and the client said so.
The failure was not dishonesty, it was **silence** — `OperatorConnectionProvider` caught the rejection
from `start()` and discarded it, so the single most useful fact in the whole incident (what the
connection failed with) existed for one instruction and was then thrown away. That `catch` now logs.
The "Offline" copy also stopped telling operators to reload, which reproduced the fault exactly.
