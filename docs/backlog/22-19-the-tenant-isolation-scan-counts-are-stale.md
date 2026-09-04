# the tenant-isolation scan counts have not been re-derived since `14-04`

- **Stage**: 22
- **Status**: done (2026-09-04)
- **Found**: 2026-09-04, while correcting `tenant-isolation.md` for `22-17`.

## The finding

`docs/architecture/tenant-isolation.md` opens with a table of counts — use-case entry points,
RBAC-gated handlers, deliberately exempt handlers, routes carrying tenant data, routes taking a
client-supplied `siteId`. Those are the numbers a reviewer reads first, and the ones that make the
document a *classification* rather than an essay: every handler is either gated or argued, and the
count is what proves nothing was skipped.

**They were last derived in `14-04`.** On `main` as of 2026-09-04 there are **103** `*Handler.cs`
files under `Ago.Chat.Application/UseCases` against the **69** handler classes the table records. Ten
stages have added entry points since without re-running the scan.

The table now carries a dated note saying so and pointing here, so nothing reads as current that is
not. That note is a warning, not a fix.

## Why this is worth a number rather than a docs chore

The classification's whole value is exhaustiveness. A handler that was never scanned is not
"documented as exempt with a stated reason" — it is *unexamined*, and unexamined is exactly the state
`17-01`'s cross-tenant hole was found in. The table's drift means nobody can currently say whether
every use case is gated or argued, only that every use case `14-04` knew about was.

`TenantScopeTests` (`Every use case is gated or argued`) is the mechanical half and does still run —
so this is not a claim that something is ungated. It is that the **document** can no longer be checked
against the code by reading it, and the numbers are the part a reviewer trusts most.

## What is deliberately not in scope

Re-arguing any exemption. If the scan finds a handler that is neither gated nor argued, that is a
finding to file, not to fix here — this item's promise is that the counts are true again.

The three cross-tenant rows (the owner's read and three writes) are maintained by hand and are
current; they are short enough to be, which is why they did not drift and the long rows did.

## Done when

- [x] The first five rows of the table are re-derived from a scan of `main`, with the method recorded
      so the next re-derivation is mechanical rather than archaeological — `tools/tenant-isolation-scan/`,
      two scripts, pinned to `ago-chat@713635b`.
- [x] Every handler the scan newly reveals is placed in one of the existing categories. **Zero
      unaccounted**: every one of the 111 entry points is either RBAC-gated or carries a stated reason
      in `TenantScopeExemptions.cs`. Nothing was filed as an orphan because nothing was orphaned.
- [x] The dated staleness note is removed, because it is no longer true.
