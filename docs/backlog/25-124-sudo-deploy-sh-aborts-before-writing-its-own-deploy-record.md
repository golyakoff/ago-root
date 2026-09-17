# 25-124 · `sudo deploy.sh` aborts before writing its own deploy record

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: 2026-09-17, the managing session hand-patching `ago-deploy-record` a third time in one
  session and finally tracing why: every `sudo ./deploy.sh <sha>` run this session left the record
  stale even though the rollout and smoke both genuinely succeeded.

## What is actually true today

`deploy.sh` line 41: `AGO_ROOT="${AGO_ROOT:-$HOME/ago}"`. Line 285:
`CHAT_REPO="${CHAT_REPO:-$AGO_ROOT/ago-chat}" "$HERE/smoke.sh" "$DOMAIN"`. Run as `sudo ./deploy.sh`
(this repository's own documented invocation, `docs/runbooks/redeploy.md`), `$HOME` is `/root` -
`sudo`'s default `env_reset` behaviour - not `ago`'s real home (`/home/ago`), so `AGO_ROOT` resolves to
`/root/ago` and `CHAT_REPO` to `/root/ago/ago-chat`, a path that does not exist (the real checkout is
`/home/ago/ago/ago-chat`).

`smoke.sh`'s own migration check then genuinely fails - not skips - because `CHAT_REPO` is *set* (to a
wrong value), so `[ -n "$CHAT_REPO" ]` is true and the check runs, finds no migration files at that
path, and reports `bad "could not compare migrations..."`, exiting `smoke.sh` non-zero. Run standalone
with no `CHAT_REPO` set at all, the identical check correctly `skip`s instead - the two look
superficially similar in the terminal ("one line differs from 45 passes") but are structurally
different outcomes, and only the second is benign.

`deploy.sh`'s own call to `smoke.sh` at line 285 is **not** wrapped in `|| true` (unlike the
`check-manifest-drift.sh` call just above it, which is deliberately advisory) - its own comment says
why: "a failed smoke does the same [as a failed rollout]" - under `set -euo pipefail`, a non-zero
`smoke.sh` exit aborts `deploy.sh` immediately, before it ever reaches `record_write` on the next line.
**The deploy itself (image rollout) already succeeded** - `kubectl set image` ran well before this
point - so the operator sees 44 real passes, one `bad`, and a deploy that "worked", with no indication
that the deploy-record half of the promise (`23-90`'s whole reason for existing) silently never ran.

## Why this matters, concretely

`23-90`'s own mechanism exists specifically to catch "two deploys happened with no manifest commit
between them" - a real incident from 2026-09-07. A deploy-record write that silently, structurally
never happens under the documented `sudo` invocation defeats that mechanism exactly as thoroughly as
never having built it, except now with a false sense that it is protecting something. This session hand-
patched the ConfigMap three times (`25-119`'s frontend pins, `25-121`'s chat pin, `25-122`/`25-123`'s
console pin) to keep `check-manifest-drift.sh` honest - a workaround, not a fix, and one a future
session will not know to reach for without rediscovering this same chain of reasoning.

## Where this is likely to go wrong

- **Do not just wrap the `smoke.sh` call in `|| true`.** That would silence a genuine rollout-health
  failure too (an actually-broken deploy), which is the real thing that line's own comment says this
  guard exists to catch - the migration-check false-failure is a narrower, specific bug in `CHAT_REPO`'s
  own path resolution, not a reason to weaken the guard around everything else `smoke.sh` checks.
- **`$HOME` under `sudo` is the root cause, not something to work around per-script.** Consider whether
  `AGO_ROOT`'s own default should resolve `ago`'s real home explicitly (`$(getent passwd ago | cut -d:
  -f6)`, or `SUDO_USER`-aware resolution) rather than trusting `$HOME`, since this VPS's own documented
  operating mode is exactly "run every one of these scripts with `sudo`" - `docs/runbooks/redeploy.md`
  and every recent session's own command history agree on that.
- **Two real, different outcomes currently print almost the same shape** ("N passed, 1 failed" vs skip)
  - whatever the fix, make the genuinely-broken case and the wrong-path case impossible to confuse
    again, not just fix the one path.

## Done when

- [ ] `sudo ./deploy.sh <sha>` on the real VPS completes cleanly end to end, including a real
      `record_write`, without hand-patching `ago-deploy-record` afterward.
- [ ] `check-manifest-drift.sh` reports `PASS` immediately after such a deploy plus its manifest commit,
      with no manual intervention.
- [ ] The migration-schema check still genuinely fails (not skips) when a real schema mismatch exists -
      confirm this by a real fails-before check, not by trusting the path fix alone.
