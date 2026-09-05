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

## 0.7. A worker is a colleague, not a disposable process

**Decided by the author, 2026-08-26**, after a day in which every task got a freshly spawned worker
and each one paid the full cold start again.

**Continue an existing worker rather than spawning a new one.** A worker that has already read
`CLAUDE.md`, the conventions and a repository's layout keeps all of that; a new one buys it again at
full price. Send the next task to the worker that is already carrying the relevant context. **A task
is always finished in the worker where it started** — a follow-up, a fix, a review comment and a
rebase all belong to whoever did the original work, and handing one to a fresh worker is strictly
worse than handing it to the one that has the file open.

The saving grows with parallelism, which is why it is worth establishing while running one worker:
with three lanes refilled all day, a cold start per refill is most of what the lanes cost.

**Each new task still begins with its own fresh worktree**, per repository, exactly as before. The
worker keeps its context; it does not keep its working directory. Two tasks sharing a worktree is
the problem that rule was written for and reusing a worker does not change it.

**The operator cleans up — but not everything.** After a task's PRs merge, the managing session
removes that task's worktrees (`git worktree remove`, and the branch once it is merged). The worker
does not do this — it is not what a worker is good at, and a half-cleaned worktree is worse than an
abandoned one.

**Never touch `.claude/worktrees/`, and do not run `git worktree prune` in a repository with a worker
you may want back.** Those directories are the agent runtime's own isolation worktrees, not task
worktrees, and **they are what makes a worker resumable**. A worker that does all its real work in
per-repository worktrees it created itself leaves its isolation worktree unchanged — which can get it
auto-cleaned — and `prune` then drops the registration, leaving a directory git resolves *upwards*
into the parent repository. The agent then refuses to resume: `work-tree-elsewhere`, and the
directory is held open so it cannot even be removed by hand.

Found on 2026-08-26, immediately after the cleanup rule above was written, by trying to hand `8-08`
to the worker that had done `16-05` and being refused. `prune` does not work by branch name at all,
so a branch filter cannot protect it.

**Remove only the worktrees this task created, by name. Never sweep by a computed property.**

This is the part that matters, and it was learned twice in one hour by getting it wrong twice. The
tempting shape is a filter — "every worktree whose branch matches a merged PR and has no uncommitted
changes" — and it is wrong because it decides what to delete from *evidence of doneness* rather than
from *ownership*. Everything that looks finished and belongs to somebody else passes it.

Both failures on 2026-08-26 were the same filter:

- Agent isolation worktrees, above.
- **The author's own parallel session's worktree**, whose branch had merged and which was clean, so
  the filter took it. A named exclusion list had protected it on an earlier run of the same procedure
  and was not carried into the next one — which is the argument against exclusion lists too. An
  allow-list cannot be forgotten the same way: a directory that is not named is not deleted, and no
  new category of thing needs to be anticipated to stay safe.

So: when a task's PRs merge, remove the worktrees whose paths the brief named for that task, and
nothing else. If a directory is left behind because nobody wrote it down, that costs disk. The other
failure mode costs somebody their working session.

### Where reuse stops paying

Retained context is only an asset while it is *relevant*. A worker that has done three unrelated
items carries three transcripts, and every later request pays for all of them — so route by area,
not round-robin: give a worker tasks in the repository and subsystem it already knows. When the next
task shares nothing with what a worker holds, a fresh one is the cheaper choice, and saying so is
part of the operator's job rather than a defeat.

## 0.75. Three lanes, held full

CLAUDE.md rule 13. **Three background workers on `sonnet`, each in its own isolated worktree, with
pull requests opened strictly one at a time — and a lane refilled the moment it frees, not when two
others have caught up.** This is the normal state and needs no request; the author saying "го по
жире" means resume it after a pause, not start a wave.

**One of the three is the migration lane.** Items needing an EF migration go there and nowhere else,
one at a time; the other two lanes take items that need none. Two concurrent `ef migrations add` in
one repository is a certainty, not a risk: both rewrite `AgoChatDbContextModelSnapshot.cs`, which
holds the whole model. The conflict is the visible half. The dangerous half is resolving it by taking
one side, which drops the other branch's columns from the model state and makes the *next*
migration a diff against a snapshot that lies — a failure that surfaces two items later.

**Do these items actually not interfere?** Decide before spawning, and decide it against *files*, not
topics. Two items collide when they share a file, when both touch `docs/adr/README.md` or a stage
section of `docs/roadmap.md`, or when one's output is the other's input. Sharing a repository is not
a collision; sharing a `package.json` is. Refilling one lane at a time makes this cheaper than a wave
did — one new item placed against two known ones, rather than three placed against each other. **When
in doubt, run two.**

**Sequential PRs, and this is the half that gets skipped.** Two branches cut from the same `main` and
opened together means the second is stale the instant the first merges, and a pushed branch with a
stale base is close-the-PR-and-rebuild rather than a rebase (`git-workflow.md`, CLAUDE.md rule 10).
Workers may finish in any order; their PRs go up in one order, each cut from the `main` that already
contains the last. §5's one-open-PR-at-a-time rule for the shared index generalises to every PR.

Nothing else changes: workers still never spawn anything (rule 12), never run `git commit`/`git push`
(rule 9), and end at a commit-prep block the managing session executes.

## 0.8. A worker implements. It does not organise.

**Decided by the author, 2026-09-02**, and now CLAUDE.md rule 12: a worker never spawns another
agent. If it thinks the task warrants delegation, it says so in its report and stops — the decision
is the author's.

The reason this needs its own section is that **the brief itself causes the failure**, and it did so
twice in one day with two different agents. Both were told "implement backlog item `NN-NN`", and both
read that as *organise the implementation of `NN-NN`*: they did reconnaissance, wrote a plan, spawned
a child, and reported the plan as their result. Neither wrote a line of code.

So write the brief for an implementer, out loud:

- Open with what the worker will **do**, not what it will manage. "Implement" is ambiguous to an
  agent that has tools for both; "**Write the code yourself. Do not delegate. Do not spawn anything**"
  is not.
- Put the no-spawning rule in the standing block below, in those words.
- Ask for the fails-before table and the verification counts as the *deliverable*. A brief whose
  deliverable is a plan will get a plan.

### And when a worker reports that it delegated, check before reacting

The second failure was the managing session's, not the worker's. A worker said it had "dispatched a
background worker"; the managing session looked for worktrees and branches, found none — too early
for them to exist — concluded nothing had been dispatched, and told that worker to do the work
itself. Both then edited the same worktrees at once, and the collision cost real time and produced a
report full of hazards that were the other agent.

**`ListAgents` answers "is something already running". An absent directory does not.** Check it
before concluding, and if a child is genuinely running, let it finish: telling the parent to start
over is what creates the collision. Send the parent an instruction for what to do *when the child
returns* instead.

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

**No spawning.** A worker never spawns another agent — CLAUDE.md rule 12. Say it in the brief in
those words, and say what to do instead: *if you think this warrants delegation, say so in your
report and stop.* See §0.8 for why the brief has to say it out loud.

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

**Tell the worker to read its own background run out of the file, never to wait for it.** A completion
notification goes to the *managing session*, not to the worker, so a worker that ends its turn saying
"I'll resume when the suite finishes" has **stopped**, not paused — it waits for a message that will
never arrive, and the managing session has to spend a turn waking it. This happened four times in one
day (2026-09-04) across four different workers, so it is the default behaviour rather than an
individual's mistake. The brief has to say: the tool result that started the run gave you its output
path; read that path, and if the run produced no summary, run it again in the foreground.

**And say what a truncated run looks like**, because it is indistinguishable from a clean one unless
the worker is told what to check. Three specific traps have each cost this project a false green:
`dotnet test` can abort part way, print a pass line for every assembly it *did* finish, and still exit
0 — so read which assemblies are **missing**, not the failure count. A pipeline like
`dotnet build … | tail -3 && dotnet test` takes its exit status from `tail`, so a failed build is
stepped straight over. And **report only what you have watched finish**: two workers in one day
reported a clean format check that was not clean, having written the report before their own run
completed.

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
- **Migrations go in the migration lane, one at a time** (rule 13, §0.75). Two workers adding EF
  migrations to the same repository both rewrite the model snapshot. That is not a risk, it is a
  certainty — so the brief says explicitly whether this item is the lane's current occupant.
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
