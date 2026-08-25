# Console: owner operations view

- **Stage**: 12
- **Status**: done — merged 2026-08-25 (`ago-console#11`, `ago-root#111`), and the interactive
  owner-login pass the Outcome left open was completed the same day (see the end of that section).
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
- A data table (~~reusing whichever `react-admin`/`Refine`-shaped component set `adr/0023`'s Consequences
  pointed toward — state the actual package chosen once implemented~~ — **overtaken by `adr/0030`**,
  which closed the console's component set at eleven hand-rolled components including `Table`; the
  package chosen is *none*, and adding one now would need an argument against both `CLAUDE.md`'s
  dependency rule and that ADR) listing every site returned by `12-02`'s
  endpoint: name, tier (literal `"free"` today — render it plainly, do not imply a richer tier system
  exists until `12-02`'s own field carries real data), seats, conversations, recent message volume,
  storage bytes, created, last activity. Keyset-paginated using `12-02`'s cursor, matching that endpoint's
  own pagination contract rather than re-implementing client-side paging over a full result set.
- Reuse whatever form/table styling `5-07`/`5-08` already established for the console's existing screens
  — this item is not a design-system pass, matching how `10-03` treated the same question for its own new
  screen. **Corrected 2026-08-24**: build this screen out of `11-05-console-design-foundation.md`'s
  components and shell, which land a stage earlier precisely so screens like this one are not built bare
  and restyled afterwards.

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
      **Half-done**: the data half is verified — three real sites (demo plus two registered through
      `10-02`) came back in one live response and rendered as the real table; the *login* half is not,
      because the implementing session cannot type a password into Keycloak's form. See Outcome.
- [x] Manually verified: an ordinary operator token (including one holding `5-08`'s `"Admin"` role)
      navigating directly to the new route's URL is rejected cleanly — the console shows a normal
      "not authorized" state, not a broken table or a leaked partial response, and no site data reaches
      the browser for that caller (confirmed via the network response, not just the rendered screen).
      Confirmed on the wire: `403` with `Content-Length: 0` for both an `"Operator"` and an `"Admin"`
      token, `401` with an empty body unauthenticated, and the refusal branch rendering with no table
      and no site id in the DOM.
- [x] CI build+lint stays green, matching `5-06`'s own precedent for what this repository automates
      versus verifies by hand for `ago-console`. `npm run typecheck`, `lint`, `test` (82 tests, 9
      files — 8 new) and `build` all run green locally.

## Outcome

**Route**: `/owner`, rendering `OwnerSitesPage`, navigation label **"Platform sites"**. No segment,
label or heading contains "admin" — `5-08`'s `/admin` is a tenant's own supervisor, this is the
operator of the service, and `12-02` drew the same line server-side (`/api/v1/owner/`). The two share
no route, no endpoint and no component tree.

**Mounted outside the operator layout**, unlike `/admin` and `/settings/widget`: the platform owner is
a Keycloak realm role, not an operator seat, so the route may not assume an `operators` row exists —
which `OperatorConnectionProvider` does, opening a per-operator hub connection this screen has no use
for. `PermissionsProvider` is kept and fails soft, which is what lets the header offer a way back into
the console only when the caller demonstrably holds a seat as well. Same reasoning `/onboarding`
already applies to the same providers.

**The client-side eligibility signal, stated as the item asks**: one `GET /api/v1/owner/sites?limit=1`
per signed-in session (`probeOwnerEligibility` / `useOwnerEligibility`), whose HTTP status *is*
`12-01`'s `RequirePlatformOwner` decision arriving in the browser. The console never inspects
`realm_access.roles` — following `10-03`'s own precedent, where a `403` from `RequireOperatorIdentity`
is reused instead of re-deriving the server's resolution. It gates exactly one thing, the navigation
link, and fails closed on anything that is not an explicit yes. The screen itself does **not** trust
it: it re-asks the real endpoint and renders whatever the server answers, so a wrong "eligible" costs
an ordinary "not authorized" state rather than a leak, and a refused response carries no body to leak.

**The two nullables and the window, rendered as what they are**: `createdAt: null` renders "Not
recorded" (never a date, never today); `lastMessageAt: null` renders "None in the last 30 days" —
built from the response's own `recentWindowDays`, never the word "never", because the API's value is
windowed and a long-dormant tenant is indistinguishable from a brand-new one. Every label naming a
number of days is computed from `recentWindowDays` (the message-volume column header included), and
unit tests cover that so a hardcoded "30" cannot creep back in.

**No new package**, and no twelfth component: the screen is `Table`, `Panel`, `Badge`, `Alert`,
`Button` and `Spinner`/`Skeleton` from `11-05`'s closed eleven, inside `AppShell`, and it added no CSS
at all (the production stylesheet is byte-for-byte the size it was). Two small additions are pure
functions with tests, not components: `time/format.ts`'s `formatDateStamp` and `owner/ownerSites.ts`'s
byte/count/window formatters.

**Deliberately absent**: any action on a row (no suspend, no edit, no "grant a bonus feature") and any
computed verdict — no colour threshold, no ranking, no sort. The table's caption says the order is the
API's own cursor order (site id descending) rather than implying a chronological or usage ranking.

**Verified live** against the local stack (compose infra, `Ago.Chat.Api` built from `12-02`'s branch on
`:5009`, migrations applied): three sites — the seeded demo tenant plus **two** created through
`10-02`'s real registration flow — returned in one response, with `createdAt: null` on the demo row
and real timestamps on the new ones, `lastMessageAt: null` on the two quiet ones, `recentWindowDays:
30`, and `attachmentBytes: 5009`. Keyset paging walked all three rows at `limit=1` and then returned
the empty final page `12-02`'s cursor rule allows, which the UI's "load more" handles. The negative
case was confirmed **on the wire**, not on screen: an ordinary operator token and an `"Admin"`-role
token each got `403` with `Content-Length: 0`, an unauthenticated cross-origin call from the console's
own origin got `401` with a zero-length body, and revoking the realm role mid-session turned the same
identity that had just seen three sites straight back into a `403`. The rendering was checked against
that exact live JSON in a throwaway fixture harness (deleted afterwards): the real columns, the real
"Not recorded" / "None in the last 30 days" cells, the exact byte count in the cell title, the
zone-labelled instant in the timestamp title, `role="alert"` and **no table and no site id anywhere in
the DOM** on the refusal branch.

**The interactive pass — completed 2026-08-25 by the managing session**, which can use these public
throwaway credentials. The implementing session could not (it cannot type a password into a login
form) and said so rather than claiming it. Signed in through Keycloak's hosted login as `demo-admin`
holding a real `platform-owner` grant:

- The shell's navigation showed **"Platform sites"** alongside the operator entries — the
  eligibility probe returning the server's own yes, not a claim the console read for itself.
- `/owner` rendered **three sites**, not one hardcoded row: `Harbour Books` and `Northwind Coffee`
  (both created through `10-02`'s real registration flow) and the seeded demo tenant.
- Every rendering decision this item argued for was visible in the real table: the message column
  headed **"Messages (the last 30 days)"** (built from the response's `recentWindowDays`, not a
  literal), the demo tenant's missing creation time as **"Not recorded"** rather than a fabricated
  date, and its two brand-new siblings showing **"None in the last 30 days"** rather than "Never" —
  the distinction the windowed field actually supports. Tier `free`, attachments `4.8 KiB`,
  343 conversations and 662 recent messages on the demo row.

The local Keycloak needed the `platform-owner` realm role created by hand through the admin API: the
running container's realm was imported before `12-01` added the role to `keycloak-realm-import.json`,
and Keycloak imports a realm only on first start. The role was left in place (it matches `main`'s
import); the *grant* was revoked after the check — confirmed `[]`.

## Open questions

None — this item depends on `12-01`/`12-02`'s contracts existing first; no new product-shape decision is
left once those are answered, and `adr/0023` already named this surface's existence and its intended
tooling direction.
