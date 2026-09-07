# a visitor uploads only after somebody agreed

- **Stage**: 23
- **Status**: ready — **two questions inside it, named below**
- **Depends on**: nothing. It changes the weighting of `23-75` and `23-76` rather than depending on them.
- **Decision**: the author's, 2026-09-07 — an operator ticks *«разрешаю пользователю отправлять файлы»*,
  and without it there is no upload control at all.

## Why this is the strongest abuse control on the table, not a UX preference

Everything else discussed for attachments **bounds the damage**: a per-conversation budget, a per-tenant
quota, a disk ceiling. This one **removes the vector**.

Today a visitor can upload before anybody has read their first word. Afterwards, an upload requires a
**human operator on our side to have agreed first**, in that conversation. An anonymous automated flood
becomes social engineering, performed separately against every conversation. That is a different order
of cost for an attacker, and it is cheaper for us to build than any of the quotas.

The author's own framing is also just true about behaviour: sending a file before anything has been
discussed is odd. The need arises after an agreement or real interest.

## The distinction that decides whether this works

**Hiding the icon is not the control.** The control is that `CreateAttachmentHandler` refuses to issue a
presigned slot for a conversation that carries no grant. The widget's missing icon is a consequence.

A gate implemented in the browser is a suggestion — `5-13` already learned this the expensive way about
size, where the application checked a declared number and the storage enforced nothing.

## Scope

- **A grant lives on the conversation**, given by an operator, revocable.
- **`CreateAttachmentHandler` refuses without it**, for the visitor side.
- **The widget shows no upload control** until it exists, and the refusal is not explained to the
  visitor in terms they could act on.
- **The operator's own uploads are unaffected.** They are an authenticated, paid identity; the
  per-conversation byte budget (`23-75`) still applies to both.

## The two questions, and they are the author's

**1. What happens out of hours?** Nobody is there to agree, and night is exactly when somebody wants to
send a photograph of a broken item. Three answers, each a different product:

- **A tenant-level default**, which the operator can then override per conversation in either
  direction. **Recommended**: a repair shop or a claims desk has photographs in every second
  conversation, and for them a per-conversation tick is a tax; a shop that fears junk leaves the default
  off. It keeps the abuse property exactly where a tenant wants it.
- **The auto-reply path grants it** when nobody is online. Keeps the night case working and gives an
  attacker a predictable, unattended way in.
- **No files out of hours.** Simplest, and it loses a real case.

**2. Does "a recognised client" grant it automatically?** The author asked whether uploads could open
once the visitor is known as a registered customer.

**As a control on its own it is weak, and this is worth being plain about.** Being "recognised" means
the visitor filled in the contact form (`23-58`), and filling that in is free and self-asserted. An
attacker types junk and is recognised. It raises the cost by one form submission.

**As a rule for granting automatically it is good**, and it composes with the operator's own switch
rather than replacing it. That is the shape to build if the answer is yes: the grant is the boundary;
recognition is one way it gets given.

## What it changes elsewhere

- **`23-76`'s quota still matters**, but for a different case: an operator who granted permission to
  somebody abusive, and a tenant abusing their own account. Not for the anonymous flood, which this
  closes.
- **`23-75`'s budget still matters** for the same narrowed reason.
- Neither should be dropped on the strength of this. A control that depends on a person can be talked
  around; a quota cannot.

## Done when

- [ ] A visitor cannot obtain an upload slot for a conversation with no grant, refused server-side.
- [ ] An operator can grant and revoke it in the conversation.
- [ ] The widget shows no upload control until then, and says nothing an attacker could use.
- [ ] The out-of-hours question is answered in the change rather than discovered at night.
- [ ] An operator's own uploads are unaffected.
