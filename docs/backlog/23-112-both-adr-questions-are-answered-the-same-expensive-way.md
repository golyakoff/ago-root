# both ADR questions are answered the same expensive way

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. `23-111` is the same shape applied to `CLAUDE.md` and the skills.
- **Found**: 2026-09-08, by the author, noticing the cost of reading chains to work out what is current.

## What the author observed

> As the project grows we change or refine decisions, and chains appear — ADR1, in which something
> went stale and something was refined, overlaid by ADR2, then something changed there too and the
> refinement landed in ADR3. There are two typical tasks: "remember how we got here" and "see what
> holds now", and both use the route ADR1 → ADR2 → ADR3. Even when the question is what is current,
> you read everything and then compute what is left.

That is exactly right, and the measurement is worse than the description.

## The measurement

- **129 ADRs, 178,000 words — about 237,000 tokens** to read in full.
- **Exactly one** machine-readable supersession link exists (`0015` → `0018`). Twenty-five files
  discuss superseding and twenty-seven discuss amending, **all in prose**.
- The index carries a supersession or amendment note on **14 of 132** rows.
- **Amendments are appended inside accepted ADRs**, contradicting `docs/adr/README.md`'s own rule. One
  records being *"amended three times… all three amendments are appended below."*

**So an ADR's number and status guarantee nothing.** A file can look current and carry its own
reversal several screens down. That is why the author's worry — *miss a link in the chain and you
compute the wrong answer* — is not merely possible; the corpus is shaped to cause it, and no index
built over it can be trusted while a body can change after acceptance.

## What was decided

`adr/0156`, chosen by the author over two alternatives: **a current-state document is authoritative for
what holds; an ADR is authoritative for why.**

The frequent question — *how is this done now*, asked every session — becomes one document of 5,000 to
8,000 words instead of a 237,000-token reconstruction. The rare question — *how did we get here* —
stays exactly where it was, because it was never the expensive one.

Three parts, and all three are required:

1. An accepted ADR is immutable; the only permitted edit is its `Status` line. **No more amendments
   appended to the body.**
2. **Every ADR is referenced from at least one current-state document**, checked by
   `tools/queue-audit.sh`.
3. A change that makes a document wrong fixes it in the same change.

**Part 2 is what makes the split safe rather than merely fast**, and it is why this was not shipped as
a convention alone: a curated source that silently omits something gives a *confident wrong answer*,
which is a worse trade than the slow correct one it replaced.

## What was rejected, and why it is worth recording

**Machine-readable frontmatter plus a generated `CURRENT.md`** was the more rigorous option and does
not depend on any document being complete. It lost on cost against duplication — discovering
relationships that were never recorded means reading all 129 files, and the result duplicates what
`docs/architecture/*` already does for 94 of them. Revisit if archaeology ever becomes expensive.

## Done when

- [x] The split is decided, recorded as an ADR, and stated where a reader will meet it —
      `adr/0156`, `docs/conventions/documentation.md`, `docs/adr/README.md`'s header, `adr-writer`,
      and one row in `CLAUDE.md`'s *Where to look*.
- [x] Amending an accepted ADR in place is forbidden in the two places that govern it —
      `docs/adr/README.md` and the `adr-writer` skill — with the reason, not just the rule.
- [x] Completeness is checked mechanically rather than asked for. `tools/queue-audit.sh` names every
      ADR with no current-state home; it reports 35 today, and `23-113` closes that backlog.
