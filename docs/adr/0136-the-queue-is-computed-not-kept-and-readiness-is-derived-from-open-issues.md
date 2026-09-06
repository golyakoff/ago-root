# ADR-0136: The queue is computed, not kept, and "ready to start" is derived from open issues and backlog files on every ask

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 23 (`23-47`, `23-50`)

## Context

`docs/roadmap.md` asserted, since 2026-09-02, that a GitHub Project board was the single source of
queue order: "Status and order live there and only there." The ordered table that used to sit in
`roadmap.md` was deleted on the strength of that sentence, on the correct argument that two lists of
one queue is the staleness problem twice over.

`23-47` counted what was actually true on 2026-09-06: the board held thirteen cards, all thirteen
`Done`. Not one of the twenty-three then-open items was on it. The sentence had been false for four
days, and nothing noticed, because nothing read the board - not `tools/queue-audit.sh`, not a person
picking work, and prose cannot fail on its own. The real queue, the whole time, was the open issues in
`ago-root`, which is what the audit already read.

`23-47`'s two offered readings - fill the board and keep the sentence true, or drop the board and let
issues be the one list - both assumed a queue is *a list somebody maintains* and argued only about
**where** it lives. The author's answer rejected the premise: *"Очередь сейчас каждый раз должна
просто «считаться» — её нет заранее, она строится из issue, доступных к разработке."* There is no
ordered list to keep honest anywhere - board, table, or otherwise. There is a question with an answer
that changes as work lands: which open items are ready to start right now.

Separately, `23-50` counted the backlog's Done-when boxes across everything closed since 2026-09-01:
94 items, 21 with at least one unticked box. Eighteen were harmless - `Status: done`, box just never
ticked. Three were real defects found only by reading, not by any check: `22-09` (closed "done except
step 5", the last five ticks never chased down), `22-18` (closed with a box reading "not decided"),
`17-11` (closed with "proven by an actual run" still unticked, and still not true two days later).
`queue-audit.sh`'s existing STALE? check only asked the opposite question - does an *open* issue's
file look finished - so none of the three were ever in its reach.

Both findings share a shape: a rule asserted with nothing mechanical checking it. `queue-audit.sh`
already read every open issue, every closed issue, and every backlog file to answer other questions;
both items' own "what follows" sections said the fix was to ask it one more question each, from data
it already has, rather than to build a second thing that has to be kept in sync with the first.

## Decision

**There is no queue to store, in `roadmap.md`, on the board, or anywhere else.** "Ready to start now"
is answered fresh on every ask by `tools/queue-audit.sh --ready`: an open `ago-root` issue is READY
when its backlog file's `Status` line says plainly `ready` (nothing appended) and every item named in
its `Depends on` field is no longer an open issue. Nothing is written down between runs; the same
eventual answer a person would get by reading every open issue and its file by hand.

**The board stops being asserted as an authority.** It may still be used as a place to glance at what
is in flight, but no document may claim it holds order or status that nothing else derives.

**`Depends on` must name item numbers a script can find**, in backticks (`` `NN-NN` `` or
`` `NN-NN-rest-of-filename.md` ``), for `--ready` to read it as a real dependency. Three shapes are
distinguished rather than collapsed into a guess: `nothing` (no dependency), no field at all (the
`Found`-defect convention, treated as no dependency because every sampled instance of it was), and
everything else that isn't a plain backticked item-number list - an ADR-only citation, an "at least
one of" disjunction, a provider or a person - which is reported as **UNKNOWN**, never silently folded
into ready or not-ready.

**A `Status` value is only plainly `ready` when it says exactly that.** Any qualifier after the word -
`ready — blocked on the deploy`, `ready. **Answered by the author...**` - puts the item in a separate
**QUALIFIED** bucket, printed with its own text, rather than guessed either way. This is how an item
blocked on something that is not another open item (a scheduled run, a provider, a deploy) is kept out
of READY without this script knowing what a deploy or a provider is.

**A closed issue can now fail an automated check for the shape `23-50` found: unsettled Done-when.**
`queue-audit.sh` (no flag needed - it runs with the rest of the full audit) flags a closed issue whose
backlog file still has an unticked `- [ ]` box. Settled means `[x]`, `[~]` with its own sentence, or
carried out to its own number (which itself ends as `[x]` or `[~]` on the box, so nothing extra is
needed to recognise it) - `CLAUDE.md` rule 14 states the three ways; this check is what makes the
first of them, "not while a box is unsettled," mechanical rather than a habit.

**A partial-Done-when report is a flag, not a new tool**: `tools/queue-audit.sh --partial` lists open
items with some boxes ticked and some not, so the author's periodic *"дай тикеты с частичным
Done-when"* sweep is one command.

## Consequences

**Positive:**
- One document can no longer assert an order that a check does not read. `roadmap.md`'s "Now" section
  is rewritten to say the queue is computed and name what computes it, closing the exact failure mode
  `23-47` found.
- Readiness costs nothing to keep in sync, because nothing is kept - it is derived from data
  `queue-audit.sh` already fetches for its other checks (`--ready` and `--partial` each cost one
  `gh issue list` call against `ago-root`, not the nine-repository sweep the full audit makes).
- The three items already known to be blocked on something other than another item (`15-19`, `17-14`,
  `24-07`) are not special-cased by number anywhere in the script - `17-14`'s Status is not plainly
  `ready` so it never enters the computation, `24-07`'s real dependency on the still-open `25-01`
  falls out of the ordinary parseable path, and `15-19`'s qualified Status lands it in QUALIFIED. No
  item number is hardcoded, which is the same enumerate-don't-keep-a-list discipline `secrets-audit.sh`
  and `23-49` already established for this codebase.
- The closed-Done-when check closes a real gap: run against the live queue on 2026-09-06 it found 18
  closed items with an unticked box, the same shape as the three real defects `23-50` found by hand,
  none of which any existing check could see.

**Negative:**
- `--ready`'s answer is only as good as `Status` and `Depends on` being kept in the form it can read.
  A dependency written as prose with no backticked item number is invisible to it and lands in
  UNKNOWN rather than being silently treated as absent - correct, but it means the survey's finding
  (most `Depends on` fields already cite items in backticks; a `Found`-defect item usually has no
  field at all and that is normal, not a gap) has to keep holding, or UNKNOWN grows and the command's
  answer thins out.
- The QUALIFIED bucket is deliberately coarse: any `Status: ready` with so much as a trailing period
  and more text lands there, including items that are, in fact, unblocked and merely carry an
  administrative note (`23-47`'s and `23-50`'s own files, `23-35`, `22-24`, at the time this was
  written). That is the honest cost of "say so rather than guess" - a human reads nine qualifiers
  instead of the script silently getting some of them right and one of them wrong.
- The board (`https://github.com/users/golyakoff/projects/1`) still exists and nothing prevents it
  drifting again the way it did before - the fix here is that no document may *claim* it is
  authoritative, not that the board is kept current. If it is wanted as a current view again, that is
  new work, not a consequence of this decision.

## Alternatives considered

- **Fill the board and keep `roadmap.md`'s sentence true** (`23-47` reading A). Rejected by the
  author: buys drag-and-drop ordering and a view per stage, at the cost of a step on every filing,
  forever - the exact step that was already skipped for four days by the person who wrote the rule
  requiring it.
- **Keep issues as the queue but say so plainly, with no computed readiness** (`23-47` reading B
  without its own "third thing to decide either way"). Rejected: it fixes the false sentence but
  leaves the actual question - what can I start right now - answered only by whoever last read every
  open issue and file by hand, which is the condition that let the board drift unnoticed in the first
  place.
- **A hand-maintained `Depends on` → readiness index, updated alongside the issues.** Rejected for the
  same reason `queue-audit.sh`'s item-to-mirror mapping is derived rather than stored: a second index
  is a second thing to keep in sync, and staleness in *that* index is exactly the failure both `23-47`
  and `23-50` are about.
- **Key the closed-Done-when check on the `Status` line instead of the boxes** (`23-50`'s reading B).
  Rejected by the author in favour of reading A: the boxes are what let somebody see *how far a ticket
  got and what is left*, which prose in `Status` does not give the same way, and keying on `Status`
  alone would have missed `22-18` and `17-11`, whose `Status` lines already read `in review` while the
  issues were closed anyway - the boxes were the only place carrying the truth.
- **Flag only where `Status` and the boxes disagree** (`23-50`'s third option). Would have caught the
  three real 2026-09-06 cases and none of the eighteen harmless ones, at the cost of a second,
  unenforced rule about how `Status` must be phrased. Not chosen; the author's answer went with
  reading A's plainer rule instead - every box settled, however it is phrased - rather than adding a
  phrasing convention that would itself need auditing.
