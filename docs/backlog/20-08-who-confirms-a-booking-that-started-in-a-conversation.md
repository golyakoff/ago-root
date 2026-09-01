# Who confirms a booking that started in a conversation

- **Stage**: 20 (and 12/14 — it is an authorisation question before it is a Calendar one)
- **Status**: ready — decided 2026-09-02, `adr/0088`. Queued behind `15-09` (unrelated repartitioning
  work already in flight; picked up next once it lands, not blocked on it in substance)
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

**Correction, 2026-09-02**: this item's own claim above was checked before deciding and is stale.
`authorization.md`'s own "Done when nothing here is open anymore" checklist is now fully `[x]` — every
item it once tracked has shipped. The file's one genuinely open item (a console UI for managing custom
per-tenant roles in `ago-console`) is real but unrelated to this question; nothing in that file names
or blocks the chat-operator/Calendar-identity tension this item is actually about. This question was
never downstream of an existing open decision — it is a new one, raised for the first time by `20-08`
itself. Decided below without waiting on anything else.

## Relation to `21-02`

`21-02` merges the two products' operator queues into one screen. This item is narrower and comes
first: it asks what a chat operator may *do* to a booking, not where they see it. A unified queue that
shows a booking nobody in that screen is allowed to act on would be a worse outcome than two queues,
so the authority question is the one to settle before the presentation question.

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

## Decided (2026-09-02): the narrow granted capability — `adr/0088`

The author weighed all three directly. Explicit linking (the third shape) was named "engineering-honest"
in the same breath it was rejected: full accountability, every chat-originated action traceable to a
real Calendar operator — but it asks a real tenant, a shop owner, to understand and perform an account-
linking step before a chat operator can do something as ordinary as confirm a booking. That onboarding
cost was judged real and unacceptable, not hypothetical. Read-only was rejected for the usability cost
already named above. The narrow capability wins on both fronts: no `Operator` row, no linking step, no
onboarding cost — see `adr/0088` for the full reasoning and the one real cost this choice accepts (a
coarser audit trail than full linking would give).

**One structural consequence worth flagging before implementation, not discovered during it**: the
capability grant cannot reuse `20-12`'s `Role`/`RoleAssignment` tables — every one of those is keyed on
an `Operator` row, and this item's own Done-when below forbids a chat-originated action from ever
creating or mutating one. A new, small, separate concept is required (a `sub` + capability string,
checked only on the chat-originated path). This is real new Domain work, not a flag to flip.

## Done when

- [x] An ADR decides it, states which of `adr/0027`'s guarantees still hold verbatim, and — if any
      does not — amends `adr/0027` rather than quietly contradicting it. — `adr/0088`, 2026-09-02.
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
