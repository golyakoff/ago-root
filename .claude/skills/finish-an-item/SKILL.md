---
name: finish-an-item
description: The six checks that run at the moment an item's last code PR merges - close every mirror, settle every Done-when box, sweep the queue, remove the worktrees. Use immediately after merging, because merging the code feels like finishing and is not.
---

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
3-4. **Reclaim the branch and the worktree - one command per repository the item touched.**

   ```bash
   bash C:/git/ago/ago-root/tools/after-merge-cleanup.sh <repo> <item>          # reports, changes nothing
   bash C:/git/ago/ago-root/tools/after-merge-cleanup.sh <repo> <item> --yes    # does it
   ```

   It deletes the remote branch, removes the worktree, and deletes the local branch - and it refuses
   if anything tracked is uncommitted, or if any commit on the branch is missing from `origin/main`
   *by content*. Content, not ancestry: this project always uses Rebase and merge, so a merged
   branch is never an ancestor of `main` and `git merge-base` would call finished work unmerged.
   `git cherry` compares patches instead and survives the rewrite. Both refusals were proved by
   constructing them.

   **It takes the item's own name and removes only that directory.** It never enumerates worktrees
   and decides which look finished, and it never runs `git worktree prune`. "Merged and clean" as a
   filter has twice taken something it should not have here: the agent runtime's own isolation
   worktrees under `.claude/worktrees/`, which left a running worker unresumable, and another
   session's working directory, whose branch had merged and whose tree was clean.

   **Why these two steps got a script when the rule already existed.** They were written as
   instructions and read as suggestions. On 2026-09-08 the workspace held **158 GB**, of which
   **147 GB was `bin/` and `obj/`** inside worktrees whose work had merged weeks earlier;
   `node_modules` was 12 GB, and every `.git` in the workspace together was **66 MB**. So none of it
   was git garbage and none of it was repository size - it was build output in directories nobody
   closed, and the instruction to close them had been sitting right here the whole time.
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

---

# Moved here from `CLAUDE.md` on 2026-09-08

`CLAUDE.md` loads in full at the start of every session; a skill loads when it is invoked. The rules
below apply **at a specific moment** rather than always, and that moment is when this file opens - so
keeping them in the always-loaded file bought nothing and cost 66%% of it. The measurement is in
`docs/backlog/23-111-*.md`.

**Their reasoning travelled with them, unedited.** A rule stripped of the post-mortem that produced
it gets argued with again within the month, so the dated parentheticals are part of the rule and are
not summaries of it. `CLAUDE.md` keeps each rule's number and its always-true core, and points here.

These two open at the moment an item is being closed or sliced, which is the moment they govern.

## A ticket ends in an explicit state, and unfinished work always gets a number of its own (`CLAUDE.md` rule 14)

**A ticket ends in an explicit state, and unfinished work always gets a number of its own.**
- **Solved → close as done** (`gh issue close <n> --reason completed`). **Cancelled → close as
  won't-do** (`gh issue close <n> --reason "not planned"`). Passing no `--reason` silently means
  `completed`, so a cancelled ticket closed without the flag is recorded as *delivered* — the
  worst of the outcomes, because the queue then claims work exists that never happened.
- **Never leave a ticket half-done.** Either finish it, or rewrite it to what actually shipped
  and carry the remainder out. A ticket rewritten to its delivered scope is closed as done — it
  is not "partly failed", it is a smaller item that succeeded.
- **A ticket does not close while a Done-when box is unsettled.** Settled means one of three
  things: ticked; `[~]` with a sentence saying what was delivered instead and why that is right;
  or carried out to its own number, per the clause below. `tools/queue-audit.sh` flags a closed
  issue with an unticked box left behind, and `--partial` lists open items with a partial
  Done-when on request — added 2026-09-06 (`23-50`), after three items closed with exactly that
  shape and nothing noticed: `22-09` (closed *done except step 5*, and the last five ticks were
  never come back for once step 5 happened an hour later), `22-18` (closed with a box reading
  *not decided*, which left the queue implying a decision existed), and `17-11` (closed with
  *proven by an actual run* unticked, and still not true two days later).
  **The boxes were load-bearing for one automated check and optional in practice**, which is the
  worst of both: the check gave a reassurance it could not give, and the cost of the convention
  was paid without the benefit. That is how `23-28` sat half-done for a day, invisible.
- **Carrying a remainder out means a *new number*, not a link.** When work is split off, it gets
  a new item plus issue in `ago-root`. Leaving it under the finished item's number is the failure
  this clause exists for: by the `NN-NN ·` title convention that prefix asserts "this *is* item
  NN-NN", so unfinished work ends up claiming the identity of a finished one.
- **One queue, and it is `ago-root`.** An item is filed once — the file in `docs/backlog/` and one
  issue in `ago-root`. Mirrors in code repositories are not the convention: the count says so
  plainly (86 issues in `ago-root` against 16 across all eight code repositories at 2026-09-05),
  and both items that genuinely had a mirror ended the same way — `ago-root` closed, the mirror
  left open, the queue claiming work that had shipped. `11-15`/`ago-calendar-console#27` is what
  prompted the closing rule above; `22-14`/`ago-calendar#32` repeated it three days later and was
  found only because `queue-audit.sh` reads mirrors.
  This clause used to require a code-repository ticket as well. It was duplication that nobody
  maintained, and the maintenance cost fell entirely on closing.
  `queue-audit.sh` still reads every repository, deliberately: a mirror that exists must still be
  closed, and the check costs nothing when there are none. (Decided 2026-09-05.)
- **The managing session files a found defect itself, without asking** (added 2026-09-05).
  Implementing one item routinely turns up another: a stale comment, a missing guard, a document
  that stopped being true, a remainder split off under the clause above. Those get a number the
  moment they are found — the file, and one issue in `ago-root`.
  **The boundary is the same one rule 9 draws for merging: no judgement the author has not seen.**
  So a found defect is filed freely; anything that would *decide* something is not. If the honest
  item needs a new port, a new store, a changed decision, or a product or commercial choice, it is
  still filed — but **filed as the question**, with the options and what each costs, the way
  `24-04` states three readings and picks none. An item that quietly answers an architectural or
  business question by being written is the failure this clause guards against, not the one it
  permits.
  Why this is safe where merging needed conditions: filing costs a number and a paragraph, and a
  wrong one is closed as not-planned. The expensive failure is the opposite — a defect noticed
  during an item, mentioned in a report, and never given a number, which is exactly how three
  stale rows outlived their items here before `queue-audit.sh` existed.
- **Closing means closing every mirror.** Items are filed twice — in `ago-root` and in the
  repository they change — and closing one is not closing the item. This is part of merging, at
  the same moment as the roadmap and ADR-index sweep, not a later batch.
(Decided 2026-09-02, from two misses in one day. First: `11-15` shipped, `ago-root#322` was
closed, its twin `ago-calendar-console#27` stayed open, and `queue-audit.sh` — which then read
`ago-root` only — reported a clean queue; it was found because the author asked. Second, found by
the mirror-aware audit on its first run: `ago-calendar-console#26` was still titled `15-11 ·`
after being split out of `15-11`. The tempting fixes were both wrong — closing it would close
undone work, and reopening `15-11` would have re-widened an item that had been *correctly*
narrowed to what it delivered. What was missing was a number, which became `15-12`.)


## One ticket, one thing (`CLAUDE.md` rule 15)

**One ticket, one thing. An "and" in a ticket is almost always a seam to cut along.**
- **Treat the conjunction as the signal.** A title or scope joined by "and", or a scope that reads
  as a list, is the common shape of two tickets wearing one number. Split first and ask whether
  that was unnecessary afterwards — the reverse is much more expensive.
- **The test is one promise that lands green — not whether the code is separable.** A ticket is
  one thing when it makes a single promise that is true or false as a whole, *and* closing it
  leaves the system passing its quality gates. Two things belong apart when they make **different
  promises**, not merely when they touch different files.
  - **A split that produces "the first breaks it, the second fixes it" is a bad split.** Every
    ticket must be able to close with the build, the suites and the gates green. If closing A
    leaves a gate red until B lands, then A and B are one ticket — that is the sharp, checkable
    form of this rule, and it catches over-splitting and dependent-splitting alike.
  - **Over-splitting is a real failure, not a safe direction to err in.** Two changes that are
    the *same* promise in different places — one symptom, one verification, one thing a reader
    would call finished — are one ticket even when the code is trivially separable.
  - Code-level independence ("different files", "neither calls the other") is about
    implementation coupling and answers a different question. It is not the test.
  - **The gate check is a veto, not a permission.** A split that fails it is wrong; a split that
    passes it is not thereby right. Where no gate would go red either way, the promise still
    decides — `#342` (rename the widget bundle to `widget.js`; its lazily-loaded chunk is named
    by a literal, so renaming one without the other reddens nothing) is one ticket because the
    promise is one: the widget's public files are named for what a person recognises.
- **Why it costs**: a ticket with two halves cannot be closed honestly when one is done, so it
  either sits open with delivered work invisible inside it, or gets closed with the other half
  buried. Both are how work goes missing. It also forces one review to carry two arguments, and
  the author's review capacity is this project's actual bottleneck. Rule 14's third clause exists
  to clean up after exactly this; splitting up front is cheaper than splitting at close.
- **When a ticket is already in flight and turns out to be two**, split it anyway: rewrite it to
  one half, file the other, and keep the two changes separable so each closes its own ticket.
(Decided 2026-09-03, from `#339` — filed as "the calendar hosts have no schema guard **and** the
migrator no database wait". Two mechanisms, two layers, two proofs, nothing shared but the
repository and the reason they were both noticed at once: two promises, each landing green.
Amended the same day by the opposite mistake. `#343`/`#344` — a hardcoded `en-GB` in
`time/format.ts`, and one screen bypassing that file with a bare `toLocaleString()` — were split
on the code-level test and should not have been. They are one promise, "the console shows dates
correctly", and it shows: `#343` alone leaves `11-16`'s gate **red** on `admin-conversations`,
so it cannot close green. That is what replaced "can they be finished separately" with "does each
land green" as the test.)

