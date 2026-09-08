# the instructions a session follows are not the ones it can reach

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `#733` already landed the first half.
- **Found**: 2026-09-08, by the author, asking why the same two mistakes keep happening.

## What was actually wrong

Three `SKILL.md` files carried no YAML frontmatter, so they were never registered and could never be
offered or invoked: `commit-guard`, `finish-an-item`, `user-story-writer`.

**`commit-guard` is the one that cost something.** It exists specifically to stop shell-quoting
failures and the forbidden `Co-Authored-By` trailer; it ships `commit.sh` and `open-pr.sh`, which take
message and body **files** rather than inline strings; and `SKILLS.md` lists it as mandatory for every
commit and every PR in every repository. It was bypassed every time for two weeks — four times on
2026-09-08 alone — because nothing could see it.

**The index said the control existed and the runtime disagreed, and nothing compared the two.** That
is the failure worth naming, and it is worse than the mistakes it let through.

`#733` fixed the three files, taught `tools/queue-audit.sh` to check for frontmatter (shown biting by
stripping `adr-writer`'s and restoring it), and replaced the worktree paragraph with
`tools/new-worktree.sh`.

## What is left, and why each of these is the same problem

**Seven skills have never been invoked, and the reason is routing rather than quality.**
`clean-architecture-guard`, `concurrency-review`, `testing-guide`, `messaging-contract`,
`db-migration`, `embeddable-widget` and `vertical-slice` all carry real procedure — ordered checklists,
not restatements of `docs/`. They are unused because the managing session does not implement (it
delegates), and `background-worker-brief` names **no implementation skill at all**: only `commit-prep`
and `land-a-slice`. The audience exists; the route does not.

**`commit-prep` and `commit-guard` describe one moment in two files.** The first says what a worker
prepares, the second is the mechanism that executes it. Splitting them is how a month was spent
reading one and not knowing the other existed.

**`local-cluster` describes Docker Desktop Kubernetes while the live stand is k3s on a VPS.** Not
stale — the local loop is real — but unlabelled, and reaching for it against the stand is a confusion
that has already cost time once.

**`context-resume` has never fired** because a compaction summary arrives with instructions to resume
directly and not narrate, and invoking a skill at that moment reads like narration. Its central claim —
*a compaction summary is a description, not verified fact* — is true always rather than at a moment,
which is the shape that belongs in `CLAUDE.md` as one line.

## The measurement that makes the CLAUDE.md half worth doing

`CLAUDE.md` is 4,380 words. Rules 1–8 and 11 — the architectural ones, the subject of the project —
total about **238 words, 5% of the file**. Rules 9, 10, 12, 13, 14 and 15 — git, tickets, workers —
total about **2,890 words, 66%**.

A project whose stated purpose is demonstrating Clean Architecture spends 5% of its central document
on it.

**And the process rules do not work in proportion to their length.** Rule 13 spends 571 words on
worktrees and did not stop the worktree mistakes; a script that refuses did. That is the argument for
moving them, and it is an argument about *where a rule lives*, not about whether it is right.

## The principle, which is the part to disagree with if any

> **What is true always and costs one line stays in `CLAUDE.md`. What applies at a specific moment
> moves into the skill that opens at that moment.**

So `10` joins `docs/conventions/git-workflow.md`, which already exists and is already cited; `12` and
`13` join `background-worker-brief`, which opens at dispatch; `14` and `15` join `finish-an-item`,
which opens after a merge; most of `9` joins `commit-guard` and `land-a-slice`.

**Four things stay in `CLAUDE.md` word for word**, because they apply at no particular moment and
therefore have no skill to live in: never push to `main`; never rewrite pushed history; everything is
public; no `Co-Authored-By` trailer.

## Where this is likely to go wrong

- **`CLAUDE.md` loads every session; a skill loads on demand.** A moved rule is only in context when
  its skill fires. That is the whole risk, it is why the four above do not move, and it is the reason
  to check afterwards whether a moved rule started being broken.
- **Moving is not summarising.** Each rule's reasoning — the dated post-mortem that makes it stick —
  travels with it. A rule stripped of why it exists gets argued with again within the month.
- **Nothing is deleted in this item.** If a rule turns out to belong nowhere, that is a separate
  decision and a separate number.

## Done when

- [ ] Every skill that carries procedure is reachable from something that fires — a brief, a script,
      or a line in `CLAUDE.md`.
- [ ] `CLAUDE.md`'s architectural rules are no longer a rounding error in their own file.
- [ ] Nothing that moved lost the reasoning that makes it stick, and the four always-true rules did
      not move at all.
