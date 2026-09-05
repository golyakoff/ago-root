# Finishing an item

`land-a-slice` gets a change verified and its PRs open. This is the part after that, and it is the
part that gets dropped — because **merging the code feels like finishing, and it is not.**

Run this once per item, at the moment the last code PR merges. It is six checks and takes a minute.

## Why this skill exists rather than a line in a longer document

On 2026-09-05 five items were found whose work had been written and left behind: `23-17`'s console
half twice over, `23-20`'s implementation in three worktrees, and the documentation halves of `23-06`,
`23-22` and `24-11` — two of which carried an ADR whose code was already merged. The gaps in
`docs/adr/README.md`'s numbering were the visible symptom, and they had been misread that morning as
numbers held by *unfinished* work. They were held by finished work whose record never arrived.

`queue-audit.sh` gained a worktree check the same afternoon. **It caught its own author within the
hour** — `23-27`'s documentation half, thirty minutes after the check was written.

And then the same session did it twice more, on `23-05` and `23-19`, in a way that check could not
see: the work was not sitting in a worktree, it had never been written at all. Both times the pattern
was identical — the code merged, and the session moved to the next item in the same breath.

That is the failure this list exists for. Not carelessness; a wrong idea of where the work ends.

## The list

Run it when the **last** PR for an item merges — code and documentation both.

1. **Merge the documentation half.** If there is no documentation change, say so explicitly rather
   than assuming: an item that changed behaviour and needs no document is a real answer, but it has to
   be an answer rather than an omission. `docs/roadmap.md` and `docs/adr/README.md` have one writer -
   whoever merges, at the moment they merge (`land-a-slice` §5).
2. **Close the issue, with a reason.** `gh issue close <n> --reason completed` for solved,
   `--reason "not planned"` for cancelled. **Passing no reason silently means completed**, so a
   cancelled item closed without the flag is recorded as delivered - the worst outcome, because the
   queue then claims work that never happened (`CLAUDE.md` rule 14). Close every mirror.
3. **Delete the remote branch.** `gh pr merge --delete-branch` does it; when it fails because a
   worktree still holds the branch, the branch is still there and needs `git push origin --delete`.
4. **Remove the worktrees this item created, by name.** Never sweep by a computed property - "merged
   and clean" once took the agent runtime's own isolation worktrees and, separately, another session's
   working directory. Name the paths the brief named, and nothing else.
5. **Run `bash tools/queue-audit.sh`** and resolve what it flags. In the same breath as the close, not
   as a later batch - three rows have outlived their items so far and each was found by accident.
6. **Say what merged**, in the session, at the time. The author reads after the fact instead of
   before, so that has to be possible.

## The two checks that make this mechanical

`tools/queue-audit.sh` holds both, so neither depends on anyone remembering:

- **Uncommitted work in a worktree, for an item that is still open.** Work existing only as unstaged
  files is invisible to `git log --grep`, to CI and to the board, and the item's row correctly stays
  open the whole time - *open* and *nobody has started* look identical.
- **Merged code under an open item.** The complement, and the one that catches this skill's own
  failure: when the code is in `main` and the issue is still open, the item is either mid-landing or
  it was dropped, and only a human can tell which. It reports rather than fails.

## When this is finished

When the item's issue is closed with a reason, its documentation is on `main`, its branches and
worktrees are gone, and the audit is clean. Not when the code merged.
