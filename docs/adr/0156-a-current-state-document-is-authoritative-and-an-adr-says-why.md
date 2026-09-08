# ADR-0156: A current-state document is authoritative for what holds; an ADR is authoritative for why

- **Status**: Accepted
- **Date**: 2026-09-08
- **Stage**: 23

## Context

There are **129 ADRs**, together **178,000 words** — roughly **237,000 tokens** to read in full.

Two questions get asked of them, and they are not asked equally often. *"How is this done now?"* is
asked in nearly every session, before nearly every change. *"How did we arrive at this?"* is asked
rarely, and usually only when somebody wants to reopen a decision.

**Today both are answered the same way: by reading the chain and reconstructing what survives.** That
is the expensive path spent on the cheap question, and it is not merely slow — it is unreliable, in a
way that is invisible when it fails. Miss one amendment and the reconstruction is confidently wrong,
and a wrong answer here produces another layer of decision on top of a misread one, which is more
expensive to unpick than the reading was to do.

Three properties of the corpus as it actually stands make that failure likely rather than theoretical:

- **The supersession graph barely exists as data.** Exactly **one** ADR carries a machine-readable
  link (`0015` → `0018`). Twenty-five files discuss superseding and twenty-seven discuss amending, all
  in prose. The index carries a note on **14 of 132** rows.
- **Amendments are appended inside accepted ADRs**, which contradicts `docs/adr/README.md`'s own
  stated rule that a decision that changes gets a *new* ADR. One ADR records being "amended three
  times… all three amendments are appended below."
- **Therefore an ADR's number and status guarantee nothing.** A file can look current and contain its
  own reversal several screens down. Any index built over the corpus inherits that.

Meanwhile `docs/architecture/*` and `docs/conventions/*` already exist, already describe current
state, are already where `CLAUDE.md`'s *Where to look* table sends a reader, and already reference
**94 of the 129** ADRs.

## Decision

**A current-state document — `docs/architecture/*` or `docs/conventions/*` — is authoritative for what
holds now. An ADR is authoritative for why it was decided, and is not the place to look up how the
system currently behaves.**

Three things follow, and all three are required together:

1. **An ADR is immutable once accepted, and this time it is enforced.** A decision that changes gets a
   **new** ADR. The only edit permitted to an accepted ADR is its `Status` line gaining a supersession
   or amendment pointer. Appending an amendment to the body is what made the corpus unreadable and it
   stops.
2. **Every ADR is referenced from at least one current-state document**, in the change that accepts
   it. `tools/queue-audit.sh` checks this and names any ADR with no home.
3. **A change that makes a current-state document wrong fixes it in the same change** — already a
   working agreement, and now load-bearing rather than good practice.

## Consequences

**Answering "how is this done now" becomes one document instead of a corpus** — 5,000 to 8,000 words
on a topic rather than 237,000 across all of them, and correct by construction rather than by careful
reading.

**Answering "how did we get here" is unchanged, and stays the ADRs' job.** It was never the expensive
question, and nothing here makes it harder.

**The dangerous consequence, stated plainly: a current-state document that silently omits a decision
now gives a confident wrong answer.** Before this, an incomplete document was merely incomplete and a
reader fell back to the ADRs. After this, the document is what a reader trusts, so an omission is
indistinguishable from a decision that was never made. **That is why point 2 is a mechanical check and
not a convention** — without it this ADR trades a slow correct answer for a fast wrong one, which is a
bad trade at any speed.

**Thirty-five ADRs have no current-state home today**, including `0001` and `0002`. Until each is
placed, the check reports them and the guarantee does not hold for them. That backfill is `23-113`,
and it is deliberately not part of accepting this — the convention has to be true going forward before
the backlog of it is worth paying down.

**Some duplication is now intended.** A decision's *what* lives in a document and its *why* lives in
an ADR, and the two can drift. This is accepted as the lesser evil: the alternative is a single place
that must be both a specification and a history, which is exactly what produced amendments appended
inside accepted decisions.

## Alternatives considered

**Machine-readable frontmatter on every ADR plus a generated `CURRENT.md`.** Each ADR declares
`supersedes`, `superseded_by`, `amended_by` and `topic`; a script assembles what holds. It is the more
rigorous answer and it does not depend on any document being complete. It lost on cost against
duplication: it means reading all 129 files to discover relationships that were never recorded, then
maintaining a second index whose whole purpose — "what holds now, by topic" — is what
`docs/architecture/*` already does. Worth revisiting if the archaeology question ever becomes
expensive; it is not today.

**Leaving it alone and reading the chain each time.** The honest null option, and it is what has been
happening. Rejected on the reliability argument rather than the cost one: 237,000 tokens is affordable
and a silently missed amendment is not.

**Enforcing immutability only (point 1 alone).** Cheapest, and necessary regardless — it is folded in
above rather than treated as an alternative. Alone it fixes correctness of the corpus without making
the frequent question any cheaper, because the reader still has 129 files to traverse.
