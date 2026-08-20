# ADR-0016: Granular permissions (RBAC), scoped per tenant, as the authorization model

- **Status**: Accepted
- **Date**: 2026-08-21
- **Stage**: 1

## Context

`authorization.md` named two candidate shapes and left the choice open, with a trigger: Stage 1's
`SendMessage` and `GetConversationHistory` need *some* check beyond "right tenant," which pushes the
question from theoretical to blocking. The two candidates:

1. **Roles + tenant scoping** — coarse `Operator`/`Admin` roles inside a `site_id`. Cheap, matches
   what the actor table already implies, and is enough for everything Stage 1 actually needs.
2. **Granular permissions (RBAC)** — named permissions (`conversation:read`, `conversation:assign`,
   `site:configure`, ...) bound to roles, roles assigned per tenant. The more standard, reviewer-
   recognizable pattern; more structure than a single-operator demo strictly needs today.

The author chose to decide this now rather than defer it, and chose RBAC — explicitly accepting the
"speculative structure, one caller" risk `clean-architecture.md` warns about, in exchange for having
the recognizable pattern in place before Stage 5's console makes it real, instead of retrofitting it
under a deadline then.

## Decision

- A **`Permission`** is a named, resource:action string constant (`conversation:read`,
  `conversation:send`, `conversation:assign`, `site:configure`, ...), defined in `Ago.Chat.Domain` —
  it is domain vocabulary (what actions this system has), not an infrastructure concern.
- A **`Role`** is a named set of permissions, scoped to one `site_id` — a role is tenant-local, so two
  sites' "Operator" roles are independent assignments even though Stage 1 gives them the same
  permission set by convention.
- `Operator` carries one or more role assignments, within its own site.
- **The check happens in `Application`**, never in `Domain` and never at the transport edge
  (`clean-architecture.md`, `authorization.md`): a handler resolves the caller's permissions for the
  relevant site/resource and checks membership *before* invoking any domain method. `Domain` keeps
  enforcing its own business invariants (e.g., "only the assigned operator can be this conversation's
  operator-side author") — that is a fact about the conversation, not an authorization decision, and
  the two checks stay separate even though both gate the same use case.
- **`Visitor` stays outside the role system.** A visitor's signed token is a single-purpose
  capability scoped to one conversation, not a role — `authorization.md` already named this as
  adequate regardless of which operator-side model won.
- **Stage 1's concrete instantiation is deliberately minimal**: exactly one built-in role
  (`"Operator"`) with a fixed permission set (`conversation:read`, `conversation:send`, and the
  trivial `conversation:assign` from `1-01`'s direct-join). It is granted at operator creation
  (`1-05`'s seed script), with no role-management surface yet. Custom per-tenant roles and a UI to
  manage them are Stage 5 console work — this ADR fixes the *model* they will manage, not the
  management surface itself.

## Consequences

- Real permission checks exist from Stage 1 onward — `authorization.md`'s "must not be trusted to
  have checked this until the model is decided" is resolved for the operator side.
- Cost, accepted knowingly: for a solo-operated portfolio system with one seeded operator, this is
  more structure than the immediate need — a `Role`/`Permission` table and a resolution step for what
  a single hardcoded role already answers. The trade is legibility to a reviewer now, against a
  YAGNI violation the project's own conventions would otherwise flag.
- Stage 5's console gets a model to build a management UI against, not a redesign — the risk that
  trade was meant to avoid.
- **Not built now, and must not be mistaken for done**: who can grant/revoke roles, custom per-tenant
  role definitions, any UI or API for managing them. Stage 1 ships the check and exactly one role.
- `authorization.md` is updated in this change to record the model as decided; the operator-
  *authentication* question (who issues the token the permission check reads its role claims from)
  stays open and unrelated — `1-06`'s dev-only stub answers it for Stage 1, OIDC for Stage 5.

## Alternatives considered

- **Roles + tenant scoping** — simpler, matches the actor table as already written, costs nothing
  extra to build for Stage 1's actual two checks. Rejected by explicit author decision: correctness at
  a scale the project does not have yet was weighted over YAGNI, to avoid a Stage-5 redesign under
  pressure.
- **Ad-hoc per-handler checks, no named model** — what `authorization.md` described as the status quo
  becoming untenable at exactly this point. Rejected outright; it is the thing this ADR exists to stop.
