# Basic operator/site analytics

- **Stage**: 18 — placed here for lack of a better-fitting stage; this is site-owner-facing operational
  visibility, not strictly "operator does the obvious thing faster" the way `18-01`-`18-07` are, but it
  lives in the console the same way they do and needs no new architectural surface. Revisit placement if
  a future session finds a stage that fits it better; not worth inventing a new stage for one item.
- **Status**: ready
- **Depends on**: nothing new architecturally — reads existing data through a new Dapper read store, the
  same access-strategy shape every other console read already uses

## Goal

A site owner or operator can see, without leaving the console: how many conversations came in, average
first-response time, and how many messages went unanswered, per channel, over a real time window — the
most basic "how am I doing" visibility a support tool owes its own user, which this product does not
have at all today.

## Why this, and why now

`ago-business/docs/decisions/0009-razryv-po-fucham-s-jivo-chto-stroim-chto-net.md` names this as "Level
2" of the gap against the nearest direct competitor (Jivo) — cheap to build (no new write path, purely
derived from data already recorded) and, unlike CRM depth or telephony (also named in that document,
and explicitly rejected), genuinely wanted by the target customer independent of what any competitor
offers: a small shop owner wants to know how their own support is doing, not to match a feature list.

**This is explicitly not `12-02`.** `12-02`'s cross-tenant read API is for the platform owner (AGO's
own team) to see usage signals across every tenant at once, gated by `RequirePlatformOwner`. This item
is the mirror image: one tenant's own owner/operator, seeing only their own site's numbers, through the
ordinary `conversation:read`/`site:configure`-shaped permission a ordinary console user already holds.
No cross-tenant read is introduced by this item.

## Context to read first

`docs/architecture/data-model.md`'s "Access strategy" section — reads go through Dapper read stores,
this is another one, not a new pattern. `messages`/`conversations`' own columns (`created_at`,
`delivered_at?`, `read_at?`, `author_kind`) already carry everything a first-response-time and
missed-message calculation needs; verify this before assuming any new column is required — the working
assumption going in is that none is.

## Scope

- A new read store (or an extension of an existing one) answering, scoped by `site_id` and a caller-
  supplied date range: conversation count, average time from the first visitor message to the first
  operator reply, count of conversations that never received an operator reply within the window, and
  a per-channel breakdown of the above (`ChannelKind` already exists as the dimension to group by).
- A console page or panel surfacing this — a plain table/summary, not a charting library; this item is
  about the numbers existing and being readable, not about visualization polish.
- Gated the same way `GetAllConversationsForSiteHandler` already is (`site:configure` or
  `conversation:read` — decide which is the better fit and record why, the same discipline every other
  new handler in this codebase already holds itself to).

## Out of scope

- Per-operator KPI (response speed, activity, broken down by individual operator rather than the whole
  site) — a real, named follow-up (`0009` calls it out explicitly as "the same derivation with an
  operator filter"), not built here. This item proves the read shape works before adding the second
  dimension.
- Any chart/graph rendering library — numbers in a table are the whole of this item's Done-when.
- Historical data beyond what `13-06`'s retention window already keeps live — this item reads the same
  live window every other console feature does, no special exemption from retention.

## Done when

- [ ] A real conversation volume, average first-response time, and missed-conversation count are
      computed correctly for a real site with real seeded data, proven by a test against real values,
      not by the query looking right.
- [ ] The same three numbers are broken down per channel.
- [ ] A console panel/page renders them, gated by the permission this item's own scope decides on.
- [ ] Cross-site isolation is proven by a test — a caller cannot see another site's numbers through
      this endpoint, the same bar `17-01`'s own tenant-isolation discipline holds every new read to.

## Open questions

Which existing permission (`conversation:read` vs `site:configure`) gates this is this item's own call,
argued from precedent, not decided here.
