# AGO Calendar: tenant/operator console and the embeddable booking widget

- **Stage**: 20
- **Status**: ready
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
- **Booking widget** (a new `ago-calendar-widget` repository or package — state which, following
  `repositories.md`'s own "new repository only when it deploys independently" test; a widget embedded
  on a stranger's site with its own release cadence independent of the console clears that bar the same
  way `ago-widget` did for AGO Chat): a slot picker (worker photo/name, available times from the
  materialized `Available` events) and a booking form (name, phone) calling `20-03`'s booking endpoint.
  TypeScript, Shadow DOM, small bundle — the same isolation reasoning `embeddable-widget` skill and
  `vision.md`'s own AGO Chat description already establish, reused rather than reinvented for a second
  embeddable script.
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

- [ ] A tenant can create a calendar, a worker, a service, and a working-hours rule from the console,
      end to end against a running `ago-calendar` backend.
- [ ] An operator can see the shared pending-bookings queue and successfully reject a booking from the
      console, verified against real data (two calendars, confirming the queue is not scoped to one).
- [ ] A plain HTML page with one script tag, pointed at a seeded demo tenant, can complete a real
      booking through the widget against the local cluster — the same "stranger's page, one script tag"
      bar `vision.md`'s own AGO Chat "done when" already holds itself to.
- [ ] `Ago.Calendar.Integration.Tests` (layer 1 CORS) and an equivalent to `5-01`'s own `OriginAuthorizationTests`
      (layer 2, cross-tenant rejection) both pass, proving the widget cannot be tricked into booking
      against a tenant its origin was never approved for.

## Open questions

Whether the console is a new app or a new area of `ago-console`, and whether the widget is a new
repository or a new package inside `ago-widget` — both named above as real decisions this item makes
and records, not genuinely blocking open questions (the repository-topology rule already answers them;
this item just has to apply it and state the answer once written).
