# the operator's own lawful basis, and what they are shown at first sign-in

- **Stage**: 24
- **Status**: ready
- **Depends on**: `24-01` (the record), `24-02` (the version)
- **Decision**: **open — this item exists to close it.** `docs/adr/0076-*` settles the tenant and the
  visitor; the operator is the role it does not resolve.

## Goal

An operator signing in for the first time is processed on a basis somebody can name, and is shown
whatever that basis requires — no more, and no less.

## Why this is the hard one, stated precisely

`adr/0076` says AGO is controller for **its own account holders**, because they registered with AGO.
An operator did register with AGO. But the lawful basis that covers the *tenant* — art. 6 ч. 1 п. 5,
necessary to perform a contract **to which the subject is a party** — does not obviously reach the
operator, because the party to that contract is their employer, not them.

Three readings, and they lead to different products:

1. **The operator is covered by the tenant's contract** — as a beneficiary of it, or because the tenant
   instructs AGO to process their staff's data. Then no consent is collected, and what the operator
   needs at first sign-in is a notice, not a control. This also implies AGO is *processor* for operator
   data, which contradicts `adr/0076` as written and would need it superseded rather than edited.
2. **The operator consents on their own behalf.** Then the consent must be separate, specific and
   refusable — and refusing it cannot be made a condition of doing their job, which in practice makes
   this reading hard to operate honestly. A consent an employee cannot refuse without losing access to
   their work is the pattern the 1 September 2025 rules were written against.
3. **The tenant is the controller for its own staff and AGO the processor**, with the operator's basis
   being their employment relationship. Then this belongs in the processing instruction (`24-06`) and
   the operator sees nothing new at all.

Reading 3 is the one this item should test first, because it is the only one where nobody is asked to
agree to something they cannot decline.

Citations are for orientation, not legal advice. This is the question in the stage that most needs the
lawyer's answer, and it needs it **before** anything is built — a mechanism built on the wrong reading
is worse than none, because it looks like compliance.

## What is actually true today, verified

- An operator is created either by `RegisterSiteHandler` (the tenant's first) or by redeeming an invite
  (`OperatorInviteRedemptionRepository`). Neither shows a document.
- `23-02` established that `GET /api/v1/operators/me` is the one point a sign-in is observable
  server-side, and already writes there. If anything must happen at first sign-in, that is where it
  goes — and the shape already exists.

## Scope

- The reading is chosen, with the reasoning recorded as an ADR. If it contradicts `adr/0076`, that ADR
  is **superseded, not edited** — its original text stands, per the ADR rules.
- Whatever the chosen reading requires at first sign-in is built. If it requires nothing, the item ships
  the ADR and a test that first sign-in asks for nothing, so a later reader does not add a control on the
  assumption one was forgotten.
- `personal-data.md`'s "Who answers to whom" section is corrected if the reading changes it.

## Out of scope

- The tenant's own acceptance — `24-03`.
- The processing instruction's contents — `24-06`, though reading 3 would put the operator inside it.

## The exemption `24-01` leaves behind does not extend to this item

`24-01` built `RecordAcceptanceHandler`/`GetAcceptancesForSubjectHandler` with **no host endpoint**, and
both are listed in `TenantScopeExemptions` — correct for that item, because neither takes a `SiteId` and
no route maps to either, so there is nothing yet for a permission policy to sit behind.

This item builds one of the real entry points, and the exemption entries will already be in the file
when it starts. Two things follow, and neither is negotiable:

- **The subject comes from the validated principal, never from a parameter the caller supplies.** An
  endpoint that accepts a subject id and checks it matches is the same defect with an extra step.
- **The exemption covers the handler, not the route.** Adding an endpoint means the route carries its
  own authentication and authorisation, argued in this item rather than inherited from a line written
  when there was no route at all.

## Done when

- [ ] The reading is chosen and recorded as an ADR that names the alternatives and why each lost.
- [ ] `personal-data.md` and `authorization.md` agree with it.
- [ ] What the operator sees at first sign-in matches the reading — including the case where the answer
      is "nothing", which is asserted rather than assumed.
- [ ] If consent is collected, it is refusable and refusing it does not deny the operator their work.

## Open questions

- **The whole item.** This is deliberate: it is filed as an item rather than a decision so that the
  question has a number, an owner and an end state, instead of living in a conversation.
