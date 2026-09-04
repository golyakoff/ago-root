# Tenant-isolation scan

Re-derives the headline counts at the top of `docs/architecture/tenant-isolation.md` from a real
scan of `ago-chat`'s source, instead of hand-counting or carrying a delta forward. Filed by `22-19`
after the counts drifted for ten stages without anyone re-running the scan that produced them.

Both scripts read source text only (no build, no `ago-chat` working-tree changes) and are safe to
run against a checkout another session is actively using, via `git archive` into a scratch
directory — never `git worktree add` or `git checkout` inside `ago-chat` itself.

## Running it

From `ago-chat`'s own checkout, export the exact tree you want to scan (usually `origin/main` after
a `git fetch`) without touching its working directory:

```bash
cd <path-to-ago-chat>
git fetch origin
mkdir -p /tmp/ago-chat-scan && git archive origin/main | tar -x -C /tmp/ago-chat-scan
```

Then, from anywhere:

```bash
python scan_entry_points.py /tmp/ago-chat-scan
python scan_routes.py /tmp/ago-chat-scan
```

Run each twice and diff the output before trusting a number that's about to go in the document --
a count that isn't reproducible is the failure this tooling exists to prevent.

## What each script derives

- **`scan_entry_points.py`** -- the first three headline rows (use-case entry points, RBAC-gated,
  deliberately exempt). Approximates `TenantScopeRule.Scan`
  (`ago-chat/tests/Ago.Chat.Architecture.Tests/TenantScopeRule.cs`) at the source-text level rather
  than reading IL: every public method of every `*Handler` class under
  `src/Ago.Chat.Application/UseCases` is one entry point; it carries a `SiteId` if a parameter (or a
  positional-record/property member of a parameter's type, one level deep) is typed `SiteId`; it
  checks permission if its body calls `.HasPermissionAsync(` or `.GetPermissionsAsync(` -- the two
  methods `IPermissionChecker` declares, confirmed unique to that interface in this codebase. Cross-
  references every entry point's key against
  `ago-chat/tests/Ago.Chat.Architecture.Tests/TenantScopeExemptions.cs` and reports anything
  unaccounted (neither gated nor exempt-listed) or mismatched (exempt-listed but this scan also
  thinks it's gated) as a finding to check by hand, not a number to trust blindly.
- **`scan_routes.py`** -- the routes row (HTTP routes + SignalR hub methods carrying tenant data)
  and the client-supplied-`siteId` row. Resolves every `<group>.Map(Get|Post|Put|Delete|Patch)(...)`
  call in `src/Ago.Chat.Api` against the route-group prefix it's nested under, then flags a route as
  client-supplied when its resolved path contains a literal `{siteId...}` segment. Hub methods come
  from every public method on `OperatorHub`/`VisitorHub` other than the SignalR lifecycle callbacks.

## What neither script derives

- The **cross-tenant reads/writes rows** (the platform-owner surfaces) are intentionally hand-
  maintained in the document, not scanned -- they're short and reasoned about individually, which is
  why they don't drift the way the long mechanical rows do.
- The **read-model queries row** isn't scripted (the population is small enough -- one method per
  Postgres read-store class under `src/Ago.Chat.Infrastructure.Postgres` using `NpgsqlDataSource`,
  i.e. `adr/0004`'s Dapper read side, not an `AgoChatDbContext`-backed store) but should be if it
  ever grows past a hand count someone can double-check by eye in a minute.
- Neither script assigns a *reason* to a newly-found exempt handler, or writes an "additional
  ownership check" description for a newly-found gated one -- that's a judgment call a person makes
  reading the handler, the same way `14-04`'s and `18-04`'s deltas did it. The scripts only say
  *how many* and *which ones*.
