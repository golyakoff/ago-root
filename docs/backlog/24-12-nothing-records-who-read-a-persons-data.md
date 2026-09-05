# reading a person's data leaves a record

- **Stage**: 24
- **Status**: done (2026-09-05). `access_records`, a tenant-facing read, a prune job, and `adr/0113` for why this names the resource where `adr/0112` names none.
- **Depends on**: nothing
- **Decision**: none yet — the shape of the record is the decision this item makes

## Goal

After the fact, this system can say who read a given person's data and when — not merely that the
controls which should have prevented the wrong person from reading it were in place.

## What is actually true today, verified 2026-09-05 (`24-06`)

Every isolation control in this project is **preventive**. `tenant-isolation.md` classifies 112 use-case
entry points, 75 permission-gated; `TenantScopeTests` fails the build when a use case is neither gated
nor explicitly exempt; `authorization.md` records two cross-tenant reads and three cross-tenant writes
in the whole codebase, all behind the platform-owner policy.

None of it is **evidential**. The only audit table in `ago-chat` is `module_grant_audit`
(`Stage22AddModuleGrantAudit`, 2026-09-04), and it covers a platform owner granting a module to a site.
Nothing records that an operator opened a conversation, read a transcript, viewed a phone number
(`20-12`'s `customer:read` in AGO Calendar), or pulled a returning visitor's cross-conversation history
(`18-07` — the one read path that reaches a conversation the operator was never a party to).

Application logs would not substitute even if they carried it: they are kept **14 days**
(`adr/0057`), and `16-05` established that what they carry is ids, counts and statuses.

## Why this is a gap rather than an oversight

Each control was correct for its own item's goal, and no item's goal was ever "be able to prove
afterwards who looked". That is the whole of it. Prevention and evidence are different properties and
building the first well produces none of the second — `17-01` is the proof from the other direction: a
real cross-tenant hole existed for months behind controls that looked complete, and when it was found
there was no way to ask whether it had ever been used.

It also blocks two other things concretely: `processing-instruction-facts.md`'s Element 6 lists this as
something that could not be produced on request, and `personal-data.md` cannot say who has reached a
row because nothing knows.

## Scope

- Decide **which reads** are worth recording. Recording everything is a second copy of the traffic and
  a personal-data store in its own right; the defensible set is the reads that cross a boundary —
  `18-07`'s cross-conversation history, the platform owner's cross-tenant reads and writes,
  `customer:read` in Calendar, and an export or erasure being requested.
- A durable record with its own stated retention, and its own row in `personal-data.md` — because an
  access log **is** personal data about the operator who made the access.
- Reachable by the tenant for their own site, not only by AGO.

## Out of scope

- Logging every read of every message. That is the version of this item that never ships and that
  doubles the storage of the busiest table in the system.
- Alerting or anomaly detection on top of it. A record first; watching it is later.

## Done when

- [x] The boundary-crossing reads listed above produce a durable record naming who, what and when.
      *Four of the five named. `customer:read` in AGO Calendar is not covered — a different repository
      on a different database — and that is written into the ADR and Element 6 rather than left to be
      discovered by whoever asks.*
- [x] The record has a stated retention enforced by something that runs, per `adr/0057`'s own standard.
      *365 days, `AccessRecordPruneJob`.*
- [x] `personal-data.md` has a row for it.
- [x] `processing-instruction-facts.md` Element 6 moves this line out of "could not be produced".
      *With its limits attached, and the *other* mention of this gap — the "every isolation control is
      preventive" finding — rewritten too, since leaving it would have made the file contradict itself.*

## Open questions

- **Does a tenant see AGO's own accesses?** A platform owner reading a tenant's data is exactly the
  access a tenant most wants recorded, and exactly the one that is uncomfortable to show them. Decide
  it deliberately rather than by whichever query is easier to write.

## Outcome

**This closes the last of the four gaps `24-06` found in Element 6.** `24-11` closed *everything held
about one person*, `24-09` *erasure reaches the archive*, `24-13` *proof an erasure happened*, and this
one *who read a given person's data*. Stage 24 was cut from that list; the list is now empty of the
things a first client's lawyer would ask about first.

**The set of recorded surfaces is named, not derived from a rule, and that is stated rather than hidden.**
A sixth boundary-crossing read is an argument for widening the enum — not evidence that it was already
covered. `adr/0113` says so in its own Consequences.

**What is deliberately not recorded, and why each:**

- **An operator opening a conversation they are a party to.** That is the ordinary work the product
  exists for; recording it would be a second copy of the busiest table's own traffic and a personal-data
  store in its own right.
- **The prior-conversation summary list beside `18-07`'s history read.** Two rows for one act a person
  experiences as one act is the doubling this item's own Scope warns against.
- **Refused attempts.** A caller denied by the permission check read nothing and has nothing to attest
  to. Watching for refusals is security monitoring, which this item's Out-of-scope defers.

**The open question is answered yes: a tenant sees AGO's own accesses.** The read filters by `site_id`
and never by actor kind. Withholding the platform owner's rows would make unreadable the one question a
tenant opens this table to ask.

**A trap this codebase now has three instances of.** Adding an endpoint broke Minimal API's metadata
build for *every* route in the affected files, inside integration tests that hand-roll a container — 35
failures, from one unregistered handler. `23-18` hit the identical thing this morning, and the endpoint
files already carried a comment describing it. Worth a mechanical guard eventually; noted here rather
than solved, because it is not this item's promise.
