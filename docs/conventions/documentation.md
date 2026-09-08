# Where each kind of knowledge lives

This is the current-state document for the project's own documentation — what goes where, and which
file a reader should trust when two disagree. The decision behind it is [`adr/0156`](../adr/0156-a-current-state-document-is-authoritative-and-an-adr-says-why.md).

## The split, and the one rule that follows from it

| Question | File | Authoritative for |
|---|---|---|
| **How does this work now?** | `docs/architecture/<topic>.md`, `docs/conventions/<topic>.md` | **Yes** — this is what a reader trusts |
| **Why was it decided that way, and what did it replace?** | `docs/adr/NNNN-*.md` | **Yes**, for the reasoning and the history |
| How do I run or operate it? | `docs/runbooks/<task>.md` | Yes, for procedure |
| What are we building next, and why in that order? | `docs/roadmap.md`, `docs/backlog/` | Yes, for intent |
| How does a session do a recurring kind of work? | `.claude/skills/<name>/SKILL.md` | Yes, for procedure and judgement |

**An ADR is not where you look up current behaviour.** It records a decision at a point in time, and
it stays exactly as written. Reconstructing "what holds now" by reading a chain of them is both slow —
129 files, 178,000 words, about 237,000 tokens — and unreliable, because missing one amendment
produces a confidently wrong answer rather than an obviously incomplete one.

**When a current-state document and an ADR disagree, the document is wrong and gets fixed** — an ADR
is never edited to match. If the document is right and the decision genuinely changed, the change
needed a new ADR and did not get one; write it.

## Why there are ADRs at all

**Every decision a reviewer could reasonably argue with gets a numbered file in `docs/adr/`, written
from `_template.md`, and code contradicting an accepted ADR without a superseding one is treated as a
defect.** That is [`adr/0001`](../adr/0001-record-architecture-decisions.md), and it is the oldest
decision in the project.

Its reason is worth restating here because it shapes everything on this page: **code shows what was
built and never what was rejected**, and *"why not X"* is the first question a senior reviewer asks.
The second reason is this project's own working conditions — the decisions have to survive being
implemented across many separate sessions that share no memory, and a rationale that lives only in
somebody's head does not.

`adr/0001` also rejected the two obvious alternatives, and both rejections are still load-bearing:
**comments in code** are invisible at design level and rot beside what they justify, and **one big
design document** becomes a wall of text where superseded reasoning is quietly edited out. That second
one is precisely the failure `adr/0156` found happening anyway, in a different form — amendments
appended inside accepted ADRs — which is why the immutability rule below is now checked rather than
stated.

## The three rules that keep this true

1. **An accepted ADR is immutable.** The only edit it may receive is its `Status` line gaining a
   supersession or amendment pointer. **Never append an amendment to the body.** That practice is what
   made the corpus unreadable: once a body can change, a file may look current and carry its own
   reversal several screens down, and no index built over it can be trusted.

2. **Every ADR is referenced from at least one current-state document**, in the change that accepts
   it. `tools/queue-audit.sh` names any that is not.

3. **A change that makes a document wrong fixes it in the same change.** Long a working agreement;
   under this split it is load-bearing, because the document is now what a reader trusts.

## Why rule 2 is a check and not a convention

This split trades a slow, complete source for a fast, curated one. That trade is only good while the
curated source is complete.

**A current-state document that silently omits a decision gives a confident wrong answer** — worse
than the reconstruction it replaced, because nothing signals the gap. Before the split, an incomplete
document was merely incomplete and a reader fell back to the ADRs; after it, an omission is
indistinguishable from a decision that was never made.

So completeness is checked mechanically rather than asked for. **Thirty-five ADRs had no home when
this was written** — `0001` and `0002` among them — and the check reports every one until it does;
closing that backlog is `23-113`.

## Skills, and why they are not a fourth category

A skill carries **procedure and judgement** for a recurring kind of work — how to land a slice, how to
brief a worker, how to commit. It cites facts and never restates them, because two copies of a rule
become two different rules within a month.

`CLAUDE.md` carries only what is true **always** and costs one line. What applies at a specific moment
lives in the skill that opens at that moment (`23-111`). That is the same principle as this page: put
each piece of knowledge where the person who needs it will already be looking.
