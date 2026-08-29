# Search across conversations

- **Stage**: 18
- **Status**: done (2026-08-29, `ago-chat#114` + `ago-console#56`) — see Outcome below
- **Depends on**: nothing new architecturally — but read the partitioning note below before assuming
  this is an ordinary index

## Goal

An operator can find a conversation by what was said in it. Today the only way to reach an old
conversation is to recognise it in a list ordered by time, which stops working at the point a site has
more than a screenful of history — that is, immediately for any real customer.

## Why this is the hard one in Stage 18

The rest of this stage is CRUD with a screen attached. This item is not, because of a decision already
made: `messages` is `PARTITION BY RANGE (created_at)`, monthly (`2-06`), and `adr/0031` adds a second
level by retention class. A full-text index over a two-level partitioned table is not the same object
as an index over a table — Postgres builds one index per leaf partition, a search touches all of them
unless the query prunes, and pruning needs a time bound the operator has not given.

So the real question this item answers is not "which index type" but **what a search is allowed to
cost**, and the honest answers are bounded: search within a date range, or search the recent window
and offer the archive separately (`13-06`). Deciding that is the item; the index is the easy half.

## Context to read first

`docs/architecture/data-model.md`'s partitioning section, and `adr/0019` on what the partition key did
to every unique constraint — the same widening logic applies to any index added here. `adr/0031` for
the second partition level, **and its Addendum (2026-08-29)** — already settles the question this item
would otherwise reopen: `site_id` does not become a third partition dimension (it would multiply
partition count by tenant count and would not deliver real cross-machine scale-out on a single
Postgres instance regardless of key), so the tenant-scoped search predicate this item needs is served
by a plain denormalized column and index instead, not a repartitioning. `docs/architecture/data-model.md`'s
access strategy — reads go through Dapper read stores with keyset pagination, and search results are a
read model like any other. `docs/backlog/13-06-retention-class-partitioning-and-archive.md` — history
past the window lives in an archive file, not in the table, so "search everything" is not a thing the
database can answer alone. `docs/backlog/17-01-tenant-isolation-proof.md` — a search endpoint that
forgets `site_id` is the worst possible instance of the defect that item exists to prevent.

## Scope

- Decide and state what a search covers: a bounded window, an operator-supplied date range, or both.
  Whatever is chosen, the bound is visible in the interface rather than a silent truncation.
- **Denormalize `site_id` onto `messages`** (plain column, populated at write time from the owning
  `Conversation`, never a cache of anything a write decision depends on — `CLAUDE.md` rule 8 does not
  apply, since nothing reads it to decide whether a write may proceed) plus a composite index carrying
  it alongside the full-text index — decided in `adr/0031`'s Addendum, not this item's own call to
  relitigate. Without it, the tenant-scoped predicate below can only be expressed as a join through
  `conversations`, defeating the pruning this item exists to get.
- A Postgres full-text index sized to the window decision above, with the partition consequences
  stated — not assumed.
- A read-store query with keyset pagination, `site_id` in the predicate (against the new column
  directly, not a join), and a test proving an operator cannot reach another site's messages through it.
- Console surface: a search field, results showing enough context to recognise the conversation, and
  clicking through to it at the right position in the thread.
- A stated answer to what happens for archived history: out of reach, or reachable through `13-06`'s
  retrieval. Silence here is the thing that makes a search feel broken.

## Out of scope

- Search over attachment contents. A different problem entirely, needing extraction per file type.
- A separate search engine. Postgres full-text is sufficient at this scale and adding a second data
  store to keep in sync is the kind of decision that needs its own ADR and a real reason.
- Search across tenants — `12-02` owns anything that crosses that line, deliberately and separately.

## Done when

- [x] An operator can find a conversation by a phrase in it, within the stated bound.
- [x] The bound is visible, not silent.
- [x] `messages` carries a denormalized `site_id` column, populated at write time, with a migration
      backfilling existing rows via the owning `Conversation`.
- [x] Cross-site isolation is proven by a test, not by the query looking right.
- [x] The partition consequences of the index are written down in `data-model.md`; the "`messages`
      carries no `site_id`" fact is updated to reflect the new column.

## Open questions

None. The scope decision above is this item's own to make and record.

## Outcome

Shipped as `SearchConversationsHandler` (`ago-chat#114`) plus a console search page
(`ago-console#56`). The bound chosen: an operator-supplied phrase **and** an optional `from`/`to` date
range, both visible as real query parameters — no silent window. `messages.site_id` was denormalized
(`adr/0031`'s Addendum, decided alongside `13-02`) with a composite index carrying it next to the
full-text index; cross-site isolation was proven by `ConversationSearchStoreTests` and independently
re-verified by mutating the `WHERE m.site_id = @SiteId` predicate to a tautology, confirming a leak of
two rows across sites instead of one, then restoring and re-running green.

Archived history was answered honestly rather than assumed: no REST history endpoint existed for a hit
to link into at the time this item shipped, and the SignalR hub's `JoinConversationAsync` has the real
side effect of claiming a `Waiting` conversation — so an `Assigned` search hit gets a real
`?at=<sequence>` deep link with backward-paging-to-target and highlight, while a `Waiting`/`Closed` hit
gets no link, only an explanatory note that opening it is not yet wired. Recorded here rather than left
implicit, since it is the kind of gap a later item could otherwise silently reopen believing search
already covers it.
