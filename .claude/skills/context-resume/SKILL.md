---
name: context-resume
description: Get back up to speed at the start of a session that continues after a /compact context refresh. Use as the first step whenever a conversation opens with a compaction summary, before taking any further action on the task it describes.
---

# Resuming after `/compact`

A compaction summary is a *description* of what happened, written by a previous instance of
yourself. It is not verified fact. Treat every concrete claim in it - "tests pass," "the fix is
applied," "committed and pushed" - the same way you'd treat a claim from a memory file: probably
right, but check before acting on it, especially before telling the user something is done.

## 1. Reconstruct state from the source of truth, not the summary

- `git status` and `git log --oneline -5` in every repository the summary says was touched. Confirm
  branch, confirm what's actually committed vs. what the summary says is committed.
- If the summary claims a build or test run succeeded, and the next action depends on that being
  true, re-run it rather than citing the old result - code may have changed since, or the claim may
  describe intent rather than an observed result.
- If the summary describes a bug fix "not yet verified," that's the actual next step, not a
  formality - do it before anything else the summary lists as pending.

## 2. Identify exactly where the task was interrupted

The summary's "Current Work" / "Pending Tasks" sections usually say this directly. Resume there, not
from the task's beginning. Do not redo steps the summary and the repository state agree are already
done - that wastes the user's time and re-litigates settled work.

## 3. Don't re-ask what's already answered

If the user's prior messages (preserved verbatim in the summary) already settled a question -
approach, scope, which repo, which branch - do not ask it again. Re-asking a settled question reads
as not having read the summary.

## 4. Proceed without narrating the resume

Per the project's `CLAUDE.md` and general session norms: don't open with "I'll continue from..." or a
recap of the summary back to the user. Just do the next verified step and report results as they
happen, the same as any other turn. The exception is when reconstruction reveals the summary was
*wrong* about something load-bearing (e.g., it claims something is committed and `git status` shows
otherwise) - that discrepancy is worth surfacing explicitly, since it changes what "done" means.

## Why this matters here specifically

This project's rule of never claiming success without having run and observed it (`CLAUDE.md`)
applies just as much to a summary of your own prior work as to a first-time claim. A session that
trusts a stale "tests pass, ready to ship" instead of re-checking it is the same failure mode as
claiming a feature works without opening a browser.
