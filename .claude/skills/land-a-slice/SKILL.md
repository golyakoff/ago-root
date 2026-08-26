---
name: land-a-slice
description: The managing session's own procedure for turning finished work into merged commits - verify, check the base, push, open PRs in the right order, and sweep the queue. Use after a slice is done, whether a worker built it or this session did.
---

# Landing a slice

`commit-prep` is the *worker's* side: it ends at a drafted command block. This is the other side.
CLAUDE.md rule 9 lets the managing session run those commands directly on a feature branch, and
every step below exists because skipping it has already cost this project something specific.

**Merging is never this session's action.** Opening a PR is not merging it. That is unchanged.

## 1. Verify independently, before anything else

A worker's report is evidence, not proof. Re-run the repository's own command set (CLAUDE.md's
*Commands*) and read the counts yourself. If the work touched a live system, check the live system
rather than the claim about it.

The failure mode to watch for is overstatement, not fabrication: "both overlays build" when one of
them cannot be rendered off-node; an ADR written but never added to its index; a control described
as protective that refuses nothing. Ask of each headline claim: *what would I see if this were
false?* Then go look at that.

### "0 failed" is not the same as "the suite ran"

`dotnet test` can abort part way — a crashed test host, a killed process — and still print
`Пройден!` for every assembly it *did* finish, print no total, and **exit 0**. A truncated run is
indistinguishable from a clean one unless you look at what is missing.

So read the assembly list, not just the failure count: **all six `Ago.Chat.*` projects, all five
`Ago.Calendar.*` ones, and the per-project counts summing to the number being claimed.** A run that
silently dropped thirteen integration tests happened twice in one day here, once to a worker and once
to me, and both times the summary looked green.

**And do not kill test hosts by process name.** `taskkill /IM testhost.exe` ends every one on the
machine, including the runs of other workers — which is what caused one of those two truncations, and
then cost a worker a paragraph in its report puzzling over a hazard that was me. If a stale process
holds a DLL (`MSB3027`), find the PID the error names and kill that one; the error message contains
it. Better still, wait: a background suite finishes on its own.

### If you mutate code to check a test bites, mutate a copy — and re-run the suite afterwards

Re-proving one of a worker's fails-before entries is the best check there is, and it is the one that
can damage the change you are verifying. Two rules, both learned by breaking `14-06` on 2026-08-26:

**Never `git checkout -- <file>` to undo your own edit.** It restores from the *index*, and a worker's
work is still unstaged at that point, so it discards the file's real changes along with your mutation.
That is what happened: `Message.cs` went back to `main`'s version while every other file kept its
`14-06` changes, so `Conversation.cs` called a constructor that no longer existed. Copy the file
aside first and restore from the copy, or stage everything before mutating so the index holds the
work rather than `main`.

**Run the full suite after the revert, not before the mutation.** The green run that mattered had
already happened; what was rebuilt afterwards was one test project, which did not compile the caller.
So the verification pass produced a broken commit and a passing report, and CI caught what the
merging session had not.

Both of these are the merger's failure mode specifically. Workers build fails-before tables in the
hundreds without disturbing their trees, because they mutate and revert one file at a time inside a
loop they wrote for it.

## 2. Check the base before the first push

```
git fetch origin
git merge-base HEAD origin/main   # must equal:
git rev-parse origin/main
```

| State | Remedy |
|---|---|
| Not yet pushed | Rebase now. Free. |
| Pushed, PR open, `CONFLICTING` | Close the PR and rebuild the branch. Never rebase a pushed branch. |

This project merges by rebase, so a stacked branch can show `CONFLICTING` with byte-identical
content — compare tree hashes before believing a conflict is real.

**Printing the check is not the same as reacting to it.** Two branches were pushed with a stale base
on 2026-08-25 *after* the check had been run and its output ignored. Read the two SHAs and compare
them.

## 3. Push and open, code before docs

Push each branch, open each PR, and say in each body which other PRs belong to the same item.

## 4. Check the whole group before merging any of it

For every PR in the group: `gh pr view <n> --json mergeable,mergeStateStatus,statusCheckRollup`.
All must be `MERGEABLE` with checks passing **before the first merge**, and then they may merge in
any order — **except that `ago-root` merges last, always**.

The reason is specific and was learned the expensive way. On 2026-08-25 two merges were issued back
to back without checking the first: the `ago-root` PR succeeded and the `ago-chat` one was refused
by a repository ruleset (`BEHIND` — and `--admin` does **not** bypass a ruleset). `main` then
claimed a cross-tenant hole was proven closed while the fix sat in a closed branch. Docs describe
code; docs that merge first describe code that may never arrive.

A merged `ago-platform` package is not a *delivered* one until the consuming repository moves its
pin in `Directory.Packages.props`. New public API also needs a `CHANGELOG.md` entry or CI
republishes the old version.

## 5. Sweep the queue at merge — it is part of merging, not a later batch

`docs/roadmap.md`'s Now queue and `docs/adr/README.md` have **one writer**: whoever merges, at the
moment they merge. Workers never touch them (`background-worker-brief`).

In the `ago-root` change that lands the item:

- Remove the item's queue row and renumber. **Anchor the match on the item column** — a loose filter
  once deleted `5-17`'s row because its reasoning cites `11-08`.
- Add the ADR index row, using the number pre-assigned in the brief.
- Record the item as done in its stage section, and fix the item file's own `Status` line.
- Run `bash tools/queue-audit.sh` and resolve anything it flags.

That last step is not ceremony. Three rows have outlived their items so far, and each was found by
accident. `16-01` merged with all five Done-when ticked, kept `Status: ready`, and sat in the Now
queue for a day as work offered to the next session to pick up and re-do.

### One open PR at a time may touch those two files

"One writer" is not enough, and 2026-08-26 proved it four times. The writer was always the same
session — me — and the conflicts came from **two of my own PRs being open at once**, each cut from a
`main` that the other was about to change. `#196`, `#202` and two branches before them were rebuilt
for no other reason.

So the rule is stronger than one writer: **while a PR that edits `docs/roadmap.md` or
`docs/adr/README.md` is open, do not open a second one.** Land the first, then cut the second from
the `main` that now contains it.

When that would stall real work — a defect worth filing immediately, a worker finishing while a
sweep is in flight — write the item file and **leave the queue row and the index row out**, then add
them in the change that lands next. Nothing goes stale in the meantime: a row goes stale when its
item *merges*, and nothing is merging while a sweep is waiting.

The failure this prevents costs a rebuild every time, and rebuilding is close-the-PR-and-recreate
once the branch is pushed — never a rebase. It is cheaper to wait.

## 6. Fix what this change made false, even outside the lane

A worker is scoped to a lane and reports out-of-lane damage rather than fixing it. That report is
the managing session's to act on, in the same change. A document this change makes false is this
change's problem regardless of who typed it.

## 7. Report honestly

State what is verified, what is merged, and what is still open — including any Done-when left unmet
and why. Never call a PR done without having read `mergeable` for it.
