# Runbook: the "loss and forgot" checks

`25-03`. Three scripts already existed and had each already caught something real before this
existed - `tools/queue-audit.sh`, `tools/secrets-audit.sh`, `tools/tenant-isolation-scan/` - and
nothing called any of them. This is what calls them: `tools/run-loss-and-forgot-checks.sh`, run
twice a day from this machine, quiet when there is nothing to report and short and actionable
otherwise.

## What runs, and where

| Part | Runs | Does |
|---|---|---|
| `tools/run-loss-and-forgot-checks.sh` | this machine, twice a day via Windows Task Scheduler | Runs the three checks, classifies each CLEAN / FINDING / CANNOT-LOOK, mails on anything but CLEAN, always appends one line to the heartbeat log |
| `tools/queue-audit.sh` | called above | The full audit - GitHub issues plus the local worktree/primary-checkout/ADR-index scan. **This is why everything below runs here and not in CI**: no GitHub-hosted runner can see this machine's worktrees |
| `tools/secrets-audit.sh` | called above | Sweeps `ago-deploy`'s manifests plus every sibling repository's workflows, after fast-forwarding `ago-deploy` to `origin/main` (see below) |
| `tools/tenant-isolation-scan/scan_entry_points.py` / `scan_routes.py` | called above | Re-derives the isolation counts from a fresh `git archive origin/main` of `ago-chat` - never touches that checkout's working tree |
| `tools/run-loss-and-forgot-checks.test.sh` | by hand, or whenever the classification changes | Unit tests for the CLEAN / FINDING / CANNOT-LOOK decision, against canned fixtures - no git, no ssh, no network |

## Why everything runs here, not split into CI plus a local piece

`docs/backlog/25-03-*.md`'s own open question weighed this: a GitHub Actions workflow can reach
every repository's issues and cannot see this machine's disk; `queue-audit.sh`'s worktree scan
needs exactly that disk. Splitting the other two checks into CI and leaving only the worktree scan
here was the alternative, and the item's own text already names the cost: "a third shape and costs
two places to look." All three checks already assume the local sibling-repository layout
`docs/runbooks/workspace.md` describes, and a hosted runner would need its own credential for
outbound mail besides, since it cannot reach the node's zero-credential Postfix (see below). So
this stays a single Windows Task Scheduler job, and `ago-root` stays without CI for this reason -
a decision made in the course of implementing this item, not settled by `25-03` itself, which left
it open.

## Mail: reused, not invented

This deployment already has exactly one path from a condition to a person's inbox: `adr/0045` -
the node's own Postfix, zero credential, addressed to `alerts@reserve-me.ru`, already carrying
real traffic from `ago-deploy/k8s/backup/backup-watchdog.sh` today. `adr/0040` had, one day before
`adr/0045`, already weighed a hosted mail provider against self-hosting and ruled out every third
party - payment (the author's Russian-issued cards do not clear at Western vendors, `adr/0026`)
and data-residency reasons that apply here exactly as they applied there.

So this script does not add a mail sender. It reaches the existing one the same way a person
already does to run `backup.sh` by hand (`docs/runbooks/backup-and-restore.md`) - over SSH, with
the same key, because nothing on this Windows machine can otherwise address a Postfix that only
takes mail from the k3s bridge or from `localhost` on the node itself:

```
run-loss-and-forgot-checks.sh  --(ssh -i ~/.ssh/ago-vps-ed25519 ago@$AGO_NODE)-->  sendmail -t on the node
                                                                                          |
                                                                                          v
                                                                                 alerts@reserve-me.ru
                                                                            (node mbox + the author's real mailbox,
                                                                             the latter named in /etc/aliases only)
```

No new secret exists because of this item. `AGO_NODE` is supplied at run time, the same way
`backup-pull.sh` already takes it - never written into this repository (`CLAUDE.md`: no real
endpoint in a public repository; the node's address is `<node-ip>`).

## Registering the Task Scheduler job

Run the script once by hand first, in dry-run mode so nothing is mailed:

```bash
cd C:/git/ago/ago-root
bash tools/run-loss-and-forgot-checks.test.sh   # the unit tests - fast, no network
bash tools/run-loss-and-forgot-checks.sh --dry-run
```

Confirm it prints a summary line (`queue-audit=... secrets-audit=... tenant-isolation=...`) and,
on anything but an all-CLEAN result, the message it would have sent. Then register it for real,
twice a day twelve hours apart - times chosen only for being outside normal working hours, adjust
freely:

```powershell
$action  = New-ScheduledTaskAction -Execute 'C:\Program Files\Git\bin\bash.exe' `
             -Argument '-lc "AGO_NODE=<node-ip> bash tools/run-loss-and-forgot-checks.sh"' `
             -WorkingDirectory 'C:\git\ago\ago-root'
$trigger1 = New-ScheduledTaskTrigger -Daily -At 7am
$trigger2 = New-ScheduledTaskTrigger -Daily -At 7pm
Register-ScheduledTask -TaskName 'AGO loss-and-forgot sweep' -Action $action `
  -Trigger $trigger1,$trigger2 -Description 'docs/backlog/25-03: queue-audit, secrets-audit, tenant-isolation-scan, twice a day'
```

This mirrors `backup-pull.sh`'s own registration (`docs/runbooks/backup-and-restore.md`: "schedule
it daily - Windows Task Scheduler, or whatever is already scheduling things on that machine").
**This command is documented here, not run by this change** - registering a scheduled task is
persistent machine configuration, and making that change is the author's own action to take.

## Reading the result without opening a mailbox

A quiet-on-clean design cannot use the mailbox to answer "is this even still running" - a stopped
scheduler and a clean sweep both produce silence there, which is the exact failure this item's own
brief warns against. Two things answer it instead:

- **Task Scheduler's own history.** Every trigger, whether or not anything fired, leaves a "Last
  Run Result" - `0` clean, `1` a check found something, `2` a check could not look (widened from
  `secrets-audit.sh`'s own convention). Open Task Scheduler, find "AGO loss-and-forgot sweep",
  check History. A task with no recent run at all - not "0", literally absent - is the "did not
  run" state this exists to make different from "ran and found nothing."
- **`<workspace>/loss-and-forgot-history.log`**, one line appended on every run regardless of
  outcome (`LOSS_AND_FORGOT_LOG` to override). Not tracked by this or any repository, sitting
  beside the checkouts the way `.nuget-feed` does (`docs/runbooks/workspace.md`) - workspace state,
  not project state. A stale last line is the same "did not run" signal, readable without Task
  Scheduler's own UI:

  ```
  2026-09-07T08:04:03+00:00  CANNOT-LOOK  queue-audit=FINDING secrets-audit=CANNOT-LOOK tenant-isolation=CLEAN
  2026-09-07T08:04:22+00:00  CLEAN        queue-audit=CLEAN secrets-audit=CLEAN tenant-isolation=CLEAN
  ```

**The residual gap, stated rather than hidden**: neither of the above is itself pushed to a
person. If the scheduled task were deleted, or the machine were off for a long stretch, both would
sit silently stale and nobody is notified of that fact by this mechanism - the same gap a GitHub
Actions workflow would *not* have had (GitHub emails when it disables a scheduled workflow after
sixty days of repository inactivity), and the trade this item's implementation made in choosing
"everything on this machine" over "split across CI and this machine" (see above). Given how
active this repository is, sixty days of silence has not been a realistic risk so far - but the
asymmetry is worth knowing about the next time this design gets revisited, not worth building a
second watchdog for today.

## What each state means and what to do

| State | Meaning | What to do |
|---|---|---|
| CLEAN | Nothing to report. No mail is sent. | Nothing |
| FINDING | The check ran to completion and found something | Read the mail - it already carries the specific finding, trimmed to what is actionable. `queue-audit.sh`'s own "leftover, safe to remove once read" worktree list is deliberately left out; re-run `bash tools/queue-audit.sh` by hand for the rest. |
| CANNOT-LOOK | The check could not run to completion (GitHub unreachable, a sibling repository missing or unable to fast-forward, `python`/`git` unavailable, its own output shape unrecognisable) | Fix the stated cause (usually: connectivity, or fast-forward `ago-deploy` by hand if it has diverged) and re-run. This is never reported as clean. |

`tenant-isolation-scan`'s own headline-number drift against `docs/architecture/tenant-isolation.md`
is deliberately **not** one of the things that turns this FINDING - that is `24-17`'s mechanism to
fix, not this item's to detect a second way. What does turn it FINDING is the scan's own
correctness signal: an entry point neither gated nor on the exemption list, an exemption the scan
can no longer find, or an exemption listed for something that now also looks gated - the same
things `TenantScopeTests` would fail on.

## Testing

`tools/run-loss-and-forgot-checks.test.sh` exercises the CLEAN / FINDING / CANNOT-LOOK
classification against canned fixtures - no git, no `gh`, no ssh, no real checks. Run it with
`bash tools/run-loss-and-forgot-checks.test.sh`; it prints a pass/fail count and exits non-zero on
any failure, the same shape `prometheus-alert-rules.test.yml` uses for the alerting rules this
item's mail delivery reuses.

`bash tools/run-loss-and-forgot-checks.sh --dry-run` runs all three checks for real and prints the
message it would have sent instead of mailing it - the fastest way to see what a real run looks
like without touching the node.
