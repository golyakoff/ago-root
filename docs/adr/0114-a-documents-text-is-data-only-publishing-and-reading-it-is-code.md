
# ADR-0114: A document's text is data; only publishing and reading it is code

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 24

## Context

`24-01` built a record that a subject accepted a specific version of a specific document
(`AcceptanceRecord`), deliberately leaving `DocumentKey`/`DocumentVersion` as opaque strings — no
table backed them yet. `24-02` closes that gap: something must publish a document's actual text,
serve the current version to an unauthenticated reader, and keep every superseded version readable
forever. The author has already decided the division of labour and the sequencing: the mechanism
ships now, with draft text; a lawyer validates the wording afterward. That decision only works if
a lawyer's correction is a change to *data*, never a change to *code* — otherwise every wording fix
would need a build, a review, and a deploy for a change with zero mechanical risk.

## Decision

A document's text lives in Postgres, in two tables mirroring `Conversation`/`Message`:
`documents` (one row per document key, holding a `LastSequence` counter and an optimistic-concurrency
token) and `published_document_versions` (one immutable row per published version, holding the
actual title/body). The version identifier a caller ever sees or quotes — `"v{n}"` — is derived from
`LastSequence`, never supplied by a caller: this is what makes it simultaneously stable (never
reassigned), ordered (it *is* the order, CLAUDE.md rule 11), and human-quotable ("you accepted v4").

Publishing is one call — `PublishDocumentVersionHandler`, reached only through
`POST /api/v1/owner/documents`, gated by the existing `RequirePlatformOwner` policy. There is no
`Rename`/`Update` method anywhere in the type: a correction is a new version, never an edit to an
existing row. Reading is unauthenticated by construction — `GET /api/v1/documents/{key}` (current)
and `GET /api/v1/documents/{key}/versions/{version}` (a specific, immutable version) — because
`24-02`'s own scope names the caller who needs this: someone who has not yet accepted anything has
no account to read it from.

## Consequences

**Positive.** Adding a version, fixing a typo, or replacing a document outright is one authenticated
HTTP call the platform owner makes after `ago-business` and a lawyer sign off — never a commit, a PR,
or a deploy. A superseded version is never deleted (no delete method exists on the repository port,
the same structural guarantee `adr/0111` gives `AcceptanceRecord`), so "what did v4 actually say"
always has an answer. `AcceptanceRecord.DocumentVersion` (`24-01`) and `PublishedDocumentVersion.Version`
(`24-02`) are now provably the same string space — proven by an integration test, not merely asserted.

**Negative, named rather than hidden.** This ADR does not decide whether a new version invalidates
an existing acceptance — `24-02`'s own Open question, deliberately left to the lawyer's reading,
since re-obtaining consent unnecessarily is itself a cost. Nor does it decide which documents exist
at all (`24-03`/`24-04`/`24-05`'s job). The mechanism accepts plain text/simple markdown with no
markup language of its own — a future item may need to add one, which is additive, not a reversal
of this decision.

## Alternatives considered

- **Text as a file in this repository, deployed with the code.** Rejected: a wording fix would then
  need a PR, a review, and a deploy for a change that carries zero mechanical risk — precisely the
  cost this ADR exists to avoid, and it would blur "the mechanism is ours, the text is
  ago-business's and a lawyer's" into one repository holding both.
- **A single "current text" row per document, overwritten in place.** Rejected outright — this is
  the specific failure `24-02`'s own Goal exists to prevent: a person who accepted v3 could no
  longer read what they accepted the moment v4 overwrote it.
- **A caller-supplied version string (e.g. the platform owner types "v4" by hand).** Rejected:
  nothing stops two publishes choosing the same label, or a label that sorts wrong lexically
  ("v10" before "v2"). Deriving the label from a server-assigned sequence gets stability, ordering
  and human-quotability simultaneously, with no caller discipline required to keep them true.
- **A content hash as the version identifier.** Rejected: stable and even ordered-by-nothing, but
  not what a support conversation can say aloud — "you accepted a3f9c2..." is not "you accepted v4".
