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

## 6. Fix what this change made false, even outside the lane

A worker is scoped to a lane and reports out-of-lane damage rather than fixing it. That report is
the managing session's to act on, in the same change. A document this change makes false is this
change's problem regardless of who typed it.

## 7. Report honestly

State what is verified, what is merged, and what is still open — including any Done-when left unmet
and why. Never call a PR done without having read `mergeable` for it.
