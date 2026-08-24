# ADR-0023: React for `ago-console`

- **Status**: Accepted
- **Date**: 2026-08-23
- **Stage**: 5

## Context

`ago-console`'s own README has deferred this since the repository was created ("the choice will be
recorded as an ADR when it is made" - `5-06`'s own text). The choice was originally framed narrowly:
a solo-maintained operator console - login, waiting queue, conversation view - consuming
`Ago.Chat.Api`'s REST endpoints and `/hubs/operator` over SignalR.

That framing has since widened. The product is intended to go beyond a portfolio demonstration to
real commercial use, and `ago-console` is now expected to grow three genuinely different surfaces
over time, not one:

1. **The operator console** itself - realtime-heavy, `/hubs/operator` (`realtime.md`'s client
   protocol: `clientMessageId`, sequence-ordered resume, presence).
2. **Tenant self-service configuration** - starting with `6-03`'s webhook endpoint registration and
   delivery history, the shape of thing that grows into more tenant-facing settings over time.
3. **An internal operations view**, for the author as the operator of the service itself - which
   tenants exist, on which tier, spotting abuse, granting bonus features. Classic admin-dashboard
   territory: data tables, filters, forms, permission-gated views - not realtime at all.

None of this changes `vision.md`'s existing exclusions (no billing system, no CRM integrations, no
mobile apps) - it is about who can see and configure what inside the product that already exists, not
about adding those excluded capabilities.

## Decision

**React**, for `ago-console` as a whole - all three surfaces above, one framework, not a split.

The deciding factor is not the operator console alone, where the two frameworks are close to a wash:
`@microsoft/signalr` is plain JavaScript with no framework opinion (already proven in `ago-widget`,
`5-09`/`5-10` - the same client library, zero framework-specific glue code needed), so neither
framework has a realtime-binding advantage worth weighing heavily.

The deciding factor is surfaces 2 and 3. Both are conventional CRUD-and-data-table admin-dashboard
problems, and the React ecosystem has mature, purpose-built frameworks for exactly that shape of app
(`react-admin`, `Refine`, and the wider `shadcn`/`TanStack Table` component space) - a solo maintainer
gets working data tables, filtered lists, forms and auth-gated views largely assembled, rather than
building that structure by hand. Angular's own reactive forms are a genuine strength for complex forms
specifically, but nothing in its ecosystem matches the maturity of React's purpose-built admin
frameworks for the dashboard-and-data-table shape surfaces 2 and 3 actually are - and for a service the
author needs to operate for real (watching for abuse, managing tenants), time to a working internal
tool matters more than architectural elegance.

"Without overhead" (the author's own framing when this was decided) cuts two ways, and both favour
React here:

- **Runtime weight**: React's core is lighter than Angular's (React + ReactDOM vs. Angular's baseline
  framework runtime) - though largely moot for a login-gated console with no bundle budget the way
  `ago-widget` has one.
- **Development overhead**: the more relevant cost for a solo maintainer building and maintaining
  three surfaces - React's ecosystem lets tenant-management and internal-admin screens reuse mature,
  purpose-built components instead of hand-building CRUD/table/form scaffolding three times over.

The trade Angular would have offered - a batteries-included router/DI/forms/HTTP stack, less decision
fatigue per feature - is real, but it pays off less here than React's ecosystem depth for exactly the
two surfaces this decision was actually about.

## Consequences

- `5-06`'s own scaffold work proceeds against React - build tooling, routing shell, environment-based
  config for the API base URL and the OIDC client id (`adr/0022`'s Keycloak token, `5-05`).
- `6-03`'s webhook self-service screens and any future internal-admin work in `ago-console` should
  reach for `react-admin`/`Refine`-shaped patterns (a specific package choice is deferred to whichever
  item first needs one - `naming-and-structure.md`'s "no NuGet package without saying what it
  replaces" spirit applies here too, evaluated when there is a real screen to build, not speculatively
  now).
- `ago-widget` stays framework-free by design (`embeddable-widget` skill's bundle-budget rule) -
  this decision does not change that; the two frontends solve different problems with different
  constraints and were never going to share a framework choice.
- **`10-03`**: a fourth console surface this ADR did not originally anticipate - a public,
  pre-account, pre-authentication route (`/signup`, `/onboarding`), reachable by a visitor with no
  `ago-console` session at all. It still runs on the same React app/build as the other three surfaces
  (no framework or tooling implication follows from it), but a later reader of this ADR alone should
  not be surprised that an unauthenticated route exists in this repository - the three surfaces listed
  above all assumed an already-authenticated operator, and this one deliberately does not.
- Cost: React's own "assembly required" nature means routing, state management, and form handling are
  each a small decision `5-06`'s own scaffold work has to make explicitly, rather than inheriting
  Angular's opinions for free.

## Alternatives considered

- **Angular** - the closer call than it might look for a `team of one, portfolio review context`
  framing alone; genuinely strong reactive forms, less decision fatigue on tooling. Rejected once the
  scope widened to include two dashboard-shaped admin surfaces, where React's ecosystem depth
  (`react-admin`/`Refine`) outweighs Angular's batteries-included advantage.
- **A different framework per surface** (e.g. Angular for the realtime console, React for admin
  screens) - maximum fit per surface, at the cost of a solo maintainer carrying two frontend
  toolchains, two build pipelines, and no shared component vocabulary between screens a real operator
  and a real tenant will both eventually use. Rejected for the same reason `adr/0013` rejected
  splitting the backend into more deployables than its own failure profiles justified - the "one
  repository, one framework" seam already exists (`ago-console` vs. `ago-widget`) and does not need a
  second one inside it.
