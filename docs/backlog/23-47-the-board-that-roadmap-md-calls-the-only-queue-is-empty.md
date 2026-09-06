# the board that `roadmap.md` calls the only queue holds nothing that is open

- **Stage**: 23
- **Status**: ready — **and it is a question before it is work**
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
