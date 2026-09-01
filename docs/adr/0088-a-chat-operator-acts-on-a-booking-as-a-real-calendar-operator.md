# ADR-0088: A chat operator acts on a booking as a real Calendar `Operator`, invited by email

- **Status**: Accepted
- **Date**: 2026-09-02
- **Applies**: `adr/0027`'s own mechanism a second time — the two products' operator rows stay separate
  and are unified only through Keycloak. Nothing in `adr/0027` is amended.
- **Resolves**: the tension `20-08`'s own item file names between `adr/0027` and `adr/0065` ("the
  operator may always intervene")

## Context

`adr/0065` lets a visitor start a booking inside a chat conversation, and lets a chat operator
intervene at any moment. `adr/0027` says AGO Calendar defines its own `Operator`, in its own
repository, with its own table, never the same row as `Ago.Chat.Domain.Operator` — the two unified
only through Keycloak, each product resolving the same `sub` against its own table.

Together they leave one thing unanswered: a chat operator looking at a booking card in a conversation
they are handling. If they can act on it, Calendar is authorising an identity with no `operators` row
of its own. If they cannot, the conversation is a dead end exactly when a visitor needs a human most.

`20-08`'s own file named three shapes: read-only, a narrow granted capability, or explicit account
linking.

## The reasoning that changed, recorded because the first answer was wrong

**This ADR was first written choosing the narrow granted capability**, on the argument that it costs a
real tenant nothing to set up while explicit linking asks a shop owner to understand and perform a
linking step. The author challenged that directly: *if a table is needed either way, the cheapness
argument for the capability disappears — do the honest thing.*

Checking it against the real code showed the challenge was right, and the original argument contained
a hole:

- **The capability's "no setup cost" was only true if the grant were blanket** — every chat operator
  automatically able to act on every booking. If a grant is deliberate, somebody must grant it, which
  means an endpoint and a screen: exactly the cost the capability was supposed to avoid.
- **The capability needs genuinely new machinery.** `20-12`'s `Role`/`RoleAssignment`/`PermissionChecker`
  are all keyed on an `Operator` row, and `20-08`'s own Done-when forbids a chat-originated action from
  creating one — so a capability grant would need its own parallel table, its own check, and its own
  screen, none of which could reuse what `20-12` already built.
- **Explicit linking reuses everything.** `Operator.ExternalSubjectId` and `LinkExternalIdentity`
  already exist. `OperatorIdentityClaimsTransformation` already resolves a Keycloak `sub` to a Calendar
  operator on every authenticated request. `Role`, `RoleAssignment`, `PermissionChecker` and the
  console's own Access screen were all built by `20-12`. The single missing piece is that
  `Operator.Create` has exactly one caller today — `RegisterTenantHandler`, for the account owner —
  so there is no way to add a *second* operator to a tenant at all.

So the shape that looked more expensive is the cheaper one, and it is also the one with real
accountability. The onboarding objection stands, but it is a **user-interface** problem, not an
architectural one — and it is solved below rather than designed around.

## Decision

**A chat operator who acts on a booking is a real `Ago.Calendar.Domain.Operator` row, created
deliberately in advance by the tenant, resolved from the same Keycloak identity they already sign in
with.** `adr/0027`'s mechanism, applied a second time, exactly as that ADR anticipated.

**The tenant never sees "linking".** The Calendar console's own Access screen (built by `20-12`) gains
one control: *invite a colleague*, taking a display name and an email address. That creates an
`Operator` row with no `ExternalSubjectId` yet, in an invited state. The first time that person signs
into the Calendar console with their existing account, `OperatorIdentityClaimsTransformation` finds no
operator for their `sub`, falls back to matching the email claim against invited rows, and calls
`LinkExternalIdentity` — after which the `sub` resolves directly, forever. This is the ordinary
invite-a-teammate flow every SaaS product already teaches its users; it introduces no concept a shop
owner has to learn, and the words "link", "subject" and "second account" appear nowhere in it.

**Linking happens on sign-in, never on acting.** `20-08`'s own Done-when forbids a chat-originated
action from creating or mutating a Calendar `Operator` row as a side effect, and this respects that
literally: the row is created by a deliberate invite, and the `sub` is attached by a deliberate
sign-in. A booking action that arrives from a `sub` with no operator row is **refused**, not
auto-provisioned.

## Consequences

- **Positive**: no new Domain concept at all. Roles, permissions, checks, the claims transformation and
  the Access screen are all reused as-is. The whole change is one create-operator use case, one
  endpoint, one email-fallback branch in the claims transformation, and one form on an existing screen.
- **Positive**: full accountability. Every chat-originated action on a booking is attributable to a real
  Calendar operator with their own role assignments and their own history — the property the capability
  shape would have given up.
- **Positive**: `adr/0027` is applied, not amended. The two operator tables stay disjoint; Keycloak
  stays the only thing both products agree on.
- **Negative, and the real friction this accepts**: an invited person must sign into the Calendar
  console **once** before they can act on booking cards from the chat console. Until they do, their
  `sub` resolves to nothing and their action is refused. The console shows invited-but-not-yet-joined
  as a visible state so the owner can see why, but the first-time flow genuinely has this step. A
  smoother path — the chat console detecting the refusal and offering "activate your booking access" —
  is a real improvement and is deliberately left out of scope rather than half-built.
- **Negative**: the email match is only as good as the email typed. If the owner types an address that
  differs from the person's Keycloak email, the link silently never happens and the person sees "you
  are not an operator here". Mitigated by showing invite status on the Access screen, not by making the
  match cleverer.
- **New personal data**: `operators` (Calendar) gains an invited-email column — a direct identifier
  where that table previously held only a display name. `personal-data.md`'s own row for it needs
  updating in the same change.

## Alternatives considered

- **Read-only card.** Rejected for the usability cost: the conversation becomes a dead end exactly when
  the operator's presence should matter most, which is the opposite of what `adr/0065` promises.
- **A narrow granted capability, checked per action, with no `Operator` row.** Chosen first, then
  rejected on the author's own challenge — see "The reasoning that changed" above. It needs more new
  machinery than the shape it was supposed to be cheaper than, and it buys a weaker identity model.
- **Blanket capability — every chat operator may act on every booking, no grant at all.** The only
  genuinely zero-setup option, and rejected on that basis rather than despite it: it is a real
  authorization decision (every chat operator gains write access to every booking) made by omission
  rather than by choice, and the tenant would have no way to express "this operator handles chat only".
