# two dozen worktrees hold somebody else's unfinished work

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-111` built the sweep that found them and the skill that says how to read them.
- **Found**: 2026-09-08, when a worker inherited one of them and nearly shipped what was inside.

## What is there

`tools/worktree-sweep.sh` reclaimed 152 worktrees and **kept 47**, each because it holds uncommitted
tracked changes — the one thing `after-merge-cleanup.sh` refuses to throw away. About two dozen of
those carry real diffs, several of 20 to 40 files:

```
ago-chat-23-02   41    ago-chat-23-72   38    ago-chat-23-06   29
ago-chat-24-11   28    ago-chat-24-11b  28    ago-chat-22-17   23
ago-chat-23-04   19    ago-chat-23-63   19    ago-chat-15-17   15
```

Each is a session that ended without landing its work.

## Why this is a hazard and not just clutter

**A worker sent to one of those items lands inside the abandoned work and inherits it.** That is not
hypothetical — it happened the day the sweep ran:

`ago-chat-23-72` held an earlier session's attempt at the same item, and inside it was a **tier-priced
administrator cap**: a `Domain` type mapping free and paid tiers to a maximum number of administrators,
a matching refusal code, a promotion-side check, and console copy to go with it. Its own doc comment
admitted it was *"modelled on an `ago-business` pricing document this session could not actually
read"*. `adr/0151` forbids exactly that — a permission is not an entitlement, and a public repository
must not encode packaging.

The worker that inherited it recognised the trap and removed every trace, which is the good outcome
and not the likely one. A worker that instead *extended* what it found would have shipped a
capacity rule inferred from a document nobody could open.

## What has already been done, so this item is only the remainder

`background-worker-brief`'s standing block now says: **if `new-worktree.sh` refuses because the
directory exists, stop and report — never work in a directory you did not create.** That closes the
inheritance path, which was the dangerous half. The script already refused; what was missing was an
instruction for the moment it does.

So what remains is the reading, and it is deliberately not automated.

## Scope

- **Each dirty worktree is read and resolved by a person**, using `leftover-branch-triage`'s KEEP-DIRTY
  procedure: debris is discarded, a real half-finished fix becomes a commit and an item.
- **Nothing is discarded unread.** That is the one irreversible action in the whole cleanup — an
  uncommitted change exists nowhere else — and it is why the sweep kept these rather than deciding.
- **The result is recorded**, so a second pass does not re-read the same diffs.

## Where this is likely to go wrong

- **The temptation is a filter**: "merged branch, only debris, discard". Every sweep-by-computed-property
  tried in this workspace has taken something it should not have, twice. These are the leftovers of
  exactly that reasoning being refused, so applying it now would defeat the mechanism that produced the
  list.
- **Some of these are worth landing, not deleting.** A 40-file diff on an item still open in the queue
  is somebody's real work; `23-72`'s inherited WIP was wrong on its central idea but its author had
  clearly thought about the problem.
- **Disk is not the reason.** The sweep already took 100 GB; what is left is measured in hundreds of
  megabytes. This item is about what the directories *contain*, not what they cost.

## Done when

- [ ] Every dirty worktree has been read and resolved — landed, filed, or discarded deliberately.
- [ ] Nothing was discarded without somebody looking at the diff first.
- [ ] What was found is written down, so the next sweep starts from a known state.
