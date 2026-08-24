# Personal data outside the database: logs, traces, and what an incident would need

- **Stage**: 16
- **Status**: ready
- **Depends on**: `16-01-personal-data-map-and-residency-constraint.md` — this item fills in the two
  rows that map currently marks "unverified"

## Goal

The two stores nobody has actually looked inside — traces and logs — are known rather than assumed,
and the edge access logs that hold client IP addresses have a defined retention instead of an
unbounded one. After this, `personal-data.md`'s table has no "unverified" row left, and a question
like "what data was affected" has an answer that does not start with a guess.

## Context to read first

`docs/architecture/personal-data.md`'s table — the rows marked unverified are this item's subject.
`docs/backlog/7-01-opentelemetry-tracing.md` and `7-02-metrics-instrumentation.md` — what is
instrumented and what tags are attached; the question is whether any span attribute or log scope
carries message text, an email address, or a token. `docs/conventions/coding-style.md`'s logging
rules — the existing convention this item checks reality against. `docs/architecture/edge.md` — NGINX
Gateway Fabric terminates client connections and logs them; those logs contain IPs and nothing else
in this repository says how long they are kept. `docs/backlog/15-03-alerting-and-notification.md` —
the alerting work this item's incident half depends on, since a deadline that starts at "when someone
noticed" is not a deadline anybody can meet.

## Scope

- **Audit what is actually emitted**: run the system, capture real traces, logs and metrics, and check
  span attributes, log messages and metric labels for message bodies, email addresses, visitor tokens,
  access tokens and IP addresses. Written up as findings, not as a claim that it was checked.
- Fix whatever the audit finds, and add a guard where a guard is possible — a test that fails if a
  known-sensitive value appears in a log scope is worth more than a convention nobody re-reads.
- **Edge access-log retention**: define it, apply it, and record the number. IPs kept forever by
  default is the most ordinary way a system holds personal data nobody meant to keep.
- Confirm the same for Prometheus labels and Jaeger spans, whose own retention `7-03` already reasons
  about for size but not for content.
- **The incident half**: a written path for what happens when personal data is exposed — how the
  affected scope is determined (which is only answerable because `16-01`'s map exists), who is told,
  and in what order. The technical requirement is that detection is fast enough for any deadline to be
  meetable at all, which is `15-03`'s alerting; this item states the dependency and the procedure, and
  leaves the legal deadlines and their applicability to `ago-business` and a lawyer.

## Out of scope

- Log aggregation or a log store — there is none, and building one is a separate decision.
- Redacting message content from the database. Content in `messages.body` is the product
  (`personal-data.md`); this item is only about copies of it leaking into places that were never
  meant to hold it.
- Deciding whether a given incident is notifiable, or to whom, or in what timeframe — legal, not this.
- Security hardening generally. This item is about what is recorded, not about who can reach it.

## Done when

- [ ] Traces, logs and metrics have been inspected against real traffic, and the findings written down.
- [ ] Nothing sensitive is emitted, or what was is fixed, with a guard where one is possible.
- [ ] Edge access-log retention is defined, applied, and recorded.
- [ ] `personal-data.md` has no unverified row left.
- [ ] An incident procedure exists, names its dependency on `15-03`, and says plainly which parts are
      the lawyer's to answer.

## Open questions

None on the technical side. The legal deadlines belong to `ago-business`.
