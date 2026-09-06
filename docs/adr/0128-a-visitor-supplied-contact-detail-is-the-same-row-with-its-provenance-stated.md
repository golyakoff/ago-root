# ADR-0128: A visitor-supplied contact detail is the same row with its provenance stated, and `Verified` is a fact nobody can assert about themselves

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 23 (`23-09`)

## Context

`14-14` built `visitor_contact_details` for exactly one shape: **an operator typing down a fact a
visitor said out loud.** That was the only way a row could appear, and `personal-data.md`'s entry for
the table said so in as many words — *"never because a real message arrived from that address and
never because a verification code proved anyone controls it"*.

`decisions.md` §4 then asked for the out-of-hours case: nobody is on shift, and the visitor should be
able to leave a number themselves rather than wait. That is a second way a row can appear, and it
falsifies the sentence above — which is why this ADR exists rather than only a schema change.

Two questions had to be answered before the column could be added at all: **where the visitor's own
contact lives**, and **what distinguishes it once it is there**.

## Decision

**The visitor's own contact detail is the same table and the same aggregate, with its provenance
recorded.** Not a second table, and — the tempting one — **not a `ChannelIdentity`**. A
`ChannelIdentity` means an address a real message arrived from, or one a verification code proved
somebody controls. A number typed into a form is neither. Treating it as a channel identity would make
the strongest claim this system can make about an address (*we have seen traffic from it*) out of the
weakest evidence it accepts (*somebody typed it*), and every later reader of that table would inherit
the confusion.

**`Source` is its own column, never inferred from `RecordedByOperatorId` being null.** The absence of
an operator id is ambiguous on its own — it could mean "the visitor supplied this" or "some future
write path that is neither" — and a fact a reader has to reconstruct from a null is exactly what
`VisitorContactDetail`'s own remarks already reject for `Kind`, which is a real column rather than
something inferred from the shape of `Value`. So `Source` states which it is, and a null
`RecordedByOperatorId` becomes a *consequence* of `Source = Visitor` rather than the fact itself.

**`Verified` is a separate fact, it starts `false`, and no path a visitor can construct sets it.**
Both factory paths — the operator's and the visitor's — hard-code `verified: false`. Verification
means somebody other than the claimant established control of the address; a person asserting it about
their own number is not evidence of anything, and a flag that a subject can set about themselves is
worse than no flag, because a reader trusts it. The mode that *does* set it true is deliberately out
of this item's scope, so the column ships with exactly one writer and that writer always writes
`false`.

**The migration backfills `source` to `Operator`, by hand, over EF's generated `""`.** Every row that
existed before this ran was recorded the only way `14-14` ever offered. EF cannot infer that: the
entity configuration deliberately declares no permanent `HasDefaultValue`, because every future insert
sets `Source` explicitly and a standing database default would have nothing to do. The hand edit is
the one place in this change where regenerating the migration mechanically would produce a silently
wrong result — an empty string no `VisitorContactDetailSource` member parses back from — and it is
commented in the migration for that reason.

**This supersedes `personal-data.md`'s claim about the table**, which was true of `14-14` and is not
true now.

## Consequences

**Positive.** A tenant who is offline stops losing the callback, and an operator reading the panel can
tell a self-reported number from one somebody checked — which is the distinction that decides whether
it is worth dialling. The provenance is a column rather than a convention, so a later read cannot get
it wrong by reasoning about nulls.

**Negative, stated rather than discovered.**

- **`Verified` currently has one writer, and it always writes `false`.** A column that can only hold
  one value is a column a later reader may assume is decorative. It is not — it is the seat a
  verification path will occupy — but until that path exists, the honest description is "reserved, and
  visibly so".
- **Two shapes now live in one table**, distinguished by a column rather than by structure. That is the
  right trade for a fact that is otherwise identical in every respect, and it does mean every read of
  this table must decide whether it cares about `Source`. `23-11`'s masking, landing days later, is the
  first read that does.
- **The strongest evidence about an address still lives elsewhere.** `ChannelIdentity` remains the only
  place that means "traffic arrived" or "a code was confirmed", and keeping the two apart is the whole
  point of this decision — at the cost that answering *"what do we know about this phone number"* now
  requires looking in two places.

## Alternatives considered

**Store the visitor's own contact as a `ChannelIdentity`.** Rejected — see the Decision. It would make
the system's strongest claim about an address out of its weakest evidence.

**A second table for visitor-supplied details.** Rejected: the two rows are the same fact about the
same person, differing only in who wrote it down. Splitting them would duplicate every read, every
erasure path and every masking rule for a distinction one column carries.

**Infer the source from `RecordedByOperatorId IS NULL`.** Rejected: it is free today and wrong the
first time a third write path appears, and it makes a fact readable only by reasoning about an absence.

**Let the visitor's own submission count as verified when it arrives with a valid visitor token.**
Rejected outright. The token proves this browser is the visitor it claims to be; it proves nothing at
all about whether they control the phone number they typed.
