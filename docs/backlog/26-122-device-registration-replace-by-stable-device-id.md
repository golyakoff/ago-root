# 26-122 · [android+chat] Re-registering a device replaces its prior registration (dedup by stable device-id) — fix A for accumulating device rows

- **Stage**: 26 — part of the `26-83` push-noise cleanup (device-registration accumulation axis).
- **Status**: ready — direction decided (author: A+B; C folded into A).
- **Found**: 2026-09-25 — one operator had 5 active registrations (1 FCM + 4 stale RuStore) from repeated
  reinstalls/re-logins; each push event fanned out to all 5. The stale rows were revoked by hand on the
  stand as immediate relief; this item is the mechanism so it does not recur.

## Fix A

A device that registers for push should **replace its own prior registration** rather than add a new row,
so a reinstall / re-login / transport switch (RuStore→FCM) updates one row instead of leaving the old one
live. This subsumes option C (revoke-old-RuStore-on-switch): keyed by device, a switch is just a
re-registration that replaces the prior row regardless of provider.

- **Client (`ago-android`)**: send a **stable device identifier** with the registration. Caveat that
  decides A's reach: it must survive an app reinstall to dedup across reinstalls. `Settings.Secure.ANDROID_ID`
  is stable per signing-key per device (survives reinstall) — evaluate it (and its privacy/OEM caveats)
  vs. a stored UUID (which a reinstall wipes, making A degrade to same-install-only and leaning on `26-123`/B).
  Pick one, state the trade-off.
- **Server (`ago-chat`)**: `operator_devices` upsert keyed by (operator_id, device_id) — a new token/provider
  for the same (operator, device) **replaces** (or revokes-and-replaces) the existing row rather than
  inserting. Needs a `device_id` column + migration (migration lane). Preserve the existing revoke-on-
  TokenGone behaviour.

## Out of scope

- Time-based prune of unseen registrations — that is `26-123` (fix B, the safety net for when the id is
  not stable across reinstall).
- The push-storm churn fix (26-119 A / 26-120 C) — different axis.

## Done when

- [ ] A device re-registering (reinstall / re-login / RuStore→FCM) results in **one** active row for that
      (operator, device), not an added one; the prior row is revoked/replaced.
- [ ] Client sends a stable device id; server upserts by (operator, device). Migration via the migration lane.
- [ ] Tests both sides; ago-chat + ago-android suites green, counts reported.
