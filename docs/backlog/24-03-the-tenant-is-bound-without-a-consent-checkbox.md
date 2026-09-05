# the tenant is bound by what they accept at registration — and it is not a consent checkbox

- **Stage**: 24
- **Status**: ready
- **Depends on**: `24-01` (the record), `24-02` (the version it points at)
- **Decision**: `docs/adr/0076-*` — AGO is **controller** for its own account holders

## Goal

A tenant registering with AGO accepts the agreement that binds them, that acceptance is recorded, and
nothing on that screen asks them to consent to processing they cannot refuse anyway.

## The thing this item exists to get right

**A consent checkbox here would be wrong, not merely unnecessary.**

AGO is the controller for the tenant's own data, and the lawful basis is `152-ФЗ` art. 6 ч. 1 п. 5 —
processing necessary to perform a contract to which the subject is a party. For everything the product
must do to deliver the service, **consent is not the basis and asking for it misrepresents what is
happening**: a consent that cannot be refused without losing the service is not freely given, and the
1 September 2025 rules name exactly that pattern — making use of a site conditional on a consent tick —
as a defect.

So the screen has two different things on it, and they must not be one control:

- **The agreement**, which the tenant accepts to enter into the contract. This is acceptance of terms,
  recorded per `24-01`.
- **Any consent that goes beyond contract necessity** — marketing being the obvious one — which is a
  **separate, unticked, refusable** control, and refusing it must not block registration.

Citations are for orientation, not legal advice; the text and the final call are `ago-business`'s and a
lawyer's, per `personal-data.md`'s own "What is not decided here".

## What is actually true today, verified

`RegisterSiteHandler` creates a site and its first operator from the token's claims. Nothing on that
path shows a document, and nothing records that anything was accepted.

## Scope

- Registration shows the agreement and records its acceptance against the registering subject.
- Anything beyond contract necessity is a separate control, **off by default**, and refusing it
  completes registration normally. If there is nothing beyond contract necessity today, say so and ship
  no control at all rather than an empty one.
- The published policy is reachable from the screen without signing in (`24-02`).

## Out of scope

- The agreement's text. `ago-business`.
- The operator's own basis — `24-04`. A tenant's first operator is created here, and it is tempting to
  fold the two together; they have different bases and different answers.
- The processing instruction the tenant gives AGO for their visitors' data — `24-06`.

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

## What `24-02` settled that this item must not undo

`adr/0114` put the **text** in the database so a lawyer's verdict is a change to data, never a code
change. That only holds end to end if **which documents this subject must accept is also data**.

The case to design for is real: a lawyer may conclude that an operator needs to accept nothing at all
(an employment relationship covering it), or that a tenant needs two documents where this item assumed
one. If the required set is a row, that verdict is a row change. If it is a condition in code, it is a
release — and the sequencing the author chose for this stage stops working at exactly the moment it
matters.

So: express *which documents are required, for which subject kind* as data this item reads, not as a
literal it hard-codes.

## Done when

- [ ] Registration records an acceptance of the agreement, with its version.
- [ ] No control on that screen asks for consent to processing the contract already requires.
- [ ] If a separate optional consent exists, it is unticked by default and refusing it still registers
      the tenant — proven by a test, since this is the half that quietly regresses.
- [ ] The policy is reachable from the screen by somebody with no account.

## Open questions

- **Is there anything today that is genuinely beyond contract necessity?** If not, this item ships one
  acceptance and no consent control, which is the better outcome and should be stated rather than
  treated as an omission.
