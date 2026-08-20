# ADR-0001: Record architecture decisions

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 0

## Context

This project exists to be reviewed by other engineers. Code shows *what* was built; it never shows
what was rejected, and "why not X" is the first question a senior reviewer asks. The decisions must
also survive being implemented across many separate AI sessions that share no memory.

## Decision

Every arguable decision gets a numbered ADR in `docs/adr/` using `_template.md`. ADRs are immutable
once accepted; a change is a new ADR that supersedes the old. Code that contradicts an accepted ADR
without a superseding one is treated as a defect.

## Consequences

- A reviewer reads ten short files and understands the whole rationale.
- Every session has an authoritative answer to "why is it like this", so decisions stop drifting.
- Cost: discipline. An ADR written after the fact to justify existing code is worse than none.

## Alternatives considered

- **Comments in code** - invisible at design level and they rot beside the code they justify.
- **One big design document** - becomes a wall of text where superseded reasoning is quietly edited out.
