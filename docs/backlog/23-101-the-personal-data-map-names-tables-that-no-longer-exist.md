# the personal-data map names tables that no longer exist

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `22-30` fixed the *code* this document was wrong about and left the document
  half-corrected.
- **Found**: 2026-09-08, while building `22-30`.

## What is wrong

`docs/architecture/personal-data.md` has a row for **operators (AGO Calendar)** that still describes the
`operators` and `roles` tables. **`22-05` dropped both.** What holds that data now is
`role_assignment_projections`, and it is not the same shape: it is an outbox-fed projection, keyed by
tenant, with **no foreign key to `tenants` at all**.

`contact_visibility_projections` is in the same position and has **no row in the map whatsoever**.

## Why a stale row here is not a stale row anywhere else

**This document is the answer to "what personal data do you hold, and how is it removed."** It is the
thing a regulator, a customer's security questionnaire, or an incident response reads. A row naming a
dropped table is not untidy — it is an answer that is false.

And it already caused a real defect. The map called the operators table **cascaded**, which was true of
`operators` and is not true of `role_assignment_projections`. `22-30` found that a tenant erasure relying
on that cascade would have left **every operator's Keycloak subject id behind forever** — personal data
about a person, not about the tenant. The code is fixed. The sentence that misled it is only partly.

## What `22-30` already did, and what it left

`22-30` corrected the **"What removes it"** column for the four AGO Calendar rows, because its own change
made those answers true. It deliberately did not rewrite the rows themselves — that is a second promise,
and folding it in would have made a personal-data document change ride inside an erasure implementation.

## Scope

- **The operators row names the table that exists**, with its real shape: a projection, tenant-keyed,
  FK-free, removed by the erasure endpoint rather than by a cascade.
- **`contact_visibility_projections` gets a row of its own**, since it holds data and the map does not
  mention it.
- **Check the rest of the map against the schema**, not only these two. One row was wrong because a
  migration moved under it; nothing guarantees it was the only one.

## Where this is likely to go wrong

- **Do not fix only the two rows this item names.** The failure mode is a map that is accurate about
  whatever was last audited and stale everywhere else, which is indistinguishable from a correct map
  when read.
- **`22-32` is the reconciliation item** and is about the two databases agreeing at runtime. This is
  about a document agreeing with a schema; related in spirit, separate in fact.
- **Whether anything should *keep* this in step** is worth a sentence, even if the answer is no. A
  document that a migration can silently falsify will be falsified again.

## Done when

- [ ] Every AGO Calendar table holding personal data has a row naming the table that exists today.
- [ ] The map's claims about how each is removed match what the code actually does.
- [ ] Whether anything keeps this in step with the schema is answered, either way.
