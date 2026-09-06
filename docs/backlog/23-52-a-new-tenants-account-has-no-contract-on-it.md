# a new tenant's account has no contract on it, and nothing said so

- **Stage**: 23
- **Status**: ready
- **Depends on**: `24-02` (documents and versions) and `24-01` (acceptance records) — both built.
- **Decision**: the author's, 2026-09-06 — *«они должны автоматически создаваться при регистрации
  теннанта»*. Found by the author reading `23-37` and noticing it had assumed the wrong audience.

## What is actually true

A tenant registers today and gets an account with **no agreement on it at all.** No contract, no
security-compliance statement, nothing they accepted and nothing we can point at afterwards.

`24-02` built documents and versions. `24-03` built `required_documents`, which decides what binds
which subject kind — and it **ships empty in every deployment** (`24-16`), so a registration records
zero acceptances and succeeds. `24-05` made *visitors* accept a *tenant's* text.

Every one of those is about the tenant's words to their visitors. **Nothing is about our words to the
tenant**, and until the author said so out loud, nothing in this queue was either.

## Why this is a launch item and not tidiness

`docs/compliance-checklist.md` is kept until the first real tenant. A tenant is a **counterparty**:
the thing that makes them one is an agreement, and the thing that makes an agreement usable is a
record of who accepted which version and when.

We already hold the machinery for exactly that, built for somebody else's documents. What is missing
is that our own are not on the account.

And `25-04`'s AI add-on already assumes this shape works — its whole design is *the tenant accepts a
document before the module turns on*. That is the same mechanism pointed at a tenant, which is what
this item makes ordinary rather than special.

## Scope

- **A registration produces the account's documents**, not a screen that offers them later. Which
  documents is data (`adr/0114`), so a deployment with none configured produces none — and says so
  rather than failing.
- **Acceptance is recorded with the version accepted**, through `24-01`'s existing records, so the
  answer to *"what did they agree to"* is a row rather than an argument.
- **The tenant can read what is on their account**, current and superseded — the same read `23-37`
  builds for their own documents, pointed at ours.
- **`required_documents` is what decides**, which means this item and `24-16` meet: `24-16` is about
  nothing making a document required anywhere, and this is the first thing that genuinely needs one.

## The questions inside it, and they are the author's

- **What is in the contract.** AGO writes it (the same boundary `25-04` settled: our words to our own
  counterparty are ours to write; `16-04` forbids writing the *tenant's* words to *their* visitors).
  A lawyer reviews it before it is ever published. **A draft is not in this item on purpose** — it
  would be a legal text written by an engineer sitting in a queue file looking settled.
- **What happens to a tenant who registered before this.** Existing accounts have no acceptance. Ask
  them at next sign-in, backfill nothing, or treat the deployment as pre-launch and ignore it? The
  third is honest today and stops being honest the day a real tenant exists.
- **Whether refusing is possible.** If a registration requires accepting, refusing means no account —
  which is a product decision about the signup flow, not a technical one.

## Done when

- [ ] A newly registered tenant's account carries the deployment's own documents, with an acceptance
      record naming the version.
- [ ] A deployment that configures none produces none, and that is visible rather than silent.
- [ ] The tenant can read what is on their account, including a superseded version.
- [ ] `compliance-checklist.md` says whether this closes any of its lines.

## Out of scope

- The tenant's own documents to their visitors — `23-37`, which this was carved out of.
- Documents from a tenant to their operators, which have no acceptance path until `24-04`.
- Writing the legal text. That is a lawyer's, and the item says so rather than pretending otherwise.
