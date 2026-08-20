# Authorization: current state and what's still open

## Status

**The authorization model is decided: RBAC, scoped per tenant (`adr/0016`).** Operator-side checks
exist in `Application` from Stage 1 onward (`1-02`, `1-06`). What remains genuinely open is narrower
than before: operator *authentication* (who issues the token the permission check reads role claims
from - Stage 1 uses a dev-only stub, `adr/0016`'s consequences; OIDC is the working direction for
Stage 5), and the management surface for custom per-tenant roles (Stage 5 console work - `adr/0016`
fixed the model, not that surface).

Do not read anything before `1-02`/`1-06` land as authorized. Until then, `visitor` and `operator`
tokens *identify* a principal and *scope* it to a `site_id`; nothing yet asks "is this principal
allowed to do this specific thing." A visitor token proves "this is the same browser that opened this
conversation," not "this browser may read conversation X." Handlers must not be trusted to have
checked this until those items ship (`clean-architecture.md`: auth decisions are application code,
never edge or infrastructure - `edge.md`, `naming-and-structure.md`).

## The three actors, and what's already true about each

| Actor | Identification today | Authorization today |
|---|---|---|
| **Visitor** | Signed token (cookie/localStorage), scoped to one `site_id`, issued by `Ago.Chat.Api` on first contact (`vision.md`, `realtime.md`) | None beyond the token's `site_id` claim |
| **Operator** | `/hubs/operator` expects a JWT (`realtime.md`); *who issues it is the open question below* | None beyond whatever the JWT's `site_id` claim says |
| **Webhook/API integrations** | Outbound only today: deliveries to a tenant's endpoint are HMAC-signed (`adr/0013`) so *they* can verify *us*. There is no inbound integration API yet, so "how does a third party authenticate to AGO Chat" is entirely unplanned | N/A - does not exist |

`site_id` scoping is the one piece already load-bearing everywhere (`vision.md`: "multi-tenant from
day one"). Every candidate model below keeps it; none of them replace it.

## Decided: the authorization model

`adr/0016` chose **granular permissions (RBAC)** over roles + tenant scoping: named permissions
(`conversation:read`, `conversation:send`, `conversation:assign`, `site:configure`, ...) bound to a
`Role`, roles assigned per tenant. Chosen knowingly over the simpler, cheaper roles+scoping
alternative, to have the recognizable pattern in place before Stage 5's console needs it for real
rather than retrofitting it under pressure then - see `adr/0016`'s Consequences for the trade accepted.

Stage 1 ships exactly one hardcoded role (`"Operator"`) and the check mechanism, not a role-management
surface - that arrives with Stage 5's console.

## Permissions and roles beyond Stage 1 - deliberately deferred, not forgotten

Discussed while writing `1-02`/`1-06`, decided to defer rather than build speculatively
(`clean-architecture.md`: an abstraction with one caller is a guess about the second one). Recorded
here so a later session designing Stage 4 or Stage 5 does not have to rediscover the reasoning:

- **A supervisor/admin role** - sees every conversation for a site (not just its own assigned ones),
  and holds `site:configure` / `site:manage_operators` (including granting the `"Operator"` role
  itself - `adr/0016` left this ungranted by anything but the `1-05` seed script). Natural home:
  **Stage 5**, alongside the console - that is the first point anything actually needs to *use* an
  admin role rather than just assert one exists.
- **`conversation:transfer`** - an operator hands off their *own already-assigned* conversation to a
  named colleague (escalation, shift change, wrong expertise). Distinct from `conversation:assign`,
  which claims an unassigned conversation out of the waiting queue - transfer moves an assigned one
  directly between two operators, no queue involved. Natural home: **Stage 4**, next to the real
  assignment engine, since both are "who is allowed to move a conversation between operators" and
  benefit from being designed together rather than transfer arriving as an afterthought.
- **`attachment:delete`** - a moderation action (remove an inappropriate or malicious upload),
  naturally paired with the admin role above rather than granted to every operator. Home: wherever the
  admin role lands (Stage 5), and after `architecture/file-storage.md`'s Stage 5 upload path exists to
  delete from.
- **`attachment:upload`/`attachment:view` as separate permissions from `conversation:send`/`read`** -
  considered and rejected for now: nothing in `vision.md` calls for an operator who can read a
  conversation's text but not its files (or vice versa). If a real compliance scenario needs that
  split later, it is a permission split, not a data-model change - cheap to add when a caller actually
  needs it.
- **`site:manage_webhooks`** - not designed yet, but Stage 6 (`Ago.Chat.Webhooks`, `adr/0013`:
  "tenant endpoint registration") will need exactly this kind of check. Flagging now so Stage 6's
  planning session connects it to this model instead of inventing a parallel one.

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

## Done when nothing here is open anymore

- [x] An ADR chooses the authorization model - `adr/0016`, RBAC.
- [ ] An ADR confirms or replaces the OIDC direction for operators (Stage 5).
- [ ] `realtime.md` and `vision.md` are updated to state the chosen model as fact instead of pointing
      here, once `1-06` ships the mechanism `adr/0016` describes.
