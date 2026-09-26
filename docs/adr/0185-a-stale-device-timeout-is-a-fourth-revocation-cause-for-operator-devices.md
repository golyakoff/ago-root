# ADR-0185: A stale-device timeout is a fourth revocation cause for `operator_devices`

- **Status**: Accepted; amends `adr/0179` §1.
- **Date**: 2026-09-26
- **Stage**: 26

## Context

`adr/0179` §1 named exactly three ways an `operator_devices` row is ever revoked - explicit sign-out,
the provider reporting the token gone, and an operator being removed from the site - and said so
because a fourth, timer-based cause seemed actively harmful: "a phone in a drawer for three weeks is
not a revoked device, and guessing otherwise silences somebody's notifications for a reason they
cannot see." That ruling depended on the second cause actually working for every dead token, because
it was the only mechanism that would ever notice one nobody explicitly signed out.

`26-83`'s live investigation (found 2026-09-25, on the demo stand, while chasing an unrelated
push-timing anomaly) found one operator holding five active `operator_devices` rows - one FCM and four
stale RuStore - from ordinary reinstalls and re-logins, each one still fanned a push to on every
assignment and message. `26-122` (fix A, landed) closes the common case: a device now upserts by a
stable `device_id` instead of always inserting, so a reinstall replaces its own prior row rather than
adding one. But that mechanism's reach is bounded by the id actually surviving the reinstall -
`26-122`'s own remarks on why `Settings.Secure.ANDROID_ID` was chosen over a stored UUID state plainly
that it "usually" survives across OEMs and Android versions, not always, and there is no fleet of real
hardware this project can test that claim against. Whenever it does not survive, fix A degrades to
"dedups within one install" and the old row is orphaned exactly as before.

The reason that orphaned row does not eventually clean itself up via `adr/0179`'s second cause is the
finding this ADR exists to record: RuStore's send API keeps answering `200 OK` for a send to some of
these dead tokens, never the `400 INVALID_ARGUMENT`/`404 NOT_FOUND` `NotifyOperatorDevicesHandler`
already treats as terminal (`push-notifications.md`'s own outcome table). "The provider tells us, on
the next send, and we believe it" - `adr/0179`'s own stated reason a sweep job was unnecessary - is not
true for this specific, observed case. A row like this lives forever under `adr/0179` alone.

## Decision

`Ago.Chat.Worker` gains a periodic `OperatorDevicePruneJob` (`OperatorDevicePruneQuery`,
`OperatorDevicePruneJobOptions`) that revokes any row with `revoked_at IS NULL AND last_seen_at < now -
Threshold`, `Threshold` defaulting to 14 days. This is the fourth revocation cause `adr/0179` §1 said
did not exist, added because the finding above shows the other three are not sufficient on their own:
none of them can reach a token the provider itself never reports dead.

The threshold is checked against a real, verified refresh mechanism, not invented (`CLAUDE.md`'s "do
not invent numbers" applies to a retention window exactly as it does to a benchmark).
`RegisterOperatorDeviceHandler`/`OperatorDevice.Refresh` is the only writer of `LastSeenAt`, and it
runs on every registration call - `ago-android`'s `WorkManagerDeviceRegistrationScheduler` schedules
that call once every 24 hours (`PERIODIC_INTERVAL_HOURS = 24`, a `CONNECTED` constraint), independent
of push activity or the app being opened, specifically so a token rotation missed while the app was
not running is still caught. A live device therefore refreshes `LastSeenAt` at least once a day
whenever it has any network at all. Fourteen days is fourteen times that cadence: wide enough that
ordinary lost connectivity (travel, a SIM swap, Doze deferring one run under load) is never mistaken
for abandonment, narrow enough that a genuinely dead registration - uninstalled, wiped, or a RuStore
token nobody can send to any more - is caught well inside the window `26-83` needs closed.

The job revokes; it never deletes and never sends. `Revoke` is `OperatorDevice`'s own existing,
idempotent mutation - the same one every other cause already calls - so a pruned row is
indistinguishable in shape from a signed-out one, keeps the same audit trail, and a device that comes
back online simply re-registers and `Refresh` clears `RevokedAt` exactly as it already does for a
returning sign-in (`OperatorDevice`'s own remarks on why `Refresh` clears revocation deliberately).

## Consequences

`adr/0179`'s own "three weeks in a drawer is not revoked" example is now false at the default
threshold, stated here rather than left for a reader of that ADR to discover on their own: a device
quiescent for a full two weeks - never opened, never granted a background run - is revoked by this
job. That is the trade being made deliberately: a stale RuStore row that would otherwise accumulate
forever (the actual, observed `26-83` defect, now with a bound) against an operator whose phone had no
network for two straight weeks needing one more sign-in or foreground open to restore push. Restoring
it costs nothing beyond that one ordinary registration call - not a reinstall, not lost data - and
`NotifyOperatorDevicesHandler`'s existing `no_devices` suppression path already treats "this operator
currently has zero active devices" as a normal, metered outcome, not an error.

No migration: `last_seen_at` and `revoked_at` already exist (`26-03`, `26-122`). No new port: the job
is raw Npgsql in `Ago.Chat.Worker`, the same shape `AccessRecordPruneJob`/`OutboxPruneJob` already
establish for a bounded-batch retention sweep, so it adds one more instance of an existing pattern
rather than a new one. `ago.chat.push.tokens_revoked`'s `cause` tag gains a fourth value
(`stale_timeout`), so the existing "how did each row die" observability line still accounts for every
row once this job exists.

## Alternatives considered

- **Do nothing until `26-122`'s device id is proven to survive every real reinstall.** Rejected: the
  live incident this ADR responds to needs a bound now, and there is no fleet of real OEM hardware this
  project could test that survival rate against to ever call it "proven."
- **A shorter threshold matched more tightly to the 24-hour heartbeat (e.g. 48 hours).** Rejected as
  needlessly aggressive - it would revoke a device on nothing worse than one bad weekend of
  connectivity, trading a cosmetic stale row for an avoidable false revoke of a device that is not
  actually dead.
- **Delete the row outright instead of revoking.** Rejected: `Revoke` is the aggregate's own existing
  idempotent mutation, already used by every other cause, and keeps the row as the same auditable trail
  a sign-out or a `TokenGone` revoke leaves; a hard delete would need its own erasure-shaped
  justification (`personal-data.md`) this item does not have and does not need.
- **Have RuStore's own `UNREGISTERED` status cover this instead.** Rejected: `push-notifications.md`'s
  own "two documented gaps" already flag `UNREGISTERED` as present in RuStore's field description but
  absent from its enumerated error list - unverified, so a design cannot depend on it arriving for the
  case this ADR exists to close.
