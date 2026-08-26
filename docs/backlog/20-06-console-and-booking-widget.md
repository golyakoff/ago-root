# AGO Calendar: tenant/operator console and the embeddable booking widget

- **Stage**: 20
- **Status**: done
- **Depends on**: `20-04-confirmation-sweep-and-operator-queue.md` (the pending-queue read and
  reject/cancel/no-show actions this console surfaces), `20-05-sms-confirmation-delivery.md` is not a
  hard dependency but should land first in practice so the console's own booking-confirmation view has
  something real to show beyond a bare status change

## Goal

A tenant can configure calendars, workers, services and working hours, and see/act on the pending-
bookings queue, from a real console — and a visitor can actually book, from a real embeddable widget on
the tenant's own site, the same "one script tag" shape `vision.md`'s own AGO Chat description uses.
This item is Stage 20's own analogue of AGO Chat's Stage 5 (the two frontends), scoped to what a first
usable version of AGO Calendar needs, not a full parity rebuild of Stage 5's own attachment/thumbnail
depth.

## Context to read first

`docs/adr/0023-console-framework-react.md` — reused unchanged; no new framework decision for this
console, state explicitly that this item is not re-litigating that choice. `docs/adr/0022-oidc-keycloak-operator-authentication.md`
and `docs/backlog/5-05-operator-oidc-authentication.md` — the exact OIDC mechanism this console's own
login reuses, pointed at the same Keycloak realm AGO Chat already uses (one identity provider across
products, `adr/0027`'s own point) but resolved against `ago-calendar`'s own `operators` table via its
own claims transformation (`20-01`). `docs/backlog/5-01-per-site-cors.md` in full — the two-layer CORS
model (browser-facing CORS policy plus an in-app tenant-origin check, since CORS itself cannot be the
tenant-isolation boundary) this item's own booking widget needs, adapted from "site" to "tenant." Read
its own found-live "CORS preflight cannot see the request body" gotcha before designing the widget's
own booking-lookup endpoint, since the same timing problem applies here. `docs/architecture/edge.md`'s
"What the edge must not be responsible for" section — CORS/tenant-origin logic belongs in the app, not
the ingress, unchanged from AGO Chat's own precedent.

## Scope

- **Console** (a new `ago-calendar-console` app, or a new area inside `ago-console` if implementation
  finds that genuinely simpler — decide and state which, with the reasoning; the product/repository
  split established by `adr/0012`/`repositories.md` argues for a separate app, since `ago-console` is
  `ago-chat`'s own static bundle with its own release cadence, but a combined "AGO operator hub" login
  experience has real UX merit worth naming even if this item does not build it):
  - Tenant setup: create/edit calendars (`BufferMinutes`), workers, services, working-hours rules.
  - Operator view: the shared pending-bookings queue (`20-04`), reject/cancel/no-show actions.
  - Manual calendar editing surface for `20-02`'s `DeleteDayOffHandler`/`EditDayBoundaryHandler`.
- **Booking UI, as a module inside `ago-widget`** — **not** a new repository and **not** a second
  script tag. Decided 2026-08-26; the reasoning is in Open questions below and in
  `reviews/2026-08-26-platform-boundary.md`, and it is a product-model decision rather than a
  repository-topology one, so this item applies it rather than re-deciding it.
  A slot picker (worker name, available times from the materialised `Available` events) and a booking
  form (name, phone) calling `20-03`'s booking endpoint. TypeScript, Shadow DOM, small bundle — the
  same isolation reasoning the `embeddable-widget` skill already establishes, and now literally reused
  rather than restated, since this ships inside the script that already applies it.
  **Watch the bundle budget**: `ago-widget` has one (45 KB gzipped, 21.0 KB used as of `5-17`), and
  this is the first feature that could plausibly threaten it. If it does, that is a finding worth a
  lazily-loaded module rather than a reason to reopen the decision above.
- Per-tenant CORS and the in-app tenant-origin check, adapted from `5-01`'s exact two-layer model:
  layer 1 (`ICorsPolicyProvider`, allow an origin if any tenant's `AllowedOrigins` contains it) and
  layer 2 (once a request resolves which tenant/calendar it is for, reject on an origin mismatch against
  *that* tenant specifically) — both required, matching `5-01`'s own finding that layer 1 alone is not a
  real tenant boundary.

## Out of scope

- Any combined "one login for both products" convenience beyond reusing the same Keycloak realm — named
  in `adr/0027`'s own Consequences as a real, deferred gap; this item does not attempt to close it.
- File attachments, thumbnails, or anything from AGO Chat's own Stage 5 depth that has no analogue in
  AGO Calendar's own product spec (no attachments exist in this domain).
- The unified operator queue spanning AGO Chat and AGO Calendar — `21-02`, explicitly deferred and
  explicitly not a byproduct of this item existing.

## Done when

- [x] A tenant can create a calendar, a worker, a service, and a working-hours rule from the console,
      end to end against a running `ago-calendar` backend.
      `ConsoleEndpointTests.ATenant_CanCreateACalendarAWorkerAServiceAndAWorkingHoursRule` — over real
      HTTP against the real host on a real Postgres, reading the result back through the console's own
      configuration screen rather than through the database. The console's own half of it is
      `ConfigurationPage.test.tsx`, which asserts the request each form builds.
      **Not verified through a browser against a signed-in Keycloak session** — see the note below.
- [x] An operator can see the shared pending-bookings queue and successfully reject a booking from the
      console, verified against real data (two calendars, confirming the queue is not scoped to one).
      `ConsoleEndpointTests.AnOperator_SeesThePendingQueueAcrossEveryCalendarAndCanRejectFromIt`, with
      two calendars exactly as this clause asks, plus
      `AnOperator_CannotRejectAnotherTenantsBooking`. Same browser caveat.
- [x] A plain HTML page with one script tag, pointed at a seeded demo tenant, can complete a real
      booking through the widget against the local cluster — the same "stranger's page, one script tag"
      bar `vision.md`'s own AGO Chat "done when" already holds itself to.
      **Done, and one word of it is not true: "cluster".** The booking was completed against
      `Ago.Calendar.Api` run from the command line over a real Postgres and a real Redis, not against
      the Kubernetes overlay — `ago-deploy` carries no AGO Calendar manifests at all, and adding them
      is not this item's change. What was proven, and how: the *built* `dist/ago-chat.js`, loaded by
      `demo/booking.html`'s single script tag from `http://localhost:8097`, walked the whole flow
      (service → worker → time → phone → name) and produced a row in `events` at
      `PendingConfirmation` with a lead card beside it. The chat half of the same tag failed
      throughout, because `Ago.Chat.Api` was not running — which incidentally demonstrates that
      booking needs no conversation and that the failure is contained rather than fatal.
      The last step was driven through jsdom rather than a real browser, because the shared browser
      pane was at its tab cap with other sessions' tabs and closing one was not this session's to do.
      Both CORS layers *were* observed at the HTTP level with a real browser's headers — see below.
- [x] `Ago.Calendar.Integration.Tests` (layer 1 CORS) and an equivalent to `5-01`'s own `OriginAuthorizationTests`
      (layer 2, cross-tenant rejection) both pass, proving the widget cannot be tricked into booking
      against a tenant its origin was never approved for.
      `TenantOriginCorsPolicyProviderTests` (layer 1, exercising `GetPolicyAsync` directly — the same
      call `5-01` made, and for the same reason) and `OriginAuthorizationTests` (layer 2, over real
      HTTP against the real host, on both the reads and `20-03`'s booking write).
      Also observed live, which is the version worth quoting: a request carrying **tenant B's own
      approved origin** against tenant A's public key came back
      `HTTP/1.1 404` *with* `Access-Control-Allow-Origin: http://localhost:8098` — layer 1 handing the
      page permission to read a response that layer 2 had already refused. `5-01`'s finding that layer
      1 is not a tenant boundary, reproduced at runtime rather than asserted.

## What was not verified, stated where it cannot be missed

- **Nobody has signed into this console with Keycloak.** Doing so needs an `ago-calendar-console`
  client in the realm, which lives in `ago-deploy`'s realm import — a repository this item did not
  open. What *is* proven is everything on this side of that redirect: the claims transformation
  resolving a `sub` against `ago-calendar`'s own `operators` table, the `calendar-operator` policy
  refusing a subject it cannot resolve, and every handler's permission check, all against real rows
  (`ConsoleEndpointTests`, which stands in for exactly one thing — proof that Keycloak signed a
  token — and leaves the rest running for real).
- **Nothing was deployed**, and `ago-deploy` has no AGO Calendar manifests. The runbook section this
  item adds to `local-dev.md` is the command-line loop, and says so.
- **A real browser never rendered the booking panel.** jsdom did, against the real API, using the
  real built bundle.

## Follow-up this item creates

- A Keycloak client and a realm-import entry for `ago-calendar-console`, plus `ago-deploy` manifests
  for `Ago.Calendar.Api`/`Worker` and the console bundle. Until those exist, `20-06`'s console cannot
  be signed into by a human and `.env.production` cannot honestly be written (`adr/0051`).
- The OIDC duplication between the two consoles, recorded in `adr/0064`'s Consequences with the
  condition under which a shared package becomes the right answer.

## Open questions

~~Whether the console is a new app or a new area of `ago-console`~~ — **decided: a new repository,
`ago-calendar-console`** (`adr/0064`). `repositories.md`'s own test answers it: the bundle versions
and deploys independently of `ago-console`, which is AGO Chat's. The argument that settled the
*widget* half deliberately does not transfer, and noticing why is the useful part — the review's
measured duplication was the realtime protocol primitives, and AGO Calendar has no realtime client at
all. The duplication this decision *does* cost is the OIDC plumbing, and the ADR names it rather than
leaving it to be found.

**The widget half is decided, 2026-08-26** (`reviews/2026-08-26-platform-boundary.md`, third pass).
**There is no second widget and no second script tag.** A shop pastes one embed; booking is reached
through it.

The reason is the product model rather than repository topology, which is why it is settled here
rather than left to this item's judgement. Booking must be possible from **any** channel — the
widget, Telegram, MAX, SMS — and the author's own product combinations include a shop running with
**no widget at all**, reaching AGO Chat's API through a channel adapter. A booking-only widget with
its own embed would be building the one shape the product model rules out: a flow that exists only
where there is a widget.

Two consequences, both narrowing this item:

- The booking UI is a **module inside `ago-widget`**, not a new `ago-calendar-widget`. The review
  measured 53% of the existing widget as reusable (18% carrying no judgement at all) — transport,
  session, storage, reconnect. And `ago-widget`'s protocol primitives are **already** duplicated
  verbatim into `ago-console`; a third copy is the outcome to avoid, not a cost to accept.
- Whatever the slot picker renders must be expressible as **conversation content a channel with no UI
  can also carry** (`14-06`). A grid that only works in a browser is a grid `21-01` cannot reuse, and
  `21-01` is the item that has to work over plain text.
