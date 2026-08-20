# Authorization: current state and the open decision

## Status

**No authorization model is chosen yet.** This document exists so that gap is a documented,
deliberate "not yet" rather than something a future session discovers by accident. It records what
already exists (identification and tenant scoping), what does not (an actual authorization model),
and the working direction for one specific piece (operator authentication) - captured here rather
than in an ADR because ADRs are for decisions made, and this one has not been.

Do not read anything in Stage 0-4 as authorized. `visitor` and `operator` tokens *identify* a
principal and *scope* it to a `site_id`; nothing today asks "is this principal allowed to do this
specific thing." A visitor token proves "this is the same browser that opened this conversation," not
"this browser may read conversation X." Handlers must not be trusted to have checked this until the
model below is decided and its checks exist in `Application` (`clean-architecture.md`: auth decisions
are application code, never edge or infrastructure - `edge.md`, `naming-and-structure.md`).

## The three actors, and what's already true about each

| Actor | Identification today | Authorization today |
|---|---|---|
| **Visitor** | Signed token (cookie/localStorage), scoped to one `site_id`, issued by `Ago.Chat.Api` on first contact (`vision.md`, `realtime.md`) | None beyond the token's `site_id` claim |
| **Operator** | `/hubs/operator` expects a JWT (`realtime.md`); *who issues it is the open question below* | None beyond whatever the JWT's `site_id` claim says |
| **Webhook/API integrations** | Outbound only today: deliveries to a tenant's endpoint are HMAC-signed (`adr/0013`) so *they* can verify *us*. There is no inbound integration API yet, so "how does a third party authenticate to AGO Chat" is entirely unplanned | N/A - does not exist |

`site_id` scoping is the one piece already load-bearing everywhere (`vision.md`: "multi-tenant from
day one"). Every candidate model below keeps it; none of them replace it.

## Open question: the authorization model

Two candidate shapes, deliberately left undecided:

1. **Roles + tenant scoping.** `Operator` / `Admin` roles inside a `site_id`; a visitor's token is a
   single-purpose capability scoped to its one conversation. Coarse-grained, cheap to reason about
   and to test, and it is what the current actor table already implies. Risk: "Admin" tends to grow
   into a junk drawer of unrelated permissions as features accrete.
2. **Granular permissions (RBAC).** Named permissions (`conversation:read`, `conversation:assign`,
   `site:configure`, ...) bound to roles, roles assigned per tenant. More correct at real
   organizational scale, and a recognizable pattern to a reviewer. Risk: for a solo-operated portfolio
   system, the permission table is speculative structure with no second consumer to validate its
   shape - exactly the premature-generalization failure `clean-architecture.md` warns about.

Neither is chosen. Decide with an ADR when there is a concrete use case that needs the answer -
realistically Stage 1 (`SendMessage`, `GetConversationHistory` need *some* check beyond "right
tenant") pushes this from theoretical to blocking.

## Working direction: operator authentication

Not yet an ADR - a direction to build the Stage 1 stub and the Stage 5 console against, cheap to
revisit before either is real:

**External IdP (OIDC)** - the console redirects to a configured identity provider (Keycloak, Entra
ID, Auth0, ...); `Ago.Chat.Api` validates the returned token (still a JWT - OIDC access/id tokens are
JWTs, so `realtime.md`'s "`/hubs/operator` authenticated by the operator's JWT" does not change,
only *who signs it* does) and maps its claims to an operator + `site_id`. Rejected for now:
self-issuing tokens against a password table in `ago-chat`'s own database - a real feature (password
reset, hashing, brute-force lockout) that competes for review attention with the concurrency and data
work this project exists to demonstrate, for a problem every OIDC provider has already solved
correctly.

Consequence this pins down early: Stage 0's `Ago.Chat.Api` will eventually hold OIDC client
configuration (issuer, audience, client id) - a secret in deployment, never in the repository
(`repositories.md` - "no secrets, ever").

## Done when this stops being an open question

- An ADR chooses roles-and-tenant-scoping or RBAC (or a third option nobody has proposed yet), with
  the trigger being a real use case, not a deadline.
- A second ADR (or the same one) confirms or replaces the OIDC direction for operators.
- `realtime.md` and `vision.md` are updated to state the chosen model as fact instead of pointing here.
