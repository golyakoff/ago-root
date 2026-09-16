# the owner's module list says revoked, not expired

- **Stage**: 23
- **Status**: done — landed `ago-chat#`-equivalent commit `487e8eb`, 2026-09-08. Reconstructed
  2026-09-16: this item shipped without ever getting a backlog file of its own — `queue-audit.sh`
  flagged it as an orphan (a commit scope with no matching file), found while chasing an unrelated
  session's own findings. `25-11`, the console-side follow-up this item's own commit message predicts
  ("the console half is deliberately not here... it lands separately"), already exists and names this
  item by number, which is what made reconstructing it possible.
- **Depends on**: nothing. `adr/0155` records the same revoke-vs-expiry distinction from the erasure
  side; this item is the read-side half for a site's own enabled-module list.

## What happened

`OwnerSiteModuleDto`/`EnabledModuleDetailSummary` carried a single `IsActive: bool` for a site's
enabled modules. Once `22-30` stopped deleting a revoked row (leaving it in place as a tombstone
rather than removing it), that boolean could no longer tell two very different things apart: a
platform owner's deliberate revoke, and a grant's own end date arriving unattended. Both read as
`IsActive: false`.

## What was done

- `IEnabledModuleReadStore`/`EnabledModuleReadStore`: the SQL that already computed `IsActive` now
  computes a `Status` string instead - `Active`, `Expired`, or `Revoked` - plus a `RevokedAt`
  timestamp. Decided once, in a single case expression, with `Revoked` taking precedence when a grant
  is genuinely both (a revoke is a deliberate, timestamped act; a revoke that also lapsed is still a
  revoke, not an expiry that happened to be timed conveniently) - so no second branch could pick the
  opposite order.
- `ExpiresAt` survives a `Revoked` status rather than being hidden - a grant can be both, and hiding
  the date would throw away a fact the row still carries.
- Each row also gained its own `Id`. `adr/0155` already records that a revoke-then-re-grant leaves two
  rows for one module; `GetAllForSiteAsync` was already unfiltered (both rows always came back), but
  with nothing beyond `ModuleKey` to key them by, two rows for one module were indistinguishable on
  the wire.
- `AllSql` also gained an explicit `order by enabled_at`, which it never had, so a site's own grant
  history now reads chronologically instead of in whatever order Postgres happened to return rows.
- Deliberately **not** included: the console. Rendering two rows for one module, and what to show for
  each status, is a decision rather than a mechanical rendering, and the commit message says as much
  - it landed separately as `25-11`, found live the next day when nothing had updated the console to
  match this item's own new contract.

## Done when

- [x] `OwnerSiteModuleDto`/`EnabledModuleDetailSummary` carry `Status`/`RevokedAt`, not a boolean that
      cannot distinguish a revoke from an expiry.
- [x] A revoked-then-re-granted module's two rows are individually addressable (`Id`), not merged or
      indistinguishable by `ModuleKey` alone.
- [x] A site's enabled-module history reads in grant order.
- [~] The console renders the new contract - not this item's own scope (its own commit message states
      the split), settled by `25-11` landing separately rather than left as this item's own unmet box.
