# ADR-0088: A chat operator acts on a booking through a narrow, granted capability - not a second `Operator` row

- **Status**: Accepted
- **Date**: 2026-09-02
- **Extends**: `adr/0027` (Calendar's own separate `Operator`, never the same database row as Chat's)
- **Resolves**: the tension `20-08`'s own item file names between `adr/0027` and `adr/0065` ("the
  operator may always intervene")

## Context

`adr/0065` lets a visitor start a booking inside a chat conversation, and lets a chat operator
intervene at any moment. `adr/0027` says AGO Calendar defines its own `Operator`, in its own
repository, with its own table, never the same row as `Ago.Chat.Domain.Operator` — the two unified
only through Keycloak, each product resolving the same `sub` against its own table.

Together they leave one thing unanswered: a chat operator looking at a booking card in a conversation
they are handling. If they can act on it — confirm, reschedule, cancel — Calendar is authorising an
identity with no `operators` row of its own. If they cannot, the conversation is a dead end exactly
when a visitor needs a human most, which is the opposite of what `adr/0065` promises.

`20-08`'s own item file named three shapes and chose none. The author weighed them directly:

- **Read-only.** Cheapest, but the conversation becomes a dead end exactly when the operator's
  presence should matter most — rejected as a real usability cost, not a hypothetical one.
- **Explicit account linking** — a tenant links a chat operator's identity to a real Calendar
  `Operator` row, once, through Keycloak, reapplying `adr/0027`'s own mechanism a second time. **The
  author's own words**: "engineering-honest" — full accountability, no coarse capability, every
  action traceable to a real Calendar operator identity. Rejected anyway, for a reason worth recording
  precisely because it is not a technical one: a real tenant is a shop owner setting up their own
  business's booking, not this project's own author, and asking them to understand and perform an
  extra account-linking step to get a chat operator to be able to confirm a booking is a real
  onboarding cost this product cannot afford to impose for a capability that should be self-evident.
- **A narrow, granted capability** — chosen.

## Decision

**A chat operator acts on a booking through one narrow capability, granted to their own Keycloak
`sub`, checked by Calendar at the moment of the action — never by creating or touching a Calendar
`Operator` row.**

Concretely: the chat-side module contract already carries structure Chat itself never interprets
(`adr/0061`, `adr/0065`, `adr/0077`) — a booking action originating in a conversation already reaches
Calendar carrying the acting operator's own Keycloak `sub`, the same way `20-07`'s own module task
handlers already resolve identity for the booking claim itself. This decision adds nothing new to that
transport. What it adds is what Calendar does with the `sub` once the request arrives: it checks a
narrow grant — "may this `sub` act on bookings that reached Calendar through the chat module" — kept
entirely separate from `Role`/`RoleAssignment`/`Operator`, the machinery `20-12` built for Calendar's
own operators. **This has to be a genuinely new, small concept, not a reuse of `20-12`'s own
tables** — every one of those is keyed on an `Operator` row, and `20-08`'s own Done-when forbids a
chat-originated action from ever creating or mutating one. A grant here names a `sub` and a
capability string directly; it is never promoted into an `Operator`.

**What of `adr/0027` still holds, verbatim**: Calendar still defines its own `Operator`, in its own
table; a chat operator never becomes one; the two products' operator tables remain exactly as disjoint
as `adr/0027` requires. The two identities are still unified only through Keycloak — the `sub` is the
only thing either product ever agrees on.

**What this decision adds, that `adr/0027` did not anticipate**: a capability narrower than a full
operator identity, granted to a `sub` Calendar has never seen before and may never see again outside
this one action. `adr/0027` assumed the two products' identities would either stay fully separate or
be fully linked; this is a third, deliberately thinner relationship — enough to act, not enough to be
an operator.

## Consequences

- **Positive**: zero setup cost for a real tenant. A shop owner gets a chat operator who can confirm a
  booking without performing any linking step — matching the author's own stated priority over the
  "engineering-honest" alternative.
- **Positive**: `adr/0027`'s separation stays intact in the strongest sense — there is no code path by
  which a chat-originated action can create a Calendar `Operator` row, because the mechanism that
  checks the capability never touches that table at all.
- **Negative, named plainly, and the actual price of choosing this over full linking**: the audit
  trail inside Calendar for a chat-originated action is coarser. Calendar can prove "a `sub` holding
  this capability confirmed this booking," not "this specific, provisioned Calendar operator, with
  their own accountability history, did." If a real compliance need for finer-grained, per-person
  history on chat-originated actions appears later, this decision does not provide it, and the
  explicit-linking shape (rejected here for onboarding-cost reasons) would need to be revisited then —
  not as a failure of this decision, but as the trade the author chose to accept for now.
- **Negative**: a genuinely new Domain concept is required — the capability grant cannot reuse `20-12`'s
  `Role`/`RoleAssignment`, on purpose, so this is real new work, not a flag to flip.

## Alternatives considered

See "Context" above — both rejected alternatives are recorded there, with the actual reasons the
author gave for rejecting each, since the reasoning (usability cost; onboarding cost) is the part
worth preserving, not just the fact that they were rejected.
