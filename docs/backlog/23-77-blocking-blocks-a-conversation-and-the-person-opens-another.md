# blocking blocks a conversation, and the person opens another

- **Stage**: 23
- **Status**: ready
- **Depends on**: `24-10` built what exists. `23-69` (closing as spam) meets it.
- **Found**: 2026-09-07, while answering the author's question about ban lists.

## What is actually true

`24-10` gave an operator `ConversationBlock`, and it is keyed on **`conversationId` + `siteId`**.
`IConversationBlockRepository.BlockAsync` takes a conversation and nothing about the person in it.

So a blocked visitor opens a new conversation and is not blocked. As *"close this and stop it
reaching me"* the feature works. As a **block on a person it is decorative**, and the name invites
everybody — us included — to believe it is more than it is.

That matters more now than when it shipped, because `23-69` adds *"close as spam"*, and the operator
who marks spam will reasonably expect the sender to stop arriving.

## What the right key is, and it is not an address

An IP is wrong in both directions here, and this is worth writing down because it will be proposed
again:

- **Too coarse to be safe.** Most Russian traffic arrives through a VPN exit shared by thousands of
  unrelated people. Blocking one address blocks strangers who did nothing.
- **Too cheap to be effective.** The one person it was aimed at changes exit for pennies.

So an address punishes the innocent reliably and the guilty barely. It is captured today for evidence
(consent and acceptance records) and used for no limit anywhere, which is the right place to leave it.

**The visitor is the honest key, and it is weak on purpose.** A visitor identity is free to obtain —
that is the design and it should stay. A block on it therefore is not a wall but a **cost**: the same
person has to start over, lose their history, and be met again. That is enough for the ordinary case,
which is a nuisance rather than an adversary.

## Scope

- A block reaches **the visitor on this site**, not one conversation: their next conversation on that
  site is blocked too.
- **It is the tenant's act, not ours.** They know who is bothering them; we do not. Nothing here is a
  platform-wide ban list.
- **It is reversible and recorded**, with who and when, exactly as `24-10` already does.
- **It stays scoped to one site.** A visitor blocked by one shop is not blocked at another. Anything
  else is a platform-level judgement about a person, which we are not in a position to make.

## Where this is likely to go wrong

- **Blocking is a judgement about a person, stored.** `personal-data.md` should say a visitor may be
  blocked, what that records, and how long it lasts.
- **The block must not be a message.** A visitor told "you are blocked" learns exactly what to change.
  Silence — their messages simply do not arrive at an operator — is both kinder and more effective, and
  it is what a shop expects.
- **Do not let this grow into a platform ban list by accident.** The moment a block is shared between
  tenants it becomes a different product with different obligations.

## Done when

- [ ] A block stops the same visitor's next conversation on that site, proven rather than reasoned.
- [ ] It is reversible, recorded, and scoped to one site.
- [ ] What the visitor experiences is decided rather than inherited.
- [ ] `personal-data.md` says what a block records and for how long.
