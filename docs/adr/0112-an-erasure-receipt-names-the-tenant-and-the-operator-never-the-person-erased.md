# ADR-0112: An erasure's own receipt names the tenant and the operator, never the person erased

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 24 (`24-13`)

## Context

`16-02` shipped erasure. Nothing recorded that it happened, so a tenant asked to demonstrate
compliance — by a customer, an auditor, or `152-ФЗ`'s own art. 18.1 — had nothing to show but the
absence of data, which is indistinguishable from data that was never there.

`personal-data.md` had already rejected a deletion journal, and for a good reason: a journal of what
was deleted is a copy of what was deleted. So the record this item needed had to prove an erasure
happened **without** re-creating any part of what it removed.

The obvious precedent is `export_requests`, which this project already runs and which names its
subject freely. That precedent does not transfer unexamined: an export's subject is the whole tenant,
while an erasure's subject is frequently **one visitor**.

`adr/0111` decided, three days' work earlier in the same stage, that an acceptance record survives the
erasure of its own subject. That decision points the opposite way from this one and the tension is the
whole substance of this ADR.

## Decision

`erasure_records` names the **tenant** (`site_id`) and the **requesting operator** (`requested_by`) —
both business identities — plus scope, status, timestamps and per-step counts. It carries **no
`conversation_id` and no `visitor_id`, ever.**

- **A conversation erased under a whole-site cascade gets no row of its own.** Only the site's own
  record, carrying `conversations_marked_for_erasure` as an aggregate. A conversation named in its own
  standalone erasure request — which is the shape a person's own request takes — does get an
  individual receipt.
- **`site_id` and `requested_by` carry no foreign key**, so a site-scoped erasure's receipt survives
  the `DeleteSiteAsync` it is evidence of. That is `adr/0111`'s mechanism, reused for a different
  reason: there, evidence must outlive its subject's erasure; here, a receipt must outlive the very
  deletion it proves.
- **`failure_reason` holds an exception type name, never a message.** A message can quote an object
  key, a path, or a fragment of the data being removed.
- **Retention is indefinite, and chosen rather than defaulted** — the same posture `export_requests`
  and `adr/0111` take, stated so a later reader does not mistake it for nobody having built pruning.

## Alternatives considered

**Store the conversation or visitor id, accepting the same trade-off `adr/0111` made for
`acceptance_records.subject_id`.** This is the strongest alternative and the one a reader will expect,
because the sibling decision three items earlier went exactly that way. Rejected because the two
records are asked to prove opposite things. An acceptance record exists to say *this person agreed*;
naming them is the content. An erasure receipt exists to say *this person's data is gone*; naming them
keeps a pointer to the person whose pointer was supposed to disappear. The same identifier is
load-bearing in one and self-defeating in the other.

**A per-conversation receipt even under a site cascade.** Rejected on cost without matching benefit:
it would require plumbing per-conversation counts back from `ConversationErasureJob`'s independent
ticks into `SiteErasureJob`'s own record, and the site's record already proves the erasure at the
granularity it was actually requested. **This is the decision in this ADR least forced by the
evidence**, and the one to revisit first if a real compliance request turns out to need per-person
proof after a site-wide erasure.

**A deletion journal**, listing what was removed. Rejected before this item began (`personal-data.md`),
and named here because it is what somebody will propose the first time this receipt is not enough.

## Consequences

**Positive.** A tenant asked whether an erasure ran can show that one ran, for the right site, by the
right operator, at the right time, with real per-step counts — and that a failure was a failure rather
than a silence. Failure is a recorded outcome, not an absence, which is what makes the record evidence
rather than a happy-path log.

**Negative, and stated rather than discovered.** Asked *"was this named person's data erased"*, this
table alone cannot answer *which* visitor. The correlation must come from outside the system — a
support ticket, the operator's own record of the request. That is a genuinely narrower guarantee than
a journal would give, and it is the price of the decision above rather than an oversight.

`Completed` also means *everything this process could reach, now* — not *gone from backups*.
`adr/0050`'s thirty-day retention on collected copies still applies, so a restore inside that window
can contain what a `Completed` receipt describes as erased. A receipt implying otherwise would be the
dishonest version of this item, so the window is stated alongside the record.

**And this decision is the one to reopen if `24-04`'s legal reading lands differently.** Like
`adr/0111`, it rests on a reading of what evidence a controller must be able to produce; unlike
`adr/0111`, being wrong here means the record is too *thin* rather than too revealing, which is the
cheaper direction to be wrong in but not a free one.
