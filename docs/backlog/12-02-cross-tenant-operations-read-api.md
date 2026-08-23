# Cross-tenant operations read API

- **Stage**: 12
- **Status**: ready
- **Depends on**: `12-01-platform-owner-identity-and-access.md` — needs its `RequirePlatformOwner`
  policy to gate the endpoint this item adds; blocked transitively by nothing else, since `12-01` itself
  has no open question.

## Goal

A single read-only endpoint lets the platform owner see, across every site in one call, its tier, and
real usage signals — seat count, conversation volume, recent message volume, attachment storage bytes,
when it was created, when it was last active — without connecting to Postgres by hand. This is the one
deliberate place in this codebase that reads across every tenant at once rather than being scoped to one
`site_id`; every other query in `ago-chat` is tenant-scoped by construction, so this item states plainly,
in its own code, why this one is not and why that is safe (it is gated by `12-01`'s owner-only policy,
nothing else reaches it).

## Context to read first

`docs/architecture/data-model.md` in full — specifically the `sites`, `operators`, `conversations`,
`messages` (and its monthly partitioning, `2-06`), and `attachments` shapes; this item reads all of
them but writes none. `docs/adr/0004-postgres-ef-writes-dapper-reads.md` — this is a read, so it follows
that ADR's Dapper-and-hand-written-SQL path, the same as every other read model in this codebase, not a
new mechanism. `docs/conventions/api-design.md`'s keyset-pagination rule (`?before=&limit=`, no
`OFFSET` — `data-model.md` bans it outright) and RFC 7807 error shape. `docs/architecture/caching.md` —
read closely enough to state, in this item's own text once implemented, why this view is *not* an
exception to `CLAUDE.md` rule 8 ("never cache what a write decision depends on"): this endpoint informs
no write, compare-and-set, or capacity check anywhere in the system — it is pure observability for a
human, the same category `7-02`'s metrics already occupy, not a caching concern this item needs to
solve now. `docs/backlog/10-02-site-and-operator-registration.md`'s Out of scope — "no tier/plan column
anywhere. There is exactly one tier today (free)" — the reason this item's `tier` field is a literal
constant, not a fabricated computation. `roadmap.md`'s Stage 13 section — read only to confirm this item
must not assume any billing/subscription record exists yet; it reads today's actual state.

## Scope

- A new Dapper-backed read query (`Ago.Chat.Application/Abstractions` port +
  `Ago.Chat.Infrastructure.Postgres` implementation — state the final names once written, e.g.
  `IPlatformOverviewReadStore`/`ListSitesForOwnerHandler`, matching this codebase's existing
  `UseCases/<Name>/<Name>.cs` + `<Name>Handler.cs` shape) returning, per site:
  - `id`, display name, `created_at`.
  - **Seat count**: distinct operators for the site (`operators` rows, or distinct `operator_roles`
    holders — state which once implemented and why).
  - **Conversation count**: total conversations for the site.
  - **Recent message volume**: message count within an explicitly bounded recent window (state the
    window once implemented, e.g. the last 30 days) rather than an all-time count — `messages` is
    partitioned by `created_at` (`2-06`), so a bounded-window query touches a handful of recent
    partitions; an all-time count is a full-table scan across every partition that has ever existed,
    and only gets worse as the table grows. State this reasoning in the query's own remarks, matching
    how other performance-relevant decisions in this codebase are documented at the point they're made.
  - **Attachment storage bytes**: `SUM(size_bytes)` for the site's non-deleted attachments — the one
    usage signal that maps directly to the business's own free/paid split criterion (infrastructure
    cost that scales with usage), referenced here only functionally, not by restating any private
    pricing detail.
  - **Last activity**: most recent message `created_at` for the site (`NULL` for a site with no
    messages yet — state how the response represents that).
  - **Tier**: the literal string `"free"` for every row. State explicitly, in this item's own text, that
    this is not a fabricated or simplified computation — it is the actual and only tier that exists in
    the system today (`10-02`'s own decision: no tier/plan column anywhere until Stage 13). The field is
    included in the response shape now so Stage 13 has a real column to populate later without breaking
    the response contract (`api-design.md`'s "additive changes only" rule, applied here in the direction
    that matters: today's placeholder must not need a breaking shape change later).
- `GET /api/v1/owner/sites` — a distinct path prefix from anything `5-08`'s per-site admin surface uses,
  chosen deliberately to avoid the word "admin" reading as "site-scoped Admin role" (`authorization.md`'s
  table already distinguishes the two actors; the URL should not blur that distinction back together).
  Gated exclusively by `12-01`'s `RequirePlatformOwner` policy. Keyset-paginated (`?before=&limit=`),
  sorted by `created_at`/`id`, matching `api-design.md` and `data-model.md`'s existing pagination rule
  exactly — never `OFFSET`.
- If trivial to add alongside the same query, a simple sort parameter over one usage dimension (e.g.
  seat count or recent message volume) — state explicitly what is and is not included, since this is a
  nice-to-have, not a requirement `roadmap.md`'s done-when names.

## Out of scope

- **Enforcing** the per-account site-count cap or the free-tier history-retention cap `roadmap.md`'s
  Stage 13 section names ("attachments/history/site-count caps as those business decisions land"). This
  item is visibility only, matching Stage 12's own roadmap done-when: "the owner can see every account...
  without querying the database by hand" — not "can prevent." Named again here, explicitly, so it is not
  lost: today, nothing stops one real person from creating multiple free sites, because `10-02` enforces
  "one site per Keycloak identity," not "one site per person" — a person can simply register a second
  Keycloak identity. This item's view surfaces each site's own seat/creation/activity data, which lets a
  human *notice* a pattern by eye, but computes and flags nothing automatically. Enforcement of either
  cap remains entirely unbuilt, and is deferred to whichever future item actually builds it — most likely
  alongside Stage 13's entitlement work, consistent with the roadmap's own stage split and with the
  business's already-stated priority on building real entitlement enforcement ahead of strict need.
- **Any automated abuse-flagging or scoring** ("this site looks suspicious because..."). `CLAUDE.md`'s
  "do not invent numbers, benchmarks, or 'typical production' figures — measure or stay silent" rules out
  a fabricated threshold or heuristic; this item surfaces real, raw signals for a human to judge, not a
  computed verdict.
- **Correlating multiple sites back to the same real person** — e.g. by the registering operator's
  email. Would need either capturing operator email at registration time (`10-02`'s `RegisterSiteHandler`
  does not do this today, and adding it is a real, separate change to an already-scoped item) or a live
  call to Keycloak's Admin REST API from `Ago.Chat.Api` (a new class of secret — Keycloak admin
  credentials — this project has not needed to hold before, and `10-01`'s own ADR reasoning already
  named exactly this cost as a reason to avoid such calls where a simpler alternative exists). Genuinely
  useful future work for whoever revisits the site-count-cap loophole above; explicitly named here as a
  real gap, not solved in this item.
- **A dollar or infrastructure-cost figure** for any tenant. Not knowable from data this system actually
  has today; `CLAUDE.md` forbids inventing it. Storage *bytes* is real and shown; a cost *estimate* is
  not.
- **Any write or action endpoint** (suspend a site, revoke a role, edit another tenant's config). This
  item is read-only; `12-03`'s console view is read-only to match. An action surface is real, separate
  future work, not built speculatively here.

## Done when

- [ ] `Ago.Chat.Integration.Tests`: seed several sites with deliberately varied seat counts, conversation
      counts, message volumes spanning both a recent and an older `messages` partition, and attachment
      byte sizes; call the endpoint against a real Postgres and assert the returned numbers match ground
      truth exactly for every site — not merely that a response with the right shape came back.
- [ ] A normal operator token (with or without `5-08`'s `"Admin"` role) receives `401`/`403`, proven with
      a real token, not asserted from `12-01`'s policy definition alone.
- [ ] Pagination proven with more sites seeded than fit on one page: a second call using the returned
      cursor returns the remaining sites with no gap and no duplicate.
- [ ] The recent-message-volume window is stated explicitly in this file (updated in place) once
      implemented, along with the partition-touching reasoning above.
- [ ] `docs/architecture/data-model.md` gets a short note that this is the first genuinely cross-tenant
      read query in the codebase, if implementation surfaces anything about the query's shape not already
      obvious from the existing table definitions (state explicitly, once written, whether it does).

## Open questions

None — the query's shape follows directly from `data-model.md`'s existing tables and `10-02`'s own
already-stated "no tier column yet" decision; the deferred items above (enforcement, abuse-scoring,
identity correlation) are named, not blocking, because none of them is required by `roadmap.md`'s own
Stage 12 done-when.
