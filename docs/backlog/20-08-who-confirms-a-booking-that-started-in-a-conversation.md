# Who confirms a booking that started in a conversation

- **Stage**: 20 (and 12/14 — it is an authorisation question before it is a Calendar one)
- **Status**: blocked on `20-07`
- **Depends on**: `20-07` — the contract and the transport. This question only becomes answerable once
  a booking can actually originate inside a conversation.
- **Tension with**: `adr/0027`, deliberately and explicitly.

## The question

`adr/0065` lets a visitor start a booking inside a chat conversation, and lets an operator intervene
at any moment. `adr/0027` says AGO Calendar defines **its own `Operator`**, in its own repository, with
its own table, and that it is **never the same database row** as `Ago.Chat.Domain.Operator` — the two
unified only through Keycloak, each product resolving the same `sub` against its own `operators` row.

Both are right on their own. Together they leave one thing unanswered: **a chat operator looking at a
booking card in a conversation they are handling.** If they can act on it — confirm, reschedule,
cancel — then Calendar is authorising an identity that has no `operators` row of its own in Calendar.
If they cannot, the operator is holding a conversation about a booking they are powerless to change,
and `adr/0065`'s "the operator may always intervene" is true of the message and false of the thing the
message is about.

## Why this is its own item and not a paragraph in `20-07`

It is not a contract-shape question. `20-07` can ship a working booking flow with **no** operator
actions on the card at all, and that flow would be honest and useful. This item decides an
authorisation policy that spans two products and touches a recorded decision, which is exactly the
kind of thing this project turns into an ADR rather than an implementation detail.

It also cannot be decided by reasoning alone: `authorization.md` still carries an open decision of its
own (`CLAUDE.md`'s own index calls it "current gap, open decision"), and this question is downstream of
it.

## The shapes worth weighing

- **Calendar grants nothing.** The card is read-only for a chat operator; acting on it means opening
  Calendar's own console. Cheapest, and honest about the product split — at the cost of making the
  conversation a dead end exactly when it matters.
- **Calendar grants a narrow, module-scoped permission**, declared by the module and stored by Chat as
  an opaque string. Keeps `adr/0027`'s two rows separate — the chat operator never becomes a Calendar
  `Operator`; Calendar simply accepts a named capability for a Keycloak `sub` it recognises.
- **The tenant links the two identities explicitly**: one person, two `operators` rows, one in each
  product, connected only through Keycloak — exactly `adr/0027`'s own mechanism, applied a second
  time. Preserves the ADR literally, at the cost of the tenant having to do something.

None of these is chosen here. Naming them is the point: the item exists so the tension is not
discovered by whoever implements the card and resolved by whatever was easiest that afternoon.

## Done when

- [ ] An ADR decides it, states which of `adr/0027`'s guarantees still hold verbatim, and — if any
      does not — amends `adr/0027` rather than quietly contradicting it.
- [ ] A chat operator's authority over a booking card is proven by a test in **both** directions: what
      they may do, and what they are refused.
- [ ] `authorization.md` is updated, since this is the second product to need an answer from it.
- [ ] No path exists by which acting on a card in Chat creates or mutates a Calendar `Operator` row as
      a side effect — the failure mode `12-04` already caught once, in a different disguise.

## Open questions

- **Whether the same answer covers the reverse direction**: a Calendar operator replying to the
  visitor through the conversation the booking came from. Probably yes, probably by the same
  mechanism, but the asymmetry has not been examined.
- **What a visitor may do to a booking from the conversation** once an operator is involved. Chat's
  own escape-to-a-human rule says the module cannot lock the visitor out of reaching a person; it says
  nothing about whether the visitor can still cancel from the card.
