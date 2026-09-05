# ADR-0109: A person's export is scoped by visitor, and runs synchronously, not through 16-03's job

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 24

## Context

`16-03` built exactly one export granularity: the whole site, as a `Pending`/`Ready`/`Failed` row in
`export_requests` that `Ago.Chat.Worker`'s `SiteExportJob` resolves off a timer. `16-02`'s erasure had
the identical choice in front of it and landed on two granularities - a whole account and one
conversation - because deletion makes the asymmetry obvious: nobody would ship "delete my data" as a
site-wide-only button. Export's asymmetry was quieter, and `24-11` exists to close it: a tenant
honouring one visitor's access request today can only run the whole-site export and extract by hand,
which means putting every other visitor's transcript into an artifact created to answer one person's
request.

Three constraints shaped what "close it" could mean here:

1. **What "one person" is** is not obvious. A visitor is a `visitors` row holding almost nothing
   (`id`, `site_id`, two timestamps - `personal-data.md`'s own description), while their data spans
   conversations, messages, attachments, contact details and channel identities. The same human can be
   two `visitors` rows (two devices, two channels) with nothing in this schema linking them -
   `channel_identities` binds an address to a visitor, not a person. An export that claimed to answer
   "everything about this person" while the system cannot know two rows are the same person would be a
   worse lie than a narrower, honest one.
2. **A schema-migration freeze was in effect for this change**: `23-06`'s own migration held the one
   slot a session may add per wave. `export_requests` has no column naming which conversation or
   visitor a request is scoped to, and adding one was off the table for this item regardless of
   whether it would otherwise have been the right shape.
3. **`SiteExportArchiveWriter`, the whole-site writer, lives in `Ago.Chat.Worker`** - a host project -
   not behind an Application-layer port, because nothing outside that host ever calls it. A caller in
   `Ago.Chat.Api` cannot reach it without either moving it (touching shipped, tested code this item
   found no defect in) or reintroducing the same raw-Npgsql-in-a-host shape one layer further out than
   it has ever lived.

## Decision

### Two granularities, matching erasure's own split

Export gains `POST /api/v1/conversations/{conversationId}/exports` (one conversation) and
`POST /api/v1/conversations/{conversationId}/visitor-export` (every conversation the same visitor has),
mirroring `16-02`'s `conversation:erase`/`site:erase` split. A new permission,
`conversation:export`, gates both - distinct from `site:export` for the identical reason
`conversation:erase` is distinct from `site:erase` (`Permission.cs`'s own remarks): a tenant honouring
one visitor's request does not need, and must not be granted, the power to export every other
visitor's data to do it.

**"One person" is scoped to one `visitors` row, stated as exactly that and no more.** The visitor-scope
export spans every conversation `IConversationReadStore.ListAllForVisitorAsync` finds for that
`VisitorId`, plus that visitor's `channel_identities` and `visitor_contact_details`. It does **not**
attempt to merge two `visitors` rows the operator believes are the same human - nothing in this schema
makes that claim safely, and an export that guessed would be exactly the "confident and wrong" register
`personal-data.md` warns against. **Not gated on holding a `ChannelIdentity`**, unlike
`GetVisitorHistoryHandler`'s own operator panel: that gate answers a different question (which operator
may read historical messages they were never assigned to); a widget-only visitor can still hold more
than one conversation under the same row, and every one of them is this same person's data, so the
export includes all of them regardless of channel identity.

### Synchronous, not through `export_requests`

Both endpoints build the archive and return it as the HTTP response body in the same request - no
`Pending` row, no completion poll. Two independent reasons, either sufficient alone:

- **Volume is bounded by construction.** `16-03` needed an asynchronous job because a whole tenant's
  history could be arbitrarily large ("a tenant with a year of conversations must not require the API
  to hold it all in memory," `16-03`'s own Scope). A conversation, or one visitor's own conversations,
  is bounded by "one person's own history," a materially smaller and different kind of quantity - the
  same reasoning that already lets `IVisitorContactDetailRepository.GetForVisitorAsync` and this item's
  own new `ListAllForVisitorAsync` read a visitor's rows unpaginated.
- **The freeze left no column to carry the scope.** Even absent the freeze, adding
  `conversation_id`/`visitor_id` to `export_requests` to carry a request this small through a queue
  built for whole-tenant archives would be solving a problem this scope does not have.

The archive still streams row-by-row through a forward-only `NpgsqlDataReader` into a `ZipArchive`
entry onto a local temp file (`PersonExportArchiveWriter`, the same shape `SiteExportArchiveWriter`
already establishes) - "synchronous" describes the request/response shape, not a return to buffering a
tenant's history in memory.

### A second, smaller writer - not `SiteExportArchiveWriter` widened

`IPersonExportArchiveWriter` is a new Application-layer port, implemented by
`PersonExportArchiveWriter` in `Ago.Chat.Infrastructure.Postgres`. It agrees with `SiteExportArchiveWriter`
on the wire format - one `.zip`, `manifest.json` plus one JSON Lines file per store, `formatVersion: 1`
(the *shape* is unchanged; only which rows a given archive holds differs, which is exactly what
`manifest.json`'s own `scope`/`visitorId`/`conversationIds` fields say) - but is a separate class in a
separate project, because `SiteExportArchiveWriter` lives in `Ago.Chat.Worker` and a request handler in
`Ago.Chat.Api` cannot legally reach into a host project (rule 1: hosts reference everything, nothing
references a host). Moving the whole-site writer into `Infrastructure.Postgres` to let both share code
was considered and rejected: it is working, tested code with no defect this item found, and the risk of
refactoring it was not worth paying to avoid a second, smaller writer class.

### What is included, and what is deliberately excluded - stated in the archive itself

The person-scoped archive holds `visitor`, `channelIdentities`, `contactDetails`, `conversations`,
`messages`, `attachments` (referenced by presigned URL, unchanged from `adr/0072`'s 7-day SigV4
ceiling). It deliberately excludes, and says so in `manifest.json`'s own `excludedStores` field - not
only in this ADR or the code - so a tenant reading the file they received can see the boundary:

- **`operators`** - the whole-site export's roster of every operator on the tenant is a *different*
  person's data; including it in an artifact meant to answer one visitor's request would be the exact
  disclosure problem `24-11` exists to close, applied to the other class of subject a site holds.
- **`notes`** (`18-04`'s `conversation_notes`) - an operator's private annotation *about* the visitor,
  already made structurally unreachable from every visitor-facing read path. A subject-access export is
  exactly such a path, so the same rule applies rather than being relaxed for it.
- **`tags`/`conversation_tags`** - tenant workflow labels, not personal data about the visitor
  (`personal-data.md`'s own words), and not named in `24-11`'s own Scope enumeration.
- **`site`** - tenant configuration, not personal data about the visitor; the whole-site export's own
  `site.json` exists for tenant *portability* (`16-03`'s framing), a question this narrower export does
  not answer.

## Consequences

- A visitor-scoped export cannot promise it found every row belonging to "this person" in the human
  sense - only every row reachable from one `visitors` row. Stated as a limit, not silently assumed
  away.
- Found, not fixed, while building this: **`SiteExportArchiveWriter` (the whole-site export) never
  writes `visitor_contact_details` at all.** `14-14` shipped after `16-03` merged, so the whole-site
  writer predates the store; personal-data.md's table lists it as belonging to `16-03`'s own Done-when
  ("every store... belonging to that tenant") without it actually being reached. Not fixed here - it is
  `SiteExportArchiveWriter`'s own code, a different item's promise, and this item's own worker was
  instructed not to touch it. Left for the managing session to decide whether it becomes its own
  ticket.
- If a tenant's own visitor ever accumulates enough conversation/message volume that the synchronous
  shape stops being reasonable, promoting this to `16-03`'s async job shape would need
  `export_requests` to carry `conversation_id`/`visitor_id` - an EF migration this item deliberately
  did not make. Nothing here blocks that later; it is a real future cost, named rather than hidden.
- No console entry point ships with this item - `24-11`'s own Done-when names two archive-shaped
  criteria and a documentation criterion, not a UI trigger. `EraseConversationButton` (`16-02`) is the
  natural console-side sibling a follow-up item could add cheaply once wanted.
- `ago-deploy/seed/create-demo-tenant.sh`'s Admin permission array does not grant `conversation:export`
  - the same pre-existing staleness already noted for `site:erase`/`conversation:erase`/`site:export`
  (`adr/0072`'s own Consequences), in a different repository this item does not touch.

## Alternatives considered

- **Widen `export_requests` with a nullable `conversation_id`/`visitor_id` and reuse `16-03`'s job.**
  Rejected: blocked outright by this session's migration freeze, and independently wrong-sized even
  without the freeze - a job queue built to keep a whole tenant's history out of API memory buys
  nothing for a request this small, at the cost of a completion poll nobody needs.
- **Move `SiteExportArchiveWriter` into `Infrastructure.Postgres` so both writers share one class.**
  Rejected: a refactor of working, tested code for marginal reuse, when the two writers already agree
  on everything a reader of the archive can observe (the wire format).
- **Gate the visitor-scoped export on the visitor holding a `ChannelIdentity`**, mirroring
  `GetVisitorHistoryHandler`'s own panel. Rejected: that gate answers "which operator may read
  historical messages they were never assigned to," not "does this export need to be complete." A
  widget-only visitor can hold more than one conversation under the same row without ever acquiring a
  channel identity, and every one of them is this person's own data.
- **Attempt to merge two `visitors` rows an operator believes are the same human.** Rejected: nothing
  in this schema makes that claim safely (`channel_identities` binds an address to a visitor, not a
  person), and a confident merge would be exactly the kind of overstated export `24-11`'s own brief
  warns against producing.
