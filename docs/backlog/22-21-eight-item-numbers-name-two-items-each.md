# eight item numbers name two items each

- **Stage**: 22
- **Status**: done (2026-09-04)
- **Found**: 2026-09-04, by the check added to `tools/queue-audit.sh` in the same change that files
  this — written to catch two of these, which then found six more.

## The finding

`NN-NN · Title` is the only thing tying an issue to its backlog file, to its stage, and to every ADR
and commit that names work that way (`conventions/git-workflow.md`). Eight numbers currently name two
different items each:

| Number | One item | The other |
|---|---|---|
| `5-18` | the operator console never connects to the operator hub | `#347` the demo-credential rate limit answers 500, not 429 |
| `5-19` | `14-06` grew a hub method's parameter list | `#352` four more demo endpoint refusals answer 500 |
| `8-11` | the demo pages still say there is one shared tenant | `#354` the hosts rely on a framework default to stay out of Development |
| `10-06` | the tenant never learns how to install the widget (`#314`) | `#324` nothing serves the widget script at a public URL |
| `11-17` | the console reports every post-callback failure as "Sign-in failed" (`#383`) | `#343` the console shows dates wrong |
| `15-11` | a rendered UX gate, and the screenshots (`#313`) | `#349` the console's UX gate times out on `page.goto` |
| `20-21` | an operator creates a customer and a booking | `#339` the calendar hosts have no schema guard |
| `20-22` | move a booking, as a chain | `#340` the calendar migrator does not wait for the database |

## How it happens, which is the part worth fixing

A defect is filed with "the next free number", and **free is judged from the board**. A backlog file
that has no issue is invisible there, so a planned-but-unqueued item's number reads as available. Six
of the eight are exactly that shape.

Nothing showed it. `queue-audit.sh` compared an issue to *a* file with its number and found one, so
the queue read clean; it did not compare what the two were *about*. That check exists now and is what
produced the table.

## Only two of the eight are live

`20-21` and `20-22`. Both name an unstarted planned item from `adr/0090` — an operator creating a
booking, and moving one as a chain — **and** a calendar defect that shipped on 2026-09-03 with
`feat(20-21)` and `feat(20-22)` commits in `ago-calendar`.

The other six are closed on both sides. `5-18` is the near-miss: its file is *fixed, not deployed*,
so its number is still doing work.

## The direction is forced, and only one side of it is a choice

**The side already written into merged commit messages cannot move.** Renumbering it would make a
commit say something that is not true, and commits are the one record here that is never edited.

So the unstarted planned items move. What is *not* forced is where to: appending them after `20-27`
keeps them in their stage, which is what a reader expects; anything else would need an argument.

## What must not be got wrong

- **`docs/roadmap.md` contains `Stages 10-14, 20-21` as a stage range**, not an item reference. A
  loose find-and-replace corrupts it. This is the same hazard that once deleted `5-17`'s queue row
  because its reasoning cited `11-08` — anchor on the item, never the bare number.
- **`20-23` and `20-17` both point at these items** by number, and the pointers have to move with
  them or they become references to calendar defects.
- **The six closed pairs are history and should stay readable, not be rewritten.** Whatever is done
  about them is a note, not an edit to what shipped.

## Done when

- [x] No number names two items — the audit's collision output went from seven lines to one, and the
      one that remains is `5-18`, which is **correct** rather than unresolved: see below.
- [x] Every reference to a renumbered item moves with it, including in `docs/roadmap.md`, and the
      stage range at `roadmap.md`'s `Stages 10-14, 20-21` is untouched — checked by printing that line
      after the edit, since a loose replace is exactly how it would have been corrupted.
- [x] The six already-closed pairs are dealt with explicitly — by a rule rather than a list.

## Outcome

`20-21` → `20-28` and `20-22` → `20-29`. The direction was forced: both defects had already shipped as
`feat(20-21)` and `feat(20-22)` in `ago-calendar`, and a commit message is the one record here that is
never edited. References moved in `20-23`, in each other, and in `roadmap.md`'s stage-20 narrative.

**The six closed pairs are handled by a rule, not an exception list.** `queue-audit.sh` now skips a
collision where nothing live wears the number — no open issue, and a file whose own Status says done.
A hand-kept list of accepted pairs would be a second source of truth that drifts and would need
auditing itself, which is the same reason the item-to-issue mapping is derived rather than stored.

**`5-18` still reports, and that is the right answer.** Both of its sides shipped — `fix(5-18)` in
`ago-chat` for the rate limit, `fix(5-18)` in `ago-console` for the hub connection — so neither can be
renumbered without making a merged commit untrue. Its file is *fixed, not deployed*, so something live
does still wear the number. The flag clears when the deploy closes that item, not by being silenced.

**The prevention is in `docs/backlog/README.md`.** A number is free when no *file* starts with it and
no issue's title does. Six of the eight collisions happened because "free" was judged from the board,
where a planned item with a file and no issue is invisible.
