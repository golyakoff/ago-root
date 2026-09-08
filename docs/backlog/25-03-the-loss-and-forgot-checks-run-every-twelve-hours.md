# the "loss and forgot" checks run every twelve hours, and email is enough

- **Stage**: 25
- **Status**: done
- **Depends on**: nothing. The checks already exist; nothing calls them.
- **Decision**: the author's, 2026-09-06 — **every 12 hours, not weekly**, and **email is enough**:
  *"главное здесь — исправить, мне не важно, что было неправильно, если исправил"*

## Goal

Nothing that has been lost or forgotten stays that way for more than half a day, and finding out costs
nobody an act of remembering.

## What is actually true today

**Three scripts exist and none of them runs on its own.**

| Script | What it catches | What calls it |
|---|---|---|
| `tools/queue-audit.sh` | A ticket whose Done-when are all ticked and is still open; merged code with no documentation half; **uncommitted work in a worktree for an open item** — which exists nowhere else, on no branch and in no commit; an ADR file with no row in its own index | Nothing. Whoever remembers |
| `tools/secrets-audit.sh` | A secret a manifest, an `.env.example` or a workflow uses and `secrets.md` does not name | Nothing |
| `tools/tenant-isolation-scan/` | The five headline counts in `tenant-isolation.md`, re-derived from source | Nothing |

Every one of them was written **because something had already been lost**, and every one has caught
something since — including, on the day it was written, two `Accepted` ADRs that had been invisible in
their own index for months, and the console and widget halves of `23-09` sitting in a worktree where
nothing could see them.

## Why twelve hours rather than a week

The author's call, and the reasoning is about what these checks watch for. They do not watch a system
that degrades slowly; they watch **work that vanishes** — a half-finished branch, a ticket left open
after its code merged, a secret introduced without a row. Those are wrong the moment they happen, and
every hour they stay wrong is an hour somebody might build on them or re-do them.

A weekly sweep would have let `23-09`'s two halves sit uncommitted for six more days.

## Scope

- Something runs all three checks on a schedule, **twice a day**, against freshly fetched checkouts of
  every repository they read.
- **Email on a finding, and nothing on a clean run.** The author's own instruction: what matters is
  that it gets fixed, not a report of what was wrong. A cron that mails on success trains its reader to
  filter it.
- The run must distinguish **"could not look"** from **"nothing to see"**. `queue-audit.sh` already
  makes that distinction for an unreachable GitHub and it must survive the scheduling — a sweep that
  silently checks nothing is the failure these scripts exist to prevent, reproduced one level up.
- **The uncommitted-worktree check cannot move off this machine**, and that constrains where this
  lives. Nothing in GitHub can see a worktree on a developer's disk.

## Out of scope

- Fixing whatever a run finds. It reports; a person or a session acts.
- Any new check. Three exist; this item is about calling them.
- The isolation counts' own mechanism — that is `24-17`, and the two are complements: `24-17` makes the
  number impossible to get wrong, this makes somebody look.

## Done when

- [~] All three run twice a day without anybody starting them. `tools/run-loss-and-forgot-checks.sh`
      calls all three and is demonstrated end to end (dry run, real repository state,
      `docs/runbooks/loss-and-forgot-checks.md`); the Windows Task Scheduler registration that makes
      it actually recurring is written and documented there but **not run** — registering persistent
      machine configuration is the author's own action, not this change's to take.
- [~] A finding reaches the author by email; a clean run is silent. The clean-is-silent half is
      demonstrated for real (see the runbook). Delivery reuses `adr/0045`'s existing node Postfix
      over SSH rather than inventing a sender — no new secret — but the actual send was not exercised
      by this change (no live systems touched); `--dry-run` shows the composed message instead.
- [x] A run that could not reach a repository says so, and is not reported as clean. Demonstrated for
      real: today's live sweep hit this path unprompted when `ago-deploy` had diverged from
      `origin/main` mid-session, and reported CANNOT-LOOK rather than a stale clean sweep.
- [x] The worktree check still runs somewhere that can see the worktrees. By construction — the
      whole sweep runs on this machine, specifically so it can (see the runbook's "why everything
      runs here" section).

## Open questions

- **Where it runs, given the worktree constraint — settled while implementing this item.** All three
  checks run on this machine via Windows Task Scheduler; none moved into CI. The reason is the one
  named below: splitting would have been a third shape costing two places to look, for no offsetting
  gain, since the other two checks also need the local sibling-repository workspace and a hosted
  runner would need its own mail credential besides. See `docs/runbooks/loss-and-forgot-checks.md`.
- **Whether `ago-root` should gain CI at all for this — answered no, for now.** It still has none.
  The reasoning above is this item's own reason for that, not a claim that the general question is
  closed for good.
