# nothing makes a document required in any deployment

- **Stage**: 24
- **Status**: ready
- **Depends on**: `24-02` (documents and versions) and `24-03` (the required-documents table and the
  registration path that reads it). Both shipped.
- **Found**: 2026-09-05, while landing `24-03`. Filed under CLAUDE.md rule 14 — the remainder of a
  finished item gets its own number rather than sitting inside it.

## Goal

A platform owner can say which documents a subject must accept, without writing SQL by hand.

## What is actually wrong today, verified

`24-03` built the mechanism and it is correct. It is also **inert**:

| | |
|---|---|
| `required_documents` | ships **empty** — the migration inserts no row |
| an endpoint to add a row | **none** — `24-03`'s scope did not include one |
| `RegisterSiteHandler` | reads the table, finds nothing, records nothing |
| the registration screen | shows no agreement link, because the list it reads is empty |

So `24-03`'s own title — *the tenant is bound by what they accept at registration* — is **not true in
any deployment today**, and cannot be made true except by an `INSERT` typed against production.

The same is true one step earlier: `24-02` shipped `POST /api/v1/owner/documents` with no surface to
call it from, so there is no published document to require either.

**Neither is a defect in those items.** `24-03` was right not to seed a row — choosing which document,
and whether one is enough, belongs to `ago-business` and a lawyer, not to an implementation. What is
missing is the mechanism that lets that choice be made once it exists.

## Scope

- **An owner surface for `required_documents`**: list what a subject kind must accept, add an entry,
  remove one. The platform owner is the only caller — `RequirePlatformOwner`, the same gate `24-02`'s
  publish already uses.
- **A surface for publishing a document version**, or a written statement that `curl` against
  `24-02`'s existing endpoint is the intended procedure and where it is documented. Shipping a
  required-documents editor while publishing stays a hand-rolled HTTP call would move the gap rather
  than close it.
- **Removing an entry must not invalidate acceptances already recorded.** `adr/0111` keeps an
  acceptance record whatever happens to its subject; the same must hold when the requirement itself is
  withdrawn. A tenant who accepted v3 accepted it.
- **`processing-instruction-facts.md` gains the honest line**: what a tenant is bound by today, and
  from when.

## Out of scope

- **Choosing which documents are required, or writing them.** That is the whole point of making it
  data — the choice is `ago-business`'s and a lawyer's, and this item builds the surface, never the
  content.
- **`24-04` and `24-05`'s own subjects.** They decide what an operator and a visitor must accept;
  this item only makes any such decision expressible.
- **A markup language for document bodies.** `24-02` deliberately left that open and it stays open.

## Done when

- [ ] A platform owner can add and remove a required document for a subject kind, without SQL.
- [ ] Publishing a version has a surface, or a runbook stating plainly that the API call is the
      procedure and how to make it.
- [ ] Removing a requirement leaves existing acceptance records untouched, asserted by a test.
- [ ] A registration in a deployment with one required document records an acceptance — proven
      end to end rather than at the handler, since the gap this item closes is exactly the one that
      handler-level tests could not see.
