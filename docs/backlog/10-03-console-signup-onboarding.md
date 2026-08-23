# Console signup and onboarding UI

- **Stage**: 10
- **Status**: ready
- **Depends on**: `10-01-self-registration-identity-flow.md` (the Keycloak registration entry point
  and the "authenticated but not yet an operator" token state this UI must detect), `10-02-site-and-operator-registration.md`
  (the endpoint this form calls)

## Goal

A visitor with no `ago-console` session can reach a public "Sign up" entry point, complete Keycloak's
own registration form, land back in `ago-console` holding a token the console recognises as
"authenticated, but not yet an operator" — a state `5-06`/`5-07`'s existing login flow never had to
handle, since every token it saw before this item belonged to an already-provisioned operator — and
complete a short "set up your site" form (site name, embed origin) that calls `10-02`'s endpoint before
being routed into the normal queue view exactly as a returning operator would be.

## Context to read first

`docs/adr/0023-console-framework-react.md` — it names three console surfaces (the operator console,
tenant self-service configuration starting with `6-03`, and an internal operations view), and all three
assume an already-authenticated operator. **This item is explicitly a fourth surface `adr/0023` did not
anticipate: a public, pre-account, pre-authentication route inside `ago-console`.** State this plainly
in whatever this item writes, since a later session reading `adr/0023` alone would not expect a public
unauthenticated route to exist in this repository at all. `docs/backlog/5-06-console-framework-and-scaffold.md`
— the existing login/callback handling this item extends rather than replaces (routing shell: login →
queue → conversation view). `docs/backlog/5-07-console-conversation-experience.md` — the queue view this
flow must end at, unchanged. `docs/architecture/realtime.md` — confirms nothing about the console's
existing token-to-hub-connection wiring changes; this item only changes what happens *before* that
wiring runs for a first-time caller.

## Scope

- A public route (no auth guard) presenting a "Sign up" link/button that redirects to Keycloak's
  registration endpoint (`10-01`'s realm config) — not a console-built form. The console never collects
  a password; that stays entirely on Keycloak's hosted page, matching `10-01`'s own recommendation.
- Callback handling: after Keycloak redirects back with a token, the console's existing "resolve who I
  am" step must distinguish **three** states, not the two it handles today: (a) a token that resolves
  to a real operator — existing behaviour, route to the queue, unchanged; (b) a token that authenticates
  against Keycloak but resolves to no operator (`10-01`'s `RequireKeycloakIdentity`-eligible state) —
  new: route to the "finish setting up your site" form; (c) no token, or an invalid one — existing "go
  log in" behaviour, unchanged. State explicitly, once implemented, how (b) is actually detected
  client-side — the console must not re-derive server-side authorization logic itself (e.g. inspecting
  JWT claims directly to guess whether an operator exists); prefer a cheap, purpose-built check or
  reading the specific error/response shape `10-02`'s endpoint's own contract already provides.
- The onboarding form itself: site display name, one embed origin. State explicitly what this item
  validates client-side versus what `10-02` already validates server-side — client-side checks are
  UX-only (e.g. "looks like a URL, please try again"), never the actual source of truth for what gets
  accepted, matching how every other form in this codebase already treats client/server validation.
- On success, route into the same queue view `5-07` built, exactly as a normal login would — no
  separate "new operator" branch anywhere downstream of this point; onboarding is a one-time detour
  into the same destination every login already reaches.

## Out of scope

- Anything about which fields Keycloak's own hosted registration page shows (email, password, confirm
  password) — that page belongs to Keycloak, not this console, per `10-01`.
- Editing the site's `allowed_origins` after signup, registering a second site, inviting additional
  operators — none of these exist anywhere yet (`10-02`'s own Out of scope), so there is nothing here
  to build a UI for.
- A design-system pass beyond what `5-06`'s scaffold already established. `5-06` deferred visual polish
  until there was a concrete screen to apply it to; this item is that screen, but a full design pass is
  still not this item's job — reuse whatever `5-07` already established for form/button styling.

## Done when

- [ ] Manually verified against the local cluster, the same "verified live, not asserted" bar
      `5-06`/`5-01` used: a real browser completes Keycloak's registration form, lands back in
      `ago-console` in the new onboarding state (not silently treated as a login failure), completes
      the site-setup form, and ends up in the queue view able to see its own (empty) waiting queue.
- [ ] A returning, already-provisioned operator's normal login is unaffected — proven by running
      through `5-06`'s existing login flow once this item is merged, confirming state (a) still routes
      exactly as it did before this item existed.
- [ ] CI build+lint stays green, matching `5-06`'s own precedent for what this repository automates
      versus verifies by hand for `ago-console`.

## Open questions

None — this item depends on `10-01`/`10-02`'s contracts existing first; no new product-shape decision
is left once those are answered.
