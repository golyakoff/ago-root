# Console: owner operations view

- **Stage**: 12
- **Status**: ready
- **Depends on**: `12-01-platform-owner-identity-and-access.md` (the owner identity the console must
  detect and gate against), `12-02-cross-tenant-operations-read-api.md` (the endpoint this view calls)

## Goal

The platform owner, logged into `ago-console` with the identity `12-01` establishes, reaches a new,
owner-only screen showing every site with its tier, seats, conversation and message volume, storage
bytes, and activity timestamps — sourced from `12-02`'s endpoint — in one data table, with no separate
database access. This is the third console surface `adr/0023` already named when the framework decision
was made ("an internal operations view... which tenants exist, on which tier, spotting abuse") — this
item is where that surface is actually built, not a new design decision about the console's shape.

## Context to read first

`docs/adr/0023-console-framework-react.md` in full — it names this exact surface and recommends
reaching for `react-admin`/`Refine`-shaped patterns for "the dashboard-and-data-table shape" this screen
literally is; read its Consequences section for that pointer. Note explicitly, in whatever this item
writes: `adr/0023`'s Context also mentions "granting bonus features" as part of this surface's eventual
territory — that is **not** part of this item's scope (see Out of scope); nothing in `roadmap.md`'s
Stage 12 done-when asks for it, and this item should say so plainly rather than silently under-delivering
against `adr/0023`'s original framing. `docs/backlog/5-06-console-framework-and-scaffold.md` — the
existing routing shell (login → queue → conversation view) this item adds a fourth route to, and the
existing "resolve who I am" callback logic `10-03` already extended once for a different new state; this
item extends it again. `docs/backlog/5-08-console-attachments-and-admin-role.md` — the existing
site-scoped admin console view. Read it closely enough to confirm this item's new route is structurally
separate: `5-08`'s admin view shows one site's own conversations to that site's own Admin-role operator;
this item shows every site's summary data to the one owner identity. The two must never share a route,
a component tree implying shared data-fetching, or naming that could blur "Admin" (site-scoped) with
"owner" (platform-scoped) in a reviewer's mind. `docs/backlog/10-03-console-signup-onboarding.md`'s
"how (b) is actually detected client-side" reasoning — the same caution applies here for detecting an
owner-eligible token, see Scope below.

## Scope

- A new route (e.g. `/owner` — state the final path; deliberately not `/admin` or anything containing
  that word, for the naming-collision reason above) in `ago-console`'s existing router
  (`5-06`'s scaffold), reachable only for a caller the console believes holds the owner identity.
- Client-side detection of "owner-eligible," stated explicitly once implemented, following `10-03`'s own
  precedent: the console must not re-derive `12-01`'s authorization decision itself (e.g. inspecting the
  JWT's `realm_access.roles` directly and trusting that as the source of truth for what is *allowed*).
  The real enforcement is `12-01`'s `RequirePlatformOwner` policy on the server, checked again on every
  call `12-02`'s endpoint receives; the client-side gate exists only so an ineligible caller does not
  briefly see a flash of a screen it cannot actually load data into, and must degrade safely (a normal
  "not found" or "not authorized" state, not a broken table) if the client-side signal and the server's
  real answer ever disagree — the server's `401`/`403` is what actually protects the data either way.
- A data table (reusing whichever `react-admin`/`Refine`-shaped component set `adr/0023`'s Consequences
  pointed toward — state the actual package chosen once implemented, matching `CLAUDE.md`'s "no package
  without saying what it replaces and why hand-rolling is worse") listing every site returned by `12-02`'s
  endpoint: name, tier (literal `"free"` today — render it plainly, do not imply a richer tier system
  exists until `12-02`'s own field carries real data), seats, conversations, recent message volume,
  storage bytes, created, last activity. Keyset-paginated using `12-02`'s cursor, matching that endpoint's
  own pagination contract rather than re-implementing client-side paging over a full result set.
- Reuse whatever form/table styling `5-07`/`5-08` already established for the console's existing screens
  — this item is not a design-system pass, matching how `10-03` treated the same question for its own new
  screen.

## Out of scope

- **Any action** on a listed site — suspend, edit config, grant a "bonus feature" (the phrase `adr/0023`
  used when first describing this surface's eventual territory). `roadmap.md`'s own Stage 12 done-when
  stops at "the owner can see... without querying the database by hand" — visibility, not control. An
  action surface is real, separate future work once actually wanted, not built speculatively here; if
  and when it is, it will need its own authorization thinking (a write path behind `RequirePlatformOwner`
  is a materially bigger decision than this item's read-only table, the same way `5-08`'s note on
  message-level admin access flagged a bigger change as explicitly out of its own scope).
- Any automated highlighting of "suspicious" sites — `12-02`'s own Out of scope already rules out a
  computed abuse score; this item does not invent a client-side one either (e.g. no arbitrary color
  threshold on message-volume numbers). The table shows real numbers; the owner does the judging.
- A design-system pass beyond what `5-07`/`5-08` already established, matching the same deferral
  `10-03` made for its own new screen.

## Done when

- [ ] Manually verified against the local cluster, the same "verified live, not asserted" bar `5-06`/
      `10-03` used: an owner-identity login reaches the new route and sees a table populated with real
      data across more than one seeded site (at minimum the demo site plus one additional site created
      through `10-02`/`10-03`'s flow, so the table is provably not just echoing one hardcoded row).
- [ ] Manually verified: an ordinary operator token (including one holding `5-08`'s `"Admin"` role)
      navigating directly to the new route's URL is rejected cleanly — the console shows a normal
      "not authorized" state, not a broken table or a leaked partial response, and no site data reaches
      the browser for that caller (confirmed via the network response, not just the rendered screen).
- [ ] CI build+lint stays green, matching `5-06`'s own precedent for what this repository automates
      versus verifies by hand for `ago-console`.

## Open questions

None — this item depends on `12-01`/`12-02`'s contracts existing first; no new product-shape decision is
left once those are answered, and `adr/0023` already named this surface's existence and its intended
tooling direction.
