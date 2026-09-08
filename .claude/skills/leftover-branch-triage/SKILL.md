---
name: leftover-branch-triage
description: Decide what a branch or worktree that survived cleanup actually is - work that reached main by another route, or work that was genuinely lost - and act on each. Use after tools/worktree-sweep.sh or tools/prune-merged-remote-branches.sh reports anything it kept.
---

# What survived the cleanup, and which kind is it?

`tools/worktree-sweep.sh` and `tools/prune-merged-remote-branches.sh` remove only what is provably
merged **by content**, and keep everything else. What they keep is not a residue to be swept later -
it is a shortlist of the only branches in the workspace that might contain work nobody has.

**Their verdict is deliberately conservative and deliberately wrong in one direction.** `git cherry`
answers "is this exact patch in `origin/main`". A branch whose *outcome* reached `main` by a different
route - reworked into a different commit, folded into another file, renamed, or superseded by a
decision - answers "not merged" and is kept. That is the right default, and it means **most of what
survives is not lost work.** Telling the two apart is this skill.

## The three verdicts, and what each one is

| Reported as | What it means | What it usually is |
|---|---|---|
| `KEEP-UNMERGED` | commits not in `origin/main` by content | usually landed by another route; occasionally real |
| `KEEP-DIRTY` | uncommitted tracked changes | usually a debugging edit; occasionally an unfinished fix |
| `UNKNOWN` | the cleanup refused for another reason | almost always a detached HEAD - look by hand |

## The triage, in the order that answers fastest

Run these against the **branch**, not the worktree. Stop at the first one that settles it.

**1. What does the branch actually contain?**

```bash
cd C:/git/ago/<repo>
git log --oneline origin/main..origin/<branch>
```

One commit with a clear subject usually names its own item. Read the subject before anything else -
it frequently says what happened (*"0126 folds into 0123 at the author's call"* settled one of these
outright).

**2. What is its item's state?**

```bash
cd C:/git/ago/ago-root
gh issue list --state all --search "<item> in:title" --limit 1 --json number,state,title
```

A **closed** issue is strong evidence the work landed somehow - the item was closed by a person who
believed it was done. It is not proof: `finish-an-item` exists because closings have missed halves.
An **open** issue, or no issue at all, means step 3 matters much more.

**3. Is the outcome in `main`, however it got there?**

This is the actual question, and it is asked about the *effect*, not the patch:

```bash
git ls-tree -r --name-only origin/main | grep -i <the file the branch adds>
git grep -l "<a distinctive phrase or symbol the branch introduces>" origin/main -- <path>
```

- **Present** → the work reached `main` by another route. The branch is a duplicate. Delete it.
- **Absent** → step 4.

**4. Absent - so is it lost, or was it deliberately abandoned?**

Read the item file in `docs/backlog/`. An item closed as **not planned**, or one whose Done-when boxes
were settled with `[~]` saying something else was delivered, means the branch was abandoned on
purpose. Anything else means **work exists that nobody has**, and that is a finding: file it, or open a
PR from the branch. Do not delete it to tidy up.

## Worked examples, all real, from 2026-09-08

Seven remote branches survived a prune that deleted 92. Six were not lost work:

- **`docs/23-12-calendar-reads-the-rung`** - two commits about `adr/0126`. `main` has **no** `0126`
  and **does** have `0123`, and the branch's own last commit says 0126 was folded into 0123 at the
  author's call. `main` is *ahead* of the branch's intent. Duplicate.
- **`docs/22-24-status-says-what-is-waiting`** - its phrase is in `docs/design/ui-inventory.md` on
  `main`. Landed by another route. Duplicate.
- **`feat/24-15-what-the-widget-stores`** - `DeviceStorageDisclosurePage.tsx` is in `main`. The branch
  additionally carries *"resolve conflict markers left by a failed stash pop"*, which is the shape of a
  branch that was rebuilt elsewhere. Duplicate.
- **`feat/24-03-the-tenant-is-bound-at-registration`** (in two repositories) - issue closed, and the
  registration binding is in `main`'s `SitesEndpoints.cs`. Duplicate.
- **`chore/pin-todays-images`** - a deploy pin from an earlier day, superseded by a later pin.
  Duplicate by definition; image pins are only ever the latest one.

One was live work: **`docs/23-103-revoked-shown-as-expired`**, whose item had no closed issue because
the console half was still in flight.

**The lesson those six carry: a `KEEP` verdict is a question, not an accusation.** Treating the kept
set as "abandoned junk" and deleting it wholesale would have been right six times out of seven, and
the seventh is exactly the case the whole mechanism exists for.

## Deleting one, once triaged

```bash
cd C:/git/ago/<repo>
git push origin --delete <branch>                      # the remote branch
cd C:/git/ago/ago-root
bash tools/after-merge-cleanup.sh <repo> <item> --yes   # will still refuse if it disagrees
```

The cleanup script keeps its own refusals even here. If it disagrees with your triage, it is worth
finding out why before overriding it by hand.

## `KEEP-DIRTY` is a different question

Uncommitted tracked changes are usually a debugging edit somebody left - a `Console.WriteLine`, a
skipped test, a hardcoded value. Read the diff:

```bash
git -C C:/git/ago/<repo>-<item> diff
```

If it is debris, discard it and re-run the cleanup. If it is a real half-finished fix, it belongs in a
commit and an item, not in a directory. **Never discard without reading** - that is the one
irreversible action in this whole procedure, since nothing about an uncommitted change exists anywhere
else.
