# ADR-0027: Operator identity across products — separate per-product entities, unified only through Keycloak

- **Status**: Accepted
- **Date**: 2026-08-24
- **Stage**: 14/20 (decided ahead of both, since it shapes how each is built)

## Context

AGO Calendar (`roadmap.md` Stage 20) introduces its own day-to-day booking-queue actor: an
**Operator**, created by a **Tenant**, who confirms/rejects pending bookings and manages customer
lead cards — a role the author's own spec for that product describes explicitly as "the same
Operator concept AGO Chat already has, not a new parallel one," while leaving open whether that
means the literal same entity/table or a structurally similar-but-separate one.

AGO Inbox (Stage 14/21) sharpens the question from the other side: its whole point is a **single
operator-facing queue** — a chat conversation, a Telegram conversation once built, and a Calendar
booking confirmation should surface in one screen, not three. If that queue is genuinely one thing,
that is a real argument for the two products' Operator concepts being the same entity, not two that
happen to share a name.

At the same time, AGO Calendar's own domain is undeniably new: `Worker`, `Customer`, `Event`,
`Service`, `WorkingHoursRule` are concepts `Ago.Chat.Domain` has never had and has no reason to grow.
That cuts the other way — toward Calendar being a genuinely separate product, not a feature bolted
onto `Ago.Chat.*`.

This ADR has to resolve the tension before either product's own Domain layer gets written, because
"where does Operator live" is exactly the kind of question `clean-architecture.md` says decides a
file's home, and getting it wrong means a rewrite once the second product's Operator table already
has real rows.

## Decision

**AGO Calendar defines its own `Operator` entity, in its own repository (`ago-calendar`,
`Ago.Calendar.Domain`), with its own table. It is never the same database row as
`Ago.Chat.Domain.Operator`, and no product ever queries the other's database.** The two are unified
only at the identity layer, through the mechanism `adr/0022` already built and proved for one
product: Keycloak issues one identity per real person; each product resolves the validated JWT's
`sub` against its own local `operators` row via its own `external_subject_id` column and its own
`IClaimsTransformation` (`OperatorIdentityClaimsTransformation`'s exact shape, copied, not shared
code — see Consequences for why copying is the right call here and not a shortcut).

Concretely, this is **Variant B** from the three candidates the author's own framing named, refined
with the identity mechanism spelled out:

1. **Variant A — literally the same `Operator` entity/table.** Rejected. See Alternatives.
2. **Variant B — structurally parallel, genuinely separate entities, unified through Keycloak
   identity only.** **Chosen.**
3. **A third option — hoist a shared `Operator` (or "OperatorIdentity") aggregate into
   `Ago.Platform.*`, each product's own conversation/booking domain object stays product-specific.**
   Rejected. See Alternatives — this is the one the author's own framing asked to be reasoned about
   explicitly rather than dismissed by default, so it gets its own paragraph there.

### Why Keycloak is the actual shared substrate, not a new platform concept

`adr/0022` already established the pattern this decision reuses: Keycloak is an external identity
provider, outside both products' own domains, and each product resolves *from* it into its own local
row. That is not a new abstraction this ADR invents — it is the same claims-transformation shape
`5-05` built for `Ago.Chat.Api`, applied a second time for `Ago.Calendar.Api`. The fact that a
*second* product can lean on it unchanged is itself a real instance of the platform claim
`vision.md` exists to prove, except the "platform" doing the proving here is Keycloak (an external
system both products point at) rather than anything inside `Ago.Platform.*` — which is exactly
consistent with `clean-architecture.md`'s own qualifying test for what belongs in the platform
package (below).

A tenant who runs both a chat queue and a calendar for the same shop provisions the *same person* as
an operator in each product's own console — one Keycloak login, two local `operators` rows, one per
product, each carrying that product's own capacity/role/permission shape. This is real friction,
named honestly in Consequences, not hidden behind the word "unified."

## Consequences

- **Two `operators` tables, two RBAC/permission catalogues.** `Ago.Chat.Domain`'s
  `conversation:*`/`site:*` permissions and `Ago.Calendar.Domain`'s own (`booking:confirm`,
  `booking:reject`, `calendar:configure`, ...) are independent vocabularies from day one — no shared
  `Permission` enum, no shared `Role` table. This is the direct cost of the decision, not a detail to
  discover later.
- **Provisioning an operator for both products is two actions, not one**, until a later item builds
  a cross-product console convenience for it (not scoped here, not scoped anywhere yet — a real gap,
  named, matching this repository's own precedent for stating a gap rather than quietly building
  around it).
- **The claims-transformation code is deliberately duplicated, not extracted.** `clean-architecture.md`
  already names the failure mode this avoids: "an abstraction extracted from exactly one caller is a
  guess about the second one... until [a second caller] exists, treat anything ambiguous as product
  code and promote it later." A second caller (`Ago.Calendar.Api`) now genuinely exists, so the
  "only one caller" objection is gone — but `OperatorIdentityClaimsTransformation` is not a
  technical port in the `ICache`/`IEventPublisher` sense (`clean-architecture.md`'s own three-part
  platform test, restated below); it is a five-line mapping from a validated claim to a
  product-specific row shape, and that row shape is exactly the part that must differ per product.
  There is nothing left to extract once the row shape is removed — copying the pattern costs one
  small file per product, which is cheaper and more honest than a shared abstraction with one real
  parameter (the row type) doing all the work.
- **A genuinely unified operator queue (AGO Inbox's own stated goal) is real, deferred, cross-product
  integration work** — not solved by this ADR, and more expensive than it would have been under
  Variant A. `ago-console` (or a future shared operator console) has to call both products' own read
  APIs and merge client-side, or a lighter cross-product notification path has to be designed later.
  Named explicitly as Stage 21's own open question (`21-02-unified-operator-queue-across-chat-and-
  calendar.md`) rather than assumed solved by this decision.
- **Reinforces, rather than weakens, the platform claim.** Calendar's Operator role looks similar
  enough to Chat's on the surface to tempt merging the two for convenience. Resisting that temptation
  for a stated architectural reason — not "it was easier to keep them apart" — is a harder and more
  honest proof that the platform/product boundary holds than AGO Ads' own untested plan ever would
  have been, because AGO Ads never had a concept that rhymed with an existing one this closely.

## Alternatives considered

- **Variant A — the literal same `Operator` entity/table.** Would make "one unified queue" a
  structural consequence rather than integration work, exactly as the author's own framing named.
  Rejected: it requires `ago-calendar` and `ago-chat` to share one database and bounded context,
  which contradicts `repositories.md`'s own stated test for when a new repository is justified —
  "only when the thing versions or deploys independently." AGO Calendar deploys independently (its
  own hosts, its own release cadence, a genuinely different load shape — booking traffic vs. chat
  traffic), exactly the property that justified a new repository for AGO Ads before it and justifies
  one for Calendar now. A shared `Operator` table would mean the repository split is cosmetic while
  the runtime coupling is real — the same failure `adr/0012` already rejected once for the
  platform/product boundary generally, now reappearing between two products instead of between the
  platform and a product.
- **A shared `Ago.Platform.Operator` (or `OperatorIdentity`) aggregate — the third option the
  author's own framing asked to be weighed explicitly.** Rejected directly by
  `clean-architecture.md`'s own "What qualifies as platform" test, applied plainly:
  - *"It contains no domain concept."* An `Operator` that carries capacity, a booking queue, or
    role/permission membership **is** a domain concept — the same reasoning that doc already applies
    by name to reject a shared `IConversationRepository` applies without modification to a shared
    `IOperatorRepository` or a shared `Operator` aggregate.
  - *"A second product would plausibly use it unchanged."* It would not: Calendar's Operator has no
    `active_chats`/capacity concept at all (a barbershop's operator works one pending-booking queue,
    not a concurrent-conversation capacity limit); Chat's Operator has no booking-confirmation
    concept. A "shared" `Operator` would immediately need product-specific extension fields, which is
    exactly the "abstraction that turns out to need a per-caller escape hatch" smell that test exists
    to catch before it is built, not after.
  - *"It can be described without naming chat, visitors, or operators [as a chat-specific
    concept]."* It cannot — "operator" here already carries chat-shaped assumptions (assignment,
    capacity) that would have to be generalised away, at which point what remains is not an entity at
    all, only the identity-resolution *pattern* — which is exactly what stays outside the platform,
    resolved through Keycloak instead (see Decision above).
  - This option is the one genuinely new idea in this ADR beyond restating Variant A vs. B, and it is
    rejected for the same reason `Ago.Platform.Kernel`'s own narrowness is deliberate
    (`naming-and-structure.md`: "There is no project named `Common`, `Shared`, `Utils` or `Core`...
    those names are where unrelated code goes to hide") — a platform-level `Operator` would be
    exactly that kind of hiding place, dressed up as a shared building block.
- **Do nothing / leave it an open question in both products' own backlog items.** Rejected: both
  Stage 14/20/21's own backlog items need to know, before their first line of Domain code, whether
  `Ago.Calendar.Domain` gets an `Operator` type or references one from elsewhere — this is exactly
  the class of decision `docs/adr/README.md` says gets an ADR rather than being re-litigated per
  item, and a reviewer reading both products side by side would ask this question directly.
