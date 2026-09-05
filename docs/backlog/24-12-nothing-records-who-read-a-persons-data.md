# reading a person's data leaves a record

- **Stage**: 24
- **Status**: ready
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

- [ ] The boundary-crossing reads listed above produce a durable record naming who, what and when.
- [ ] The record has a stated retention enforced by something that runs, per `adr/0057`'s own standard.
- [ ] `personal-data.md` has a row for it.
- [ ] `processing-instruction-facts.md` Element 6 moves this line out of "could not be produced".

## Open questions

- **Does a tenant see AGO's own accesses?** A platform owner reading a tenant's data is exactly the
  access a tenant most wants recorded, and exactly the one that is uncomfortable to show them. Decide
  it deliberately rather than by whichever query is easier to write.
