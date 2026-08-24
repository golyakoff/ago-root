# Public demo page and operator console, throwaway login

- **Stage**: 8
- **Status**: done
- **Depends on**: `8-01-public-deployment-target.md` — needs a live, TLS-terminated public API and
  Keycloak instance to point the widget and console builds at; nothing about this item's own scope
  is unresolved independent of that

## Goal

A stranger who was handed only a URL can open a page, type a message into the widget, and — from a
second tab or device — log into a public `ago-console` with a documented throwaway credential and
answer as the operator, in real time, with no local setup, no VPN, and no account creation. This is
`roadmap.md`'s own Stage 8 done-when bar: "a stranger with the link can hold a conversation with the
operator console."

## Context to read first

`backlog/5-09-widget-bootstrap-and-messaging.md` — its `ago-widget/demo/` page is deliberately
*hostile* (colliding CSS, globals) to prove Shadow DOM isolation; this item's public page is a
different, friendlier one built for a visitor to actually use, not an isolation test, and must not
be confused with or replace that one. `backlog/5-06-console-framework-and-scaffold.md`,
`5-07-console-conversation-experience.md`, `5-08-console-attachments-and-admin-role.md` — what the
console already does (login, queue, conversation view, attachments, per-site admin view); this item
deploys that, it does not extend it. `backlog/5-05-operator-oidc-authentication.md` and
`runbooks/local-dev.md`'s "Getting a working operator session locally" section — the
`demo-operator`/`demo-operator-password` direct-grant credential already documented and already
treated as safe to publish; this item reuses that exact value against the public Keycloak instead of
inventing a new one. `architecture/edge.md`'s CDN row for `widget.js`. `runbooks/local-dev.md`'s
"Running the widget demo locally" and "Running the console locally" sections — the environment-based
config mechanism (`AGO_API_BASE_URL`, OIDC issuer/client id) both already use, which this item points
at a public URL instead of `localhost`.

## Scope

- Build the `ago-widget` bundle with `AGO_API_BASE_URL` set to `8-01`'s public API — the same
  build-time config mechanism `local-dev.md` already documents, no new machinery. Host it wherever
  `8-01`'s edge already serves static content, or a CDN if the hosting choice doesn't include one
  (state which was used).
- A demo landing page — not `ago-widget/demo/`'s hostile isolation page, a plain, presentable page
  embedding the same `<script data-site="...">` tag against the public demo site's public key, with
  enough copy that a visitor understands what they're looking at without having read the README
  first.
- Build `ago-console`'s static bundle (`5-06`'s scaffold already produces one) pointed at the public
  API base URL and the public Keycloak issuer/`ago-console` client — the same environment-based
  config `5-06` already established.
- Register the public console's real origin in Keycloak's `ago-console` client (`redirectUris`,
  `webOrigins`) — the same two-registration requirement `local-dev.md` already documents for
  `localhost:5173`, applied to the public origin instead. Add the public console's and demo page's
  real origins to the demo site's `AllowedOrigins` (`5-01`'s per-site CORS policy).
- Document the throwaway login directly on the demo/landing page — shown in the page itself, not
  left for a visitor to dig out of a README. It is the exact `demo-operator`/`demo-operator-password`
  value `5-05` and `local-dev.md` already established and already treat as safe to publish
  (`repositories.md`'s "no secrets, ever" rule was already satisfied by this value once, for the same
  reason it stays satisfied here: it was never a stand-in for a real credential).
- State explicitly, on the page or in the linked runbook, that the demo tenant is the only tenant
  this deployment holds — anything a visitor does through the throwaway login only ever touches this
  dedicated demo site's data, never a real tenant's. This is multi-tenancy's own isolation
  (`vision.md`'s "Site" actor) making the throwaway login safe by construction, not a new mechanism
  this item has to build.

## Out of scope

- Any change to the widget's or console's own application code — both ship as-is from Stage 5; this
  item is deployment and configuration only. A real product bug found while doing this becomes its
  own backlog item, not a fix folded in here.
- Automatically resetting or cleaning the demo tenant's data on a schedule — a real feature with its
  own design questions (what "clean" means, how often, whether an in-flight visitor conversation
  should survive it). If real use of this deployment later shows it is needed, that is a new backlog
  item, not something invented here speculatively.
- Tenant self-service (`6-03`'s webhook registration/delivery-history API) or an internal-admin view
  (`adr/0023`'s named third console surface, "internal operations view") — neither has a UI yet
  (`6-03`'s own Out of scope says a UI is "explicitly deferred, not forgotten"), so there is nothing
  built to publicly deploy for either.

## Done when

- [x] From a machine on a network unrelated to the deployment (not the same LAN/VPN), the demo page
      loads, the widget connects, and a message sent from it is visible — verified live
      (`demo-shop1.reserve-me.ru`, real message confirmed in Postgres). This did **not** work on the
      first pass — see "Found live" below; `5-12` is the real fix that made it actually work, not just
      appear to.
- [x] From the same unrelated network, the public console URL redirects to the public Keycloak login,
      the documented throwaway credential logs in, and the operator sees the message sent above in
      the queue/conversation view and can reply — verified live, both directions, matching `5-09`'s
      and `5-06`'s own "verified live, not asserted" bar.
- [x] The demo/landing page states the throwaway credential in the page itself, not only in a linked
      doc.
- [x] A runbook section (`runbooks/public-deploy.md`'s step 12) covers rebuilding and republishing the
      widget/console static bundles specifically — a different mechanism from `8-01`'s backend
      redeploy, documented separately.

## Found live (not assumed away)

The demo page, console, TLS, CORS, and Keycloak registration all worked on the first real pass — but
the actual chat conversation did not: a visitor's message consistently failed to reach the operator.
Two independent causes, both found and fixed live, both documented as their own items rather than
folded into this one silently (`5-11`'s own precedent for "a real bug found while proving deployment
work becomes its own backlog item"):

- **`5-12`** — the real, deterministic cause: the widget's own client code never finished wiring
  `clientMessageId` through to `VisitorHub.SendMessageAsync`'s now-4-parameter signature (`5-07`), so
  every real send failed at the hub-invocation layer before ever reaching the handler. This is a
  widget application bug, not a deployment/config issue — exactly the kind `8-02`'s own Out of scope
  said "becomes its own backlog item, not a fix folded in here."
- **A one-time, self-resolving red herring along the way**: immediately after applying this item's own
  Gateway manifest changes (the new SANs/routes), a handful of WebSocket connections dropped within
  seconds of opening — traced to NGINX Gateway Fabric reloading its data-plane config in response to
  the TLS Secret changing underneath it (a normal `nginx reload`, which does not preserve in-flight
  long-lived connections). Confirmed transient, not structural, by testing again once the config
  settled: a fresh connection through the same public route stayed open and stable. Not a persistent
  Gateway problem — investigated and ruled out before `5-12`'s real cause was found.

## Open questions

None — the mechanism (environment-based build config, Keycloak client registration, per-site CORS
allow-list) already exists from Stage 5 and is only being pointed at a new, public environment here,
not redesigned.
