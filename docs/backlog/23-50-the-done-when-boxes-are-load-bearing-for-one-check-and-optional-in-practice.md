# the Done-when boxes are load-bearing for one check and optional in practice

- **Stage**: 23
- **Status**: done (2026-09-07). The rule is in `CLAUDE.md` rule 14, the checks are in
  `queue-audit.sh`, and the backlog the rule created is `23-55`. Was: **answered by the author,
  2026-09-06: reading A, plus a periodic review** — the
  boxes are the record, closing requires them settled, and partially-done items get looked at on
  purpose rather than by accident.
- **Depends on**: nothing
- **Decision**: none taken. Two readings below; the choice is the author's.

## What is actually true, counted on 2026-09-06

Of the 94 items closed since 2026-09-01, **21 still carry unticked Done-when boxes**. Three of them
carry five each.

Most are not unfinished work. The `Status` line says `done` with a pull request against it, and the
boxes were simply never ticked — the habit is to write the truth in `Status` and move on. Sampled by
hand: `13-08`, `23-18`, `24-02` and `15-17` all look genuinely delivered.

**But three were real**, and they were found by reading rather than by any check:

- **`22-09`** — closed as *"done except step 5"*, the author's own registrar change. Step 5 happened
  within the hour, and nothing brought the item back for its last five ticks. Verified against the
  live deployment on 2026-09-06 and closed properly.
- **`22-18`** — `Status: in review`, closed anyway, with a box reading *"not decided"*. The queue
  implied a decision existed. Carried out to `22-24`.
- **`17-11`** — `Status: in review`, closed anyway, with *"Dependabot opens NuGet PRs, proven by an
  actual run"* unticked. **Still not true two days later.** Carried out to `17-14`.

## Why this matters beyond tidiness

**`queue-audit.sh`'s staleness check reads the boxes.** It flags an item whose Done-when are *all
ticked* while its row is still open. So an item nobody ticks is invisible to it — and that is exactly
how `23-28` hid all day: its code had shipped, its documentation half was owed, and every box was
unticked, which is indistinguishable from work that never started.

So the boxes are **load-bearing for one automated check and optional in practice.** That combination
is the worst of both: the check gives a reassurance it cannot actually give, and the cost of the
convention is paid without the benefit.

## The readings

**A — the boxes are the record, and closing requires them settled.** Every box is `[x]`, or `[~]` with
a sentence, or carried out to a number. `queue-audit.sh` then means something in both directions: an
unticked box on a closed item is a finding, as is a fully ticked item still open. Costs a minute per
close, forever, and it is exactly the minute that was skipped in all three real cases above.

**B — the `Status` line is the record, and the boxes are a drafting aid.** Honest about what people
actually do. Then `queue-audit.sh`'s staleness check should be **deleted rather than left half-true**,
because a check keyed on a field nobody maintains is a false negative generator — and something else
has to notice a half-done item, because that is the failure this item exists for.

**What is not acceptable is today's state**, where one reading is written down and the other is
practised.

## A third option, and its cost

Have the check read the `Status` line *and* the boxes, and flag only where they **disagree** — a
`Status: done` with unticked boxes, or `in review` on a closed row. That catches all three real cases
above and none of the eighteen harmless ones, and needs no change to anybody's habits. Its cost is one
more rule about how `Status` is phrased, which is itself unenforced prose.

## Done when

- [x] The author has chosen, and the choice is recorded in `CLAUDE.md` or the git-workflow convention
      — wherever a person actually looks before closing an item. Reading A, in rule 14.
- [x] `queue-audit.sh` implements that choice, whatever it is, and is shown flagging a case it should
      flag and staying quiet on one it should not.
- [~] The eighteen harmless items are either tidied or explicitly left, on the record, rather than
      remaining ambiguous. **Six settled the same evening; the other twelve carried out to `23-55`,**
      because each needs reading against what its item shipped rather than a pass that ticks on the
      strength of a `Status` line — which is the reassurance this item exists to remove.

## Out of scope

- The three real cases. They are already handled: `22-09` closed, `22-18` → `22-24`, `17-11` → `17-14`.

## The answer (author, 2026-09-06)

**Reading A, with the half this item did not think of.** The author's own words: the boxes exist so
somebody can come and see *how far a ticket got and what is left* - which is exactly what they are
for, and exactly what they had stopped being.

So: **a ticket does not close while a box is unsettled.** Settled means one of three things, and the
third is the one that was missing in practice:

1. ticked;
2. `[~]` with a sentence saying what was delivered instead and why that is right;
3. **carried out to its own number** - which is rule 14's existing requirement, and which is what
   `22-18` and `17-11` both needed and neither got.

**And the review is deliberate rather than occasional.** *"Дай тикеты с частичным Done-when"* should
be a command, not a favour - otherwise it happens when somebody remembers, which is the failure mode
this whole item is about.

## What follows from it

- `queue-audit.sh` flags a **closed** issue whose Done-when are not all settled. Today it only looks
  at the opposite shape. All three real defects found on 2026-09-06 - `22-09`, `22-18`, `17-11` - are
  exactly this, and none was caught by anything.
- It gains a **partial report**: every open item with some boxes ticked and some not, so the author's
  periodic sweep is one command.
- The rule goes where a person looks **before closing** - `CLAUDE.md` rule 14 already owns closing, so
  it belongs there rather than in a convention nobody reads at that moment.
- The eighteen already-closed harmless ones are tidied or explicitly left, on the record.

## Done when (replacing the ones above)

- [x] `CLAUDE.md` rule 14 says a ticket closes only with every Done-when settled, and names the three
      ways to settle one.
- [x] `queue-audit.sh` flags a closed item with unsettled boxes, shown flagging one and staying quiet
      on a properly closed one.
- [x] `queue-audit.sh` can list partially-done open items on request.
- [~] The eighteen existing ones are settled or explicitly left, on the record. **Six settled the
      same evening** — and settling them was nearly mechanical, because their `Status` lines already
      said the box was unmet and why; the truth was written, just not where a check could find it.
      **The remaining twelve are carried out to `23-55`**, because unlike the six, nothing in their
      files says whether a box is true: each needs reading against what the item shipped. Ticking
      thirty-nine boxes on the say-so of a `Status` line would produce exactly the reassurance this
      item exists to remove.

## Outcome

`ago-root#593`, merged by the author.

**The rule and the check landed together, which is the point.** The boxes had been load-bearing for
one automated check and optional in practice - the worst of both, because the check gave a
reassurance it could not give. Rule 14 now says a ticket closes only with every box settled, and the
audit flags a closed item that breaks it: on its first run it found eighteen.

**What the first sweep taught, and it was not what I expected.** Six of the eighteen were not sloppy
at all - their `Status` lines already said which box was unmet and why, in those words. The
information existed and was honest; it simply sat where no check would look. That is a milder failure
than the one this item was filed about, and worth separating from it: the convention was not being
ignored, it was being followed in the wrong field.

**And one of the six turned out to be overtaken rather than unmet.** `20-20`'s box asked that a
tenant reach the calendar console at its own hostname - and `22-09` retired that hostname. The thing
it wanted proven no longer exists to prove, which no amount of ticking or leaving would have said.

The other twelve are `23-55`.