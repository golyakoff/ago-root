# Console: widget configuration screen

- **Stage**: 11
- **Status**: ready
- **Depends on**: `11-01-widget-config-data-model-and-api.md` (the API this screen calls)

## Goal

An operator holding `site:configure` can open a settings screen in `ago-console`, see their site's
current widget primary color and launcher position, change either, save, and get confirmation — the
console half of Stage 11's own done-when bar. Without this, `11-01`'s API has no real caller other than
a test or a curl command, the same gap `6-03` deliberately left open for its own webhook API and named
as future work, not built there.

## Context to read first

`docs/adr/0023-console-framework-react.md` — names "tenant self-service configuration, starting with
`6-03`'s webhook endpoint registration and delivery history" as one of the three surfaces that justified
React. `6-03` shipped the API but explicitly deferred its UI ("A UI for any of this - explicitly
deferred per the Goal above, not forgotten"), which means **this item, not `6-03`'s own eventual UI
follow-up, is the first tenant self-service configuration screen actually built in `ago-console`** —
state this plainly, since a later session reading `adr/0023` alone would reasonably assume `6-03`'s
screen came first. `docs/backlog/5-06-console-framework-and-scaffold.md` — the existing routing shell
(login → queue → conversation view) this item adds a new authenticated route to, and the OIDC token
already attached to every API call. `docs/backlog/5-07-console-conversation-experience.md` and
`5-08-console-attachments-and-admin-role.md` — reuse whatever form/button styling and permission-gated
view pattern those already established (`5-08`'s admin-only conversation list is the existing precedent
for "a route only visible/reachable to a caller holding a specific permission"); this item is not a
design-system pass, matching `5-06`'s own deferral of visual polish until there is a concrete screen.
**Note added 2026-08-24**: `11-05-console-design-foundation.md` now makes that pass in this same stage.
This item still is not it — whichever of the two lands second adopts the other's result, and this screen
is the smaller retrofit of the pair.
`11-01`'s exact request/response shapes for `GET`/`PUT .../widget-config` once implemented.

## Scope

- A new authenticated route (e.g. `/settings/widget` — state the final path once written), reachable
  only to an operator whose token resolves `site:configure`, matching `5-08`'s existing pattern for a
  permission-gated view rather than inventing a new one. An operator without the permission does not see
  the entry point at all — client-side visibility only, since the server's own `403` on `11-01`'s
  endpoints is the actual enforcement (matching how every other client/server validation split in this
  codebase is already stated explicitly).
- The form itself: a color input (hex value, live swatch preview) and a position selector (the two
  enum values `11-01` defined, e.g. a two-option choice, not a free-text field). State explicitly what
  this validates client-side (malformed hex, UX-only) versus what `11-01`'s own endpoint already
  validates server-side (the actual source of truth) — the same split `10-03`'s onboarding form already
  documents for its own fields.
- Load current values on mount (`GET`), submit changes (`PUT`), a visible success/failure state on save
  (a toast or inline message — whatever `5-07`/`5-08` already established for this, reused rather than
  invented fresh).
- A short, static note in the screen itself (or its own doc comment) that a change here will not update
  an already-open widget on a visitor's page until that page is reloaded — `11-01`'s own ADR states why;
  this item surfaces that fact to the person making the change, since silently saying nothing about it
  would read as a bug report waiting to happen.

## Out of scope

- Any field beyond primary color and position — `11-01`'s own scope is exactly these two; if `11-04`'s
  open question resolves to more fields later, this screen's form grows to match, not before.
- Editing `allowed_origins` — still deferred (`5-01`, `10-04`), unrelated to this item.
- A live preview of the actual embedded widget rendering with the chosen color/position inside the
  console itself (e.g., an embedded demo iframe) — a real nice-to-have, not named in Stage 11's own
  done-when bar (which tests against "the embedded widget on their own page," not a console-side
  preview); flagged here as a reasonable future enhancement, not built speculatively now.
- A design-system pass beyond what `5-06`/`5-07` already established for forms and buttons.

## Done when

- [ ] Manually verified against the local cluster, the same "verified live, not asserted" bar `5-06`
      through `5-08` used: an operator holding `site:configure` opens the screen, sees the site's
      current values (or the built-in defaults if never set), changes the color and position, saves,
      and a subsequent page reload shows the new values persisted (proving the round trip through
      `11-01`'s real API, not just local component state).
- [ ] An operator without `site:configure` cannot reach the screen through the console's own navigation
      (client-side gating) and, if the route is hit directly, the underlying API call fails with the
      `403` `11-01`'s own server-side check already produces — the screen does not attempt to hide a
      failed call as if it succeeded.
- [ ] CI build+lint stays green, matching `5-06`'s own precedent for what `ago-console` automates versus
      verifies by hand.

## Open questions

None — this item's own scope follows directly from `11-01`'s already-defined API and `5-06`/`5-07`'s
already-established console patterns; the one real open product question (`11-04`) is explicitly not
this item's to answer, and this screen's own two fields are unaffected by how it eventually resolves.
