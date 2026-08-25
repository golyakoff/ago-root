# Search across conversations

- **Stage**: 18
- **Status**: ready
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
the second partition level. `docs/architecture/data-model.md`'s access strategy — reads go through
Dapper read stores with keyset pagination, and search results are a read model like any other.
`docs/backlog/13-06-retention-class-partitioning-and-archive.md` — history past the window lives in an
archive file, not in the table, so "search everything" is not a thing the database can answer alone.
`docs/backlog/17-01-tenant-isolation-proof.md` — a search endpoint that forgets `site_id` is the worst
possible instance of the defect that item exists to prevent.

## Scope

- Decide and state what a search covers: a bounded window, an operator-supplied date range, or both.
  Whatever is chosen, the bound is visible in the interface rather than a silent truncation.
- A Postgres full-text index sized to that decision, with the partition consequences stated — not
  assumed.
- A read-store query with keyset pagination, `site_id` in the predicate, and a test proving an operator
  cannot reach another site's messages through it.
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

- [ ] An operator can find a conversation by a phrase in it, within the stated bound.
- [ ] The bound is visible, not silent.
- [ ] Cross-site isolation is proven by a test, not by the query looking right.
- [ ] The partition consequences of the index are written down in `data-model.md`.

## Open questions

None. The scope decision above is this item's own to make and record.
