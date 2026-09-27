# 26-123 · [chat] Prune device registrations not seen for N days — fix B for accumulating device rows

- **Stage**: 26 — part of `26-83`'s device-registration cleanup (safety net complementing `26-122`/A).
- **Status**: done — `OperatorDevicePruneJob` shipped (ago-chat#370); ADR-0185 records the 4th
  revocation cause (ago-root#1673).
- **Found**: 2026-09-25, same investigation as `26-122`.

## Why (on top of A)

`26-122`/A replaces a device's own prior row on re-registration — but only reaches across a reinstall if
the device id is stable. When it is not (a wiped stored UUID), reinstalls still accumulate rows. B is the
unconditional backstop: **revoke registrations whose `last_seen_at` is older than a threshold** (e.g. 14
days), regardless of provider. RuStore returning 200 for dead tokens (so revoke-on-TokenGone never fires
for them) is exactly why a time-based prune is needed — a dead RuStore row would otherwise live forever.

## Scope

- A periodic Worker job (the existing `PeriodicTimer`/`BackgroundService` shape) that sets `revoked_at` on
  `operator_devices` rows with `last_seen_at < now - Threshold` and `revoked_at is null`. Threshold is a
  validated option; default ~14 days, justified in a comment (not an invented number — tie it to how often
  a real operator's device checks in / refreshes its token).
- Ensure `last_seen_at` is actually refreshed on real device activity/token refresh so a live device is
  never pruned (confirm the refresh path exists; if not, that is part of this).
- No push is sent by this job; it only revokes stale rows.

## Out of scope

- The replace-by-device-id mechanism (`26-122`/A).

## Done when

- [x] A registration unseen past the threshold is revoked; a recently-seen one is not. — ago-chat#370
      (8428571), `OperatorDevicePruneJob` revokes rows unseen >14d, bounded-batch, revoke-not-delete.
- [x] `last_seen_at` is confirmed to refresh on real device activity. — confirmed: it refreshes on every
      registration Refresh, so live devices are never pruned (issue close note).
- [x] Test proves prune-past-threshold / keep-recent; ago-chat suite green, counts reported. Migration only
      if genuinely needed (say which). — ago-chat#370, no migration needed.
