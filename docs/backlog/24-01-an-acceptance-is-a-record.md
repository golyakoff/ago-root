# an acceptance is a record: who accepted which document, in which version, when

- **Stage**: 24
- **Status**: ready
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

- [ ] An acceptance can be recorded and read back with subject, document, version and timestamp.
- [ ] `personal-data.md` carries the row, including retention and what removes it.
- [ ] The erasure decision is recorded with its reasoning, and a test holds it in place — including the
      case the decision does **not** remove, so a later change cannot quietly reverse it.
- [ ] A second acceptance of the same document by the same person does not overwrite the first: the
      question "what did they agree to in March" has an answer.

## Open questions

- **Does erasure remove an acceptance record?** The two pulls are real. A person asking for erasure has
  a right to it; and we may need to show, later, that their data was processed lawfully at the time.
  This needs an answer before the store is built, not after.
