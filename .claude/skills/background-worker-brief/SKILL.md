---
name: background-worker-brief
description: Write the brief for a background worker implementing one backlog item, and decide first whether that item deserves a worker at all. Use whenever a managing session is about to delegate implementation work.
---

# Briefing a background worker

A background worker starts cold. It re-derives every piece of context the managing session already
holds, which is the entire reason it is expensive and the entire reason it is sometimes worth it.
This skill is about spending that cost deliberately.

## 0. First decide whether to delegate at all

Measured on 2026-08-26, one wave of three workers cost roughly **840,000 tokens** — about ninety per
cent of that day's total, against 107, 130 and 201 tool calls respectively. A large share of those
calls was rediscovering repository structure the managing session already knew.

**Delegate when** the work is long, mechanical and verification-heavy: a vertical slice with a test
suite to run repeatedly, a migration to write and prove, a manifest change to apply and observe.
The worker's cost is amortised across dozens of build-and-test cycles the managing session would
otherwise pay for inline.

**Do it inline when** the work is mostly reading and deciding: documentation, an ADR, backlog
grooming, queue maintenance, a doc correction, a small fix in a file already open. A worker here
pays the full cold-start cost to reach a state the managing session was already in.

If unsure, ask what fraction of the work is *typing and running* versus *reading and choosing*. Only
the first kind amortises.

## 0.5. Check what already exists before briefing anything

A queue row means the *item* is unfinished. It does not mean **nothing has shipped**, and the two are
easy to conflate at the moment of delegating, because the queue row is the only thing being read.

Before writing the brief, in each repository the item touches:

```
git log --oneline --all --grep="<item>" -20
```

and read any Done-when box already ticked in the item file. Two minutes here, against a worker that
otherwise spends its opening moves discovering the situation.

`11-07` on 2026-08-26 is the case. Its theme had been built, merged (`fbda4cd`) and deployed the day
before; what remained was the anti-drift mechanism that first pass had named as a debt in its own
commit message, plus six unverified pages. The brief was written as though from nothing, and the
worker had to establish the real starting point itself.

**`tools/queue-audit.sh` does not catch this and is not meant to.** It flags rows whose Done-when
list has nothing left open. A part-finished item still has open boxes, so it is correctly *not*
flagged — the row belongs in the queue. Partial completion is a separate question, and the only
thing that answers it is looking.

When work already exists, say so in the brief: what shipped, what its author recorded as owed, and
what specifically remains. A brief that describes remaining work is far shorter than one that
describes the whole item, which is the second reason to check.

## 1. Standing rules — put every one of these in every brief

These do not vary by item. Restating them from memory is how they drift; copy them.

**Worktrees.** The worker creates its own fresh worktree per repository it changes, named for the
item, based on `origin/main` **after `git fetch`**. Never the primary checkout, never a worktree
another task is using (`git-workflow.md`).

**Base freshness.** `git merge-base HEAD origin/main` must equal `git rev-parse origin/main` before
the first push. While a branch is still local this is free to fix; once it is pushed with a PR open
it becomes close-the-PR-and-rebuild. See `git-workflow.md`.

**No history writing.** A worker never runs `git commit`, `git push`, or opens a PR — CLAUDE.md
rule 9 delegates those to the *managing session only*, and explicitly not to workers. The worker
ends with a commit-prep block per repository, each a shell script beginning with an explicit `cd`
(see the `commit-prep` skill). No `Co-Authored-By` trailer for an AI session.

**The two shared indexes are off limits.** `docs/roadmap.md` and `docs/adr/README.md` collide on
every concurrent item, because each one appends to the same region of the same table — five
collisions in a single day. The worker reports its ADR index row as text and never edits either
file; the managing session makes that edit once, at merge. Pre-assign the ADR number in the brief.

**Everything is public.** No secret, token, real endpoint or personal data in any repository —
including in a fixture, a test, an example log line or a commit meant to be fixed later. The VPS
address is written `<node-ip>`.

**Verification.** Whatever the repository's own command set is (CLAUDE.md's *Commands*), run it once
green — format, build with zero warnings, full suite with zero failures — and report exact counts
per test project. **Once is enough.** A worker that runs the full suite five times has spent four
suites proving nothing; the managing session re-verifies independently anyway.

**Fails-before is not optional.** Every new test must be shown to fail against the code without its
own check: delete or invert that production code, rebuild, capture the failure, restore. Report it
as a table. A test that passes against the unfixed code proves nothing, and the managing session
will check.

**Teaching mode.** For every file placement, interface and layer choice, state which principle drove
it and what the alternative would have been (CLAUDE.md). In the report, not as code comments.

## 2. What the brief must add on top

The standing rules are the floor. The brief earns its keep in what only the managing session knows:

- **Which repositories are in flight, and what that forbids.** Name any unmerged branch touching the
  same repository, the files it changes, and whether the worker may deploy. This is the highest-value
  sentence in most briefs. Concrete case: `ago-deploy`'s `main` was *not* what was deployed while
  `17-05` sat unmerged, so a worker verifying against the live cluster from `main` would have
  silently stripped a `securityContext` off a public deployment.
- **One migration per repository per wave, at most.** Two workers adding EF migrations to the same
  repository both rewrite the model snapshot. That is not a risk, it is a certainty.
- **Where the item is likely to go wrong**, in the managing session's judgement — not a summary of
  the item, which the worker will read anyway. Name the decision that is easy to get wrong and
  invisible when wrong.
- **What must be demonstrated rather than asserted.** Pick the one claim that would be worthless as
  an assertion and say it must be shown biting.
- **What is out of scope**, especially repositories the worker must not touch.

## 3. What to ask for in the report

Ask for the parts that are hard to reconstruct later: what the worker found that the documents got
wrong; what the item's spec did not name and had to be decided; the fails-before table; the exact
verification output; and **what remains unverified**.

Say plainly that an unmet Done-when reported honestly is worth more than a ticked one the managing
session has to disprove. Workers otherwise round towards done — the observed failure mode is
overstatement, not omission.

## 4. On the way back

Verify independently before landing. Re-run the suite; re-check any claim about a live system
against that system. Then follow `land-a-slice`.
