# the board that `roadmap.md` calls the only queue holds nothing that is open

- **Stage**: 23
- **Status**: done (2026-09-07), `ago-root#593`. Was: **answered by the author, 2026-09-06, and with a third shape neither reading
  offered: the queue is not kept anywhere — it is computed.**
- **Depends on**: nothing
- **Decision**: none taken. Two readings, below, and the choice is the author's.

## What is actually true, counted rather than felt

`docs/roadmap.md` says it plainly, and the ordered table that used to sit in the file was **deleted
rather than duplicated** on the strength of it:

> The queue moved to the board on 2026-09-02. **Status and order live there and only there.** …The
> ordered table that used to sit here is *gone rather than duplicated*: two lists of one queue is the
> staleness problem twice over, and this one went stale three times while it was the only one there
> was.

The board holds **thirteen cards, and all thirteen are `Done`**. Not one of the twenty-three open
items is on it.

So the place declared the single source of order is empty of everything that has an order, and the
real queue is the open issues in `ago-root` — which is what `tools/queue-audit.sh` reads, and the
only reason nothing has broken.

## Why this went unnoticed for four days

**Nothing looks at the board.** `queue-audit.sh` reads issues; a person picking work reads issues;
the roadmap's own sentence is prose, and prose cannot fail. The argument that removed the table was
correct about duplication and silent about the case where the survivor is the empty one.

It is the same failure shape as `23-44` — an invariant asserted in a comment with nothing checking it
— and worth putting beside it rather than treating as an administrative slip.

## The question, which is the author's

**Reading A — fill the board, and keep the roadmap's sentence true.** Add the twenty-three open items,
set their status and order there, and keep doing it. Buys a real board: drag-and-drop ordering, a
view per stage, something to show somebody. Costs a step on every filing, forever, and it is exactly
the step that was skipped for four days by the person who wrote the rule.

**Reading B — say issues are the queue, and correct the roadmap.** One list, the one everybody
already uses and the one the audit already reads. Costs the board: order becomes label-or-milestone
shaped rather than draggable, and there is nothing to show at a glance.

**What is not acceptable is the present state**, where a document asserts an order lives somewhere it
does not, because the next person to read that sentence will believe it.

## A third thing to decide either way

**Whatever wins, `queue-audit.sh` should check it.** If the board is the queue, an open issue absent
from the board is a finding. If issues are the queue, the audit already covers it and `roadmap.md`'s
sentence has to change. A rule with no check is what produced this item.

## Done when

- [ ] The author has chosen, and the choice is recorded.
- [ ] `roadmap.md` says what is true of the queue on the day it is read.
- [ ] Whichever place holds the order, something mechanical notices when an item is missing from it.

## Out of scope

- Re-ordering the queue itself. This is about where the order lives, not what it is.

## The answer (author, 2026-09-06)

Neither reading. **"Очередь сейчас каждый раз должна просто «считаться» — её нет заранее, она
строится из issue, доступных к разработке."**

That is a better answer than either option this item offered, and it is worth saying why rather than
just recording it. Both readings assumed the queue is a *list somebody maintains* and argued about
**where** it is kept. The failure they were each trying to avoid - a second list going stale - is
avoided completely by not having a list at all.

**So there is no ordered queue to keep honest. There is a question with an answer that changes as
work lands:** which open items are ready to be started right now.

## What follows from it

- **The board stops being the queue**, and `roadmap.md`'s sentence - *status and order live there and
  only there* - is simply false and has to go. What replaces it is not a pointer to another place; it
  is a statement that the queue is derived.
- **Something has to compute it**, or the answer lives only in whoever last read the issues.
  `tools/queue-audit.sh` already reads every open issue and every backlog file - readiness is one more
  question asked of what it already has: is the item's `Status` ready, and is everything it depends on
  closed.
- **`Depends on` becomes load-bearing.** It is prose today, and a computed queue can only read it if
  it names item numbers in a form a script can find. That is the one real cost of this answer, and it
  should be paid deliberately rather than discovered.
- **The board can stay** as a place to look at what is in flight. It just stops being asserted as the
  source of order.

## Done when (replacing the ones above)

- [x] `roadmap.md` says the queue is computed from open issues, and points at what computes it.
- [x] A command answers *what is ready to start now* from the issues and the backlog files.
- [x] `Depends on` is machine-readable enough for that command to be right, and where it is not, the
      item says so. **Surveyed rather than assumed**: of 322 backlog files, 169 name items in
      backticks, 100 say *nothing*, 52 carry no such field, one is an OR — and **zero** name a
      dependency the script cannot read. The unparseable branch exists and reports rather than
      guesses, with no live example to exercise it today.
      item says so rather than the command guessing.
- [x] Nothing claims an ordered list lives anywhere.

## Outcome

`ago-root#593`, merged by the author, together with `23-50` because both changed the same script.

**The answer was neither reading, and that is what makes it worth recording.** Both options this item
offered argued about *where an ordered list lives*. The author's answer removed the premise: the queue
is computed from the open issues, every time it is asked, so the staleness both readings were trying
to avoid has nowhere to live.

**The command reports what it cannot decide.** A `Status` that says *ready* plus a qualifier, a
dependency shaped as an OR, or one naming no item number is surfaced for a person rather than folded
into an answer. The three items blocked today by a provider, a lawyer and a scheduled run fall out by
their own words - no number is hardcoded anywhere, which was the whole point.

**One weakness, found by running it rather than by reading it.** Six of the nine items it reports as
*qualified* are qualified by prose I wrote myself - `Status: ready. **Answered by the author…**` -
which is the opposite of a blocker. The script is right to refuse to guess; the cost lands on my own
habit of writing explanations into a field a machine reads. Worth knowing before trusting the buckets.