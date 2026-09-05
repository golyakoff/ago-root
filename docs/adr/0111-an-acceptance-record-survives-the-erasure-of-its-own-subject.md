# ADR-0111: An acceptance record survives the erasure of its own subject

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 24

## Context

`24-01` builds the first thing Stage 24 needs: a record that a subject (a tenant, an operator, or a
visitor - `adr/0076`'s own three-way split) accepted a specific version of a specific document, at a
specific instant. Its own backlog item names one open question before the store could be built at all:
**does erasure remove an acceptance record?**

Both pulls are real, and neither is a strawman.

- A person who asks for erasure has a right to it, and `16-02`/`23-08` already treat that right as a
  product requirement, not a courtesy - a record this system keeps *about* them, after they asked to be
  forgotten, is exactly the kind of thing those two items exist to reach.
- **The record's entire reason to exist works against removing it.** `24-01`'s own Goal is "the system
  can say afterwards what they accepted... without asking them to take our word for it" - that sentence
  is only true for as long as the record survives. An acceptance record that a lawful-basis question
  might need is evidence of processing that already happened; deleting it on the same request that
  triggers a fresh erasure does not undo the earlier processing, it only removes AGO's own ability to
  show it happened lawfully. `152-ФЗ`'s own analogue to GDPR Art. 17(3)(b) - a controller may retain
  data necessary "for compliance with a legal obligation" or "for the establishment, exercise or
  defence of legal claims" - is cited here for orientation, the same footing `personal-data.md` already
  uses for the localisation rule, not as this repository's legal reading.

**What tips it, and it is a fact about this table rather than a general privacy stance.** An acceptance
record holds a narrow, low-risk shape: a subject kind, a subject id, a document key, a version, a
timestamp, and two short request-context fields (`AcceptanceRecord`'s own remarks explain why exactly
those two and nothing else). It is not a copy of `messages.body`, not a phone number, not free text a
person wrote about themselves - the thing `personal-data.md`'s own "shape of the problem" section calls
the hard part of this system's privacy story. Keeping a narrow evidentiary fact is a materially smaller
retention decision than keeping a transcript would be, and `23-08`'s own `visitor_contact_details` row
is the precedent for exactly this shape of argument: an "indefinite" retention is defensible when it is
named, reasoned about and stated in the register, rather than a byproduct of nobody having built
deletion.

## Decision

**An acceptance record is not removed, anonymised, or otherwise altered by any erasure this codebase
runs today** - not `16-02`'s conversation-scoped erasure, not `16-02`'s site-scoped erasure, and not
any future per-operator erasure `24-04` might add. It is kept whole, including the subject id, as
evidence that processing had a lawful basis at the time it happened. Retention is **indefinite** - the
same word `visitor_contact_details` already carries in `personal-data.md`, and for the same kind of
reason: this is not a timed record about the visitor, it is AGO's own evidence of its own compliance,
and nothing in this item invents a number `docs/roadmap.md`'s own guardrails would call unmeasured
(CLAUDE.md: "do not invent numbers, benchmarks, or 'typical' production figures"). If a real retention
period is ever wanted for this table - a limitation period after which a lawful-basis question can no
longer be raised, for instance - that is a future, scoped decision with its own number and its own
reasoning, not a default this ADR backs into.

**Made structural, not merely documented.** `acceptance_records.subject_id` carries **no foreign key**
to `sites`, `operators`, or `visitors` - the identical mechanism `adr/0101` already established for
`conversation_assignments.conversation_id`, applied here for a different reason (there: a workload
count should not disappear with a visitor's own erasure; here: evidence should not disappear with any
subject's own erasure). Concretely: `ConversationErasureQuery`'s per-conversation drain
(`16-02`/`23-08`) never mentions `acceptance_records`, and `SiteErasureQuery.DeleteSiteAsync`'s cascade
list - `operators`, `visitors`, `channel_identities`, and everything reachable through them - has
nothing to reach this table with, because nothing points at it.

**Anonymising the subject id instead of keeping it whole was considered and rejected** - see
Alternatives. The decision is to keep the record identifiable, because an unattributed acceptance is
close to worthless as evidence: "someone accepted version 4 on 12 March" answers a different, much
weaker question than "this operator accepted version 4 on 12 March," and the whole point of building
this store is to be able to answer the second one.

**Guarded, not merely asserted.** `tests/Ago.Chat.Integration.Tests/AcceptanceRecordErasureGuardTests.cs`
proves both directions this decision touches: erasing a conversation (which also drains that visitor's
`visitor_contact_details`, `23-08`) leaves the visitor's own acceptance record standing and readable;
deleting a site (which cascades its operators) leaves both the tenant's own acceptance record and an
operator's own acceptance record standing and readable. Both are guards, true today by construction -
there is no foreign key to cascade through, so there is no code path from either erasure job to this
table to break yet. They exist so a future foreign key added "for consistency" with
`conversation_notes`/`visitor_contact_details`, or an explicit drain step added by a reviewer assuming
the same symmetry those two tables use, cannot quietly reverse this decision with no suite going red -
the same reasoning `adr/0101`'s own guard gives for `conversation_assignments`.

## Consequences

**Positive.** A lawful-basis question - "did this tenant/operator/visitor really agree to this version,
and when" - has an answer for as long as this system runs, independent of whether the subject's account
or conversation was later erased. This is the property `24-02` through `24-05` are all building toward:
none of them can finish if the record they end with can be made to disappear by an unrelated erasure
request.

**Negative, and named rather than hidden.** `acceptance_records` can hold a `subject_id` that no longer
resolves to any live `sites`/`operators`/`visitors` row, once that subject is erased - a genuine
dangling reference, the identical trade-off `adr/0101` already accepted for `conversation_assignments`,
here applied to a table that (unlike that one) is the *point* of an item rather than a side effect of
one. Any future reader that joins this table to a subject's own row must treat a missing subject as an
expected outcome: an acceptance record surviving its own subject's erasure is this ADR working as
intended, not a data-integrity bug. There is also no database-level defence against a genuine bug that
writes a `subject_id` that was never real to begin with - caught only by review and by the guard tests
above, the same residual `adr/0101`'s own Consequences names for its own table.

**A second, harder question this ADR does not answer.** If the lawyer's eventual reading of `152-ФЗ`
(or GDPR, for a future EU tenant) concludes that an acceptance record must itself be erasable on
request - because "evidence of a lawful basis" does not survive scrutiny as its own separate basis for
retention - this decision is wrong and needs superseding, not patching. That confirmation sits with
`ago-business` and a lawyer, exactly the boundary `personal-data.md`'s own "What is not decided here"
draws, and exactly the posture `adr/0076` already took for the controller/processor split this ADR
depends on.

## Alternatives considered

- **Remove the acceptance record on any erasure that reaches its subject.** Rejected: this is the
  option that looks most respectful of the request and is least defensible on inspection - it removes
  AGO's own ability to show a lawful basis existed, on the same request that is supposed to be handled
  lawfully. It also directly contradicts `24-01`'s own Goal, which exists specifically so this system
  does not have to ask a person to take its word for what they agreed to.
- **Anonymise: strip the subject id, keep document/version/timestamp.** The middle option, and the one
  most likely to be proposed as a compromise. Rejected because it produces a record that answers a
  strictly weaker question than the one this item was built to answer - "somebody accepted version 4 on
  12 March" is not "this operator accepted version 4 on 12 March," and evidence of lawful basis without
  an identifiable subject is close to no evidence at all for the dispute it would actually be used in.
  If a future, scoped item wants a genuinely anonymised statistic ("how many tenants accepted v4 in its
  first month"), that is a different read model built for a different purpose, not a mutation of this
  table's own rows.
- **Time-boxed retention, matching `messages.body`'s per-tier window (`adr/0031`/`13-06`).** Rejected
  for lack of a number to put in it: that window exists because `15-05` measured a real value for a
  high-volume, high-sensitivity free-text store. An acceptance record is neither high-volume (a handful
  of documents per subject, ever) nor comparable in sensitivity, and inventing a plausible-sounding
  number for it would be exactly the guessing CLAUDE.md's working agreements forbid. **Indefinite,
  stated as a deliberate choice** (`23-08`'s own precedent for `visitor_contact_details`) is more honest
  than a borrowed number that does not derive from anything about this table.
- **A foreign key with `ON DELETE SET NULL` on `subject_id`.** Rejected: `subject_id` is not nullable
  and a null subject is not a smaller fact about an acceptance, it is a different and useless one - the
  identical reasoning `adr/0101` gives for rejecting the same shape on `conversation_assignments`.
