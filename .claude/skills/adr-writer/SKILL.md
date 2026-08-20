---
name: adr-writer
description: Write or supersede an Architecture Decision Record for AGO Platform. Use when a change involves choosing between real alternatives, weakening or strengthening a guarantee, or deliberately deviating from an architectural rule.
---

# Writing an ADR

Location `docs/adr/`, template `docs/adr/_template.md`, index `docs/adr/README.md`.

## Does this need an ADR?

**Yes** if: a technology was chosen over an alternative a reviewer would have expected; a guarantee
changed (ordering, durability, consistency); a layering rule was deliberately deviated from; a
decision will be expensive to reverse; or someone reading the code in six months would ask "why on
earth".

**No** if: a convention doc already covers it (naming, formatting, test structure); it is an
implementation detail with no alternative worth naming; or it is reversible in an afternoon.

When in doubt, ask whether you could argue the other side for two minutes. If yes, write it.

## Rules

1. **Number sequentially**, never reuse a number, and add the row to `README.md` in the same change.
2. **Immutable once accepted.** A changed decision is a *new* ADR marked "Supersedes ADR-NNNN"; the
   old one gets "Superseded by ADR-NNNN" and keeps its original text. Editing accepted reasoning
   destroys the record's only value.
3. **Context contains no solutions** - only the forces: load characteristics, constraints, earlier
   decisions this must live with.
4. **Consequences must include the negative ones.** An ADR listing only benefits is marketing. State
   what got harder, what must now be maintained, and what was given up.
5. **Alternatives get a fair hearing.** Name the strongest competing option and the real reason it
   lost - "adds a deployable to operate", not "not suitable". If the alternative is what most teams
   would choose in production (MassTransit, a Redis backplane, EF everywhere), say so explicitly:
   showing you know the pragmatic choice and chose otherwise deliberately is the entire point in a
   portfolio project.
6. **Date it, and name the roadmap stage.**
7. Keep it under a page. Long ADRs do not get read, and an unread ADR is a wasted one.

## After writing

- Link it from the architecture doc it affects.
- If code already contradicts it, either fix the code in the same branch or mark the ADR `Proposed`
  until it does. An `Accepted` ADR the code violates is worse than no ADR.
