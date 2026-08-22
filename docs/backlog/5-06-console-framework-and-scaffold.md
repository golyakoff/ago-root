# Console framework decision and scaffold

- **Stage**: 5
- **Status**: blocked
- **Depends on**: `5-05-operator-oidc-authentication.md` for the login flow specifically (the
  scaffold/build-tooling/routing shell can start in parallel, but this item is not "done" until login
  actually works end to end)

## Goal

`ago-console` stops being an empty repository holding only a note. The framework decision the README
has deferred since the repository was created gets made and recorded as an ADR (the console README's
own words: "the choice will be recorded as an ADR when it is made"), and the resulting project scaffold
can build, run, and complete a real OIDC login against `5-05`'s IdP.

## Context to read first

`ago-console/README.md` (the deferral itself, and the two pointers it already gives: `api-design.md`
for protocol rules, `realtime.md` for what the console must implement). `authorization.md`'s operator-
identification row. `5-05`'s file for the exact OIDC flow the console redirects into. `repositories.md`
- `ago-console` produces a **static bundle**, deployed the same "versions/deploys independently"
reasoning that justified giving it its own repository at all.

## Scope

- An ADR: React or Angular, with the actual trade-off for *this* project (team of one, portfolio review
  context, a realtime-heavy SPA consuming SignalR + REST, no existing organisational preference to
  defer to) - not a generic pros/cons list copied from elsewhere. Author's decision, stated below with
  a recommendation.
- Project scaffold: build tooling, linting, a routing shell (login -> queue -> conversation view, even
  as placeholders `5-07` fills in), environment-based config for the API base URL and the OIDC client
  id/issuer (never a secret baked into a static bundle - the OIDC client id is public by design, same
  status as the widget's site key, but the API base URL and any per-environment config still should not
  be hardcoded).
- Login: redirect to the chosen IdP, handle the callback, hold the resulting token, attach it to the
  operator hub connection exactly as `realtime.md`'s existing `?access_token=` query-string mechanism
  expects (no server-side change needed here - `5-05` already made the server accept a real OIDC
  token, this item is the client half of the same exchange).
- CI: build + lint on every push, matching `ago-platform`/`ago-chat`'s own CI precedent
  (`docs/conventions/git-workflow.md`) even though this repository has no backend test suite yet.

## Out of scope

- Queue, active-conversation list, message send/receive, presence, history - `5-07`, the actual chat
  functionality this shell will hold.
- Attachment UI, admin role management - `5-08`.
- A design system / component library choice beyond what the framework itself needs to run - defer
  visual polish decisions to `5-07`, where there is an actual UI to apply them to.

## Done when

- [ ] `adr/00XX` written and accepted, naming the framework and why, in `ago-console` (or `ago-root`,
      matching wherever this project's other ADRs live - confirm `docs/adr/` in `ago-root` is still the
      single ADR home even for a decision scoped to a different repository, since `repositories.md`
      does not carve out a separate ADR log per repo).
- [ ] `ago-console` builds and runs locally against the local cluster's API.
- [ ] A real login against `5-05`'s IdP completes and the resulting token successfully opens
      `/hubs/operator` - proven by hand against the local overlay (this is a frontend scaffold; there
      is no automated test harness for "a browser can complete an OAuth redirect" worth building here,
      matching `CLAUDE.md`'s own rule that UI changes are verified live, not just asserted).
- [ ] CI builds and lints on push.

## Open questions

**Needs the author's decision**: React or Angular. Recommendation: **React** - the wider ecosystem
around SignalR client bindings and realtime-UI patterns (optimistic updates, virtualized message lists)
has more prior art to draw on for a solo-maintained portfolio project, and its component model maps
directly onto this app's shape (conversation list, message thread, presence indicators as independent,
composable pieces) without Angular's heavier DI/module ceremony for an app this size. Angular is a
perfectly defensible choice too (stronger opinions out of the box, less decision fatigue on tooling) -
state the reasoning either way in the ADR.
