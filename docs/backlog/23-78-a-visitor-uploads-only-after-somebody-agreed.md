# a visitor uploads only after somebody agreed

- **Stage**: 23
- **Status**: done — `ago-chat#251`, `ago-widget#77`, `ago-console#193`
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
- **A tenant-level default** (off, per the author's own recommendation above — a tenant who wants
  uploads open by default turns it on) that seeds the per-conversation grant, which an operator can
  then still override in either direction for one specific conversation.
- **`CreateAttachmentHandler` refuses without it**, for the visitor side.
- **The widget shows no upload control** until it exists, and the refusal is not explained to the
  visitor in terms they could act on.
- **The operator's own uploads are unaffected.** They are an authenticated, paid identity; the
  per-conversation byte budget (`23-75`) still applies to both.
- **No automatic grant from "recognised client" status** — recognition (`23-58`'s contact capture) is
  free and self-asserted, and the author's own answer above is that it never grants on its own.

## The two questions, and they are the author's — both answered 2026-09-09

**1. What happens out of hours?** Nobody is there to agree, and night is exactly when somebody wants to
send a photograph of a broken item. Three answers, each a different product:

- **A tenant-level default**, which the operator can then override per conversation in either
  direction. **Recommended, and decided.** a repair shop or a claims desk has photographs in every second
  conversation, and for them a per-conversation tick is a tax; a shop that fears junk leaves the default
  off. It keeps the abuse property exactly where a tenant wants it.
- **The auto-reply path grants it** when nobody is online. Keeps the night case working and gives an
  attacker a predictable, unattended way in. Rejected.
- **No files out of hours.** Simplest, and it loses a real case. Rejected.

**2. Does "a recognised client" grant it automatically?** The author asked whether uploads could open
once the visitor is known as a registered customer. **Decided: no.** Only an operator's own manual
grant, per conversation or via the tenant-level default above — never automatically from recognition
alone.

**As a control on its own it is weak, and this is worth being plain about.** Being "recognised" means
the visitor filled in the contact form (`23-58`), and filling that in is free and self-asserted. An
attacker types junk and is recognised. It raises the cost by one form submission — not enough on its
own, which is exactly why the answer above is no.

## What it changes elsewhere

- **`23-76`'s quota still matters**, but for a different case: an operator who granted permission to
  somebody abusive, and a tenant abusing their own account. Not for the anonymous flood, which this
  closes.
- **`23-75`'s budget still matters** for the same narrowed reason.
- Neither should be dropped on the strength of this. A control that depends on a person can be talked
  around; a quota cannot.

## Done when

- [x] A visitor cannot obtain an upload slot for a conversation with no grant, refused server-side.
- [x] An operator can grant and revoke it in the conversation.
- [x] A tenant-level default (off) seeds the per-conversation grant, overridable by an operator either
      way for one conversation — the out-of-hours case this item asked about, built rather than
      discovered at night.
- [x] The widget shows no upload control until then, and says nothing an attacker could use.
- [x] Recognised-client status alone never grants it — only an operator's own manual grant or the
      tenant default above.
- [x] An operator's own uploads are unaffected.

## Outcome

`ago-chat#251`, `ago-widget#77`, `ago-console#193`. `CreateAttachmentHandler` refuses the visitor-side
presigned slot without a grant, checked before the rate limiter. The grant is two mapped properties on
`Conversation` (`AttachmentUploadGrantedAt`/`GrantedBy`), written through a new
`IConversationAttachmentUploadGrantRepository` (raw SQL, mirroring `IConversationBlockRepository`) to
avoid racing the aggregate's own `xmin` against a visitor mid-typing. `WidgetConfig
.AllowAttachmentUploadsByDefault` (off by default) seeds new conversations; a new `Permission
.ConversationAttachmentUploadGrant` sits in the Operator role (routine per-conversation judgement, not
a moderation act), and grant/revoke also checks the caller is the operator currently assigned. No
separate audit table — current-state attribution is what the Done-when asks for. One migration: three
additive columns. Widget hides the attach icon until `VisitorJoinResult.hasAttachmentUploadGrant` says
otherwise, refreshed on reconnect. Console gets a `SeatToggleButton`-shaped grant/revoke toggle riding
the existing `/queue` response. A real, unrelated bug was found and fixed along the way: two new error
codes had no entry in `ErrorExtensions.ToProblem`'s switch and fell through to a 500 default.

**Named gaps, not silently closed**: `ago-deploy/seed/create-demo-tenant.sh`'s own restatement of the
Operator permission list was not updated (no worktree for that repo — the same already-acknowledged
gap other permissions carry); no live push for an already-connected, never-reconnecting visitor when
an operator toggles the grant mid-session (narrowed via reconnect refresh, not closed — the same gap
block/unblock already accepts); the console's "who granted it" caption never resolves to an operator's
display name.
