# an acceptance is a record: who accepted which document, in which version, when

- **Stage**: 24
- **Status**: done (2026-09-05) — the record, its two handlers, the erasure exception in `adr/0111` and the guard that holds it. **No endpoint**: which caller may record an acceptance, and under what authentication, is `24-03`/`24-04`/`24-05`'s to decide, and this item deliberately builds no route.
- **Depends on**: nothing. Every other item in this stage writes to what this builds, so it goes first.
- **Decision**: `docs/adr/0076-*` (who is controller and who is processor, decided in `16-04`)

## Goal

When a person accepts something, the system can say afterwards **what** they accepted, **which version**
of it, **when**, and **who they were** — without asking them to take our word for it.

## Why this is the first item

Every other item in this stage ends with somebody accepting something. None of them is finished if the
acceptance leaves no trace: an acceptance nobody can reconstruct is indistinguishable from one that
never happened, and the burden of showing a lawful basis sits with us, not with the person.

## What is actually true today, verified

- **Nothing records an acceptance.** Grepped `ago-chat` for consent, acceptance and terms:
  the hits are `AuthEndpoints`, the channel adapters and widget config — none of them records that a
  person agreed to anything.
- **`16-04` shipped a notice, not a consent.** The widget shows a processing notice before the visitor
  types, with the text and link supplied by the tenant. A notice tells somebody what happens; it does
  not record that they agreed. The two are different obligations and the difference is this stage.

## Scope

- A store for acceptances: the subject (which operator, which tenant, or which visitor), the document
  identity, the **version** identifier, the timestamp, and enough of the request context to make the
  record credible without turning it into a surveillance log.
- A port in `Application/Abstractions` and its adapter, in the shape this codebase already uses.
- **`personal-data.md` gains its row in the same change** — this is a new personal-data store, and the
  register calls that "not a small change". What is held, control, retention, what removes it, and
  where it was verified.
- **The erasure path, stated and tested.** An acceptance record is evidence of a lawful basis, and
  evidence that vanishes with the account it justifies is worth less than no evidence. Decide
  deliberately whether erasure removes it, anonymises it, or keeps it — and write down which and why.
  `23-08` is the precedent for how that reasoning is recorded.

## Out of scope

- The documents themselves and their text — `ago-business` and a lawyer, per `personal-data.md`'s own
  "What is not decided here".
- Showing anything to anybody. That is `24-03`, `24-04` and `24-05`.
- Versioning and publication — `24-02`.

## Done when

- [x] An acceptance can be recorded and read back with subject, document, version and timestamp.
      *`RecordAcceptanceHandler` for all three subject kinds, `GetAcceptancesForSubjectHandler` reading
      them back oldest-first.*
- [x] `personal-data.md` carries the row, including retention and what removes it.
      *And what does **not** remove it, which is the unusual half here.*
- [x] The erasure decision is recorded with its reasoning, and a test holds it in place — including the
      case the decision does **not** remove, so a later change cannot quietly reverse it.
      *`adr/0111`; `AcceptanceRecordErasureGuardTests` covers both erasure scopes — a visitor's own
      conversation erasure and a whole site's. Re-proven biting rather than taken on trust: with the
      conversation erasure mutated to also `delete from acceptance_records`, the guard fails.*
- [x] A second acceptance of the same document by the same person does not overwrite the first: the
      question "what did they agree to in March" has an answer.
      *`HandleAsync_CalledTwiceForTheSameSubjectAndDocument_SavesTwoDistinctRecords`, and the domain's
      own `TwoAcceptancesOfTheSameDocumentByTheSameSubject_AreDistinguishableRecords`.*

## Open questions

- **Does erasure remove an acceptance record?** The two pulls are real. A person asking for erasure has
  a right to it; and we may need to show, later, that their data was processed lawfully at the time.
  This needs an answer before the store is built, not after.

## Outcome

Built as a record with no entry point, deliberately: `24-03`/`24-04`/`24-05` each decide who may record
an acceptance and under what authentication, and this item would have had to guess at three answers to
build one route. What it leaves them is a table, two handlers and a decision.

**One thing it leaves them that is easy to misread, and is called out here rather than discovered
later.** Both handlers are listed in `TenantScopeExemptions` — correctly today, because neither takes a
`SiteId` and no host maps a route to either, so there is nothing yet for a permission policy to sit
behind. That exemption does **not** extend to the endpoints those three items will build. Each of them
takes the subject from the validated principal, never from a parameter the caller supplies; an endpoint
that accepts a subject id and checks it matches is the same defect with an extra step. The exemption
entries will already be in the file when those items start, which is exactly why this is written down.

**A finding from landing it, not from building it.** The branch built and passed for its author and
then did not compile against `main`: `24-09` merged in between and gave `ConversationErasureJob` a
seventh constructor parameter, which this item's own guard test constructs directly. `dotnet test`
reported `Пройден!` for four assemblies, said nothing about the two that never compiled, and exited 0 —
the failure `land-a-slice`'s *read the assembly list, not the failure count* rule exists for, caught
here by that rule and not by anything automated.
