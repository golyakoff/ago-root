# ADR-0165: The quota-impact preview is the first reply the calendar sends chat, over the identical outbox mechanism

- **Status**: Accepted
- **Date**: 2026-09-10
- **Stage**: 23 (`23-88`)
- **Extends**: `adr/0125` (the chat→calendar quota-grant crossing this item's own reply direction
  mirrors) and `adr/0093` (the two-schema boundary this decision crosses a second, new way). Amends
  neither.

## Context

`23-88`'s own Scope: before a platform owner lowers a tenant's worker quota, chat must say how many
workers the new number would exceed. `messaging.md`'s own "AGO Calendar's own topics" section stated,
until this item, a plain fact about the whole system: *"Nothing here is consumed by AGO Chat and
nothing there is consumed here."* Every crossing built so far (`adr/0125`'s quota grant,
`adr/0147`'s collected-contact carry-over) runs one way, chat to calendar. Answering "how many" needs
the opposite direction for the first time: calendar has to tell chat something.

Two shapes were on the table for that reply:

1. **A new mechanism** - a webhook chat exposes, or a database calendar could poll. Rejected before
   being seriously drafted: this platform already has exactly one cross-product transport (the
   outbox/broker pair, `messaging.md`'s own delivery-guarantee and versioning rules), and a second one
   built for one reply would need its own retry, ordering and idempotency story duplicating what the
   first already has.
2. **The identical outbox mechanism, used in the direction it has not been used in yet.** Chat
   publishes a question the same way it already publishes `ModuleQuantityGranted`
   (`ModuleQuantityImpactRequested`, `adr/0125`'s own snapshot shape); whichever module answers
   publishes a reply on its own outbox, to a topic chat subscribes to the same way calendar already
   subscribes to chat's own topics (`ModuleQuantityGrantedConsumer`'s own precedent, mirrored).

## Decision

**Reuse the existing outbox/broker mechanism in both directions. No new cross-product transport.**

- `Ago.Chat.Contracts.ModuleQuantityImpactRequested` (`SiteId`, `ModuleKey`, `RequestedQuantity`,
  `CorrelationId`, `OccurredAt`) is chat's own question, staged on chat's own outbox in the same
  transaction as the preview row it describes (rule 4) - the identical shape
  `ModuleQuantityGrantedMapper`/`ModuleQuantityGrantStore` already establish for the grant itself.
- The answering module publishes its own reply, `ModuleQuantityImpactComputed` (`SiteId`, `ModuleKey`,
  `RequestedQuantity`, `AffectedCount`, `AffectedItemDisplayNames`, `CorrelationId`, `OccurredAt`), on
  its own outbox, to a topic named by that literal string - `Ago.Chat.Worker` subscribes to it exactly
  the way `Ago.Calendar.Worker.ModuleQuantityGrantedConsumer` already subscribes to chat's own
  `ModuleQuantityGranted`, including the identical "each product declares its own local copy of the
  wire shape, never a shared Contracts assembly" discipline `adr/0027`'s repository split already
  requires (`ModuleQuantityImpactComputedWireContract`, `Ago.Chat.Worker`'s own file, `internal`).
- No idempotency ledger on the receiving side (either direction): both the grant and the impact answer
  are naturally idempotent snapshots (`ModuleQuantityImpactPreview.Answer`'s own remarks - a
  redelivered identical answer rewrites the identical values; a late answer to a superseded question
  is a silent no-op, the identical "ack, do nothing, no inbox row for a message never acted on" shape
  `ModuleQuantityGrantedConsumer` already establishes for a grant meant for a different module).
- **This reply is opaque to chat, the same discipline `ModuleQuantityGrant` already applies to the
  grant itself.** `AffectedItemDisplayNames` is a list of strings chat never inspects the meaning of -
  it does not know or care whether they name workers, masters, or anything a future module invents.

## Consequences

- **`messaging.md`'s own "nothing there is consumed here" sentence stops being true**, and this ADR is
  the record of why the change is deliberate rather than a drift the document simply failed to catch.
  `docs/architecture/messaging.md` is updated in the same change that accepts this ADR.
- **`ago-chat`'s own half is complete and inert until a module product implements the answering half.**
  `Ago.Chat.Worker.ModuleQuantityImpactComputedConsumer` subscribes to a topic nothing publishes to
  yet - a real, harmless deployment state (an idle competing-consumer subscription), not a defect;
  the console-facing preview simply sits "asked, not yet answered" until `ago-calendar` ships its own
  consumer/publisher pair (`23-88`'s own report specifies the exact shape needed).
- **Two payment-free, low-volume, human-paced questions per quota-lowering decision, not a hot path.**
  The identical "admin-to-admin, low-volume" profile `adr/0095`'s own provisioning secret already
  argues from - this is not a channel a visitor's browser can reach, directly or indirectly, so the
  broker load this adds is negligible and no rate limiting or circuit-breaking beyond what the
  platform's outbox dispatcher already provides is warranted.
- **The write-time safety net stays exactly where `adr/0125` already put it.** This reply exists to
  inform an owner before they confirm, not to gate whether a grant may apply - the calendar's own
  live lock-and-count, inside the transaction that actually applies a grant, remains the only place an
  incorrect deactivation could be prevented, unchanged by this item. A stale or entirely absent answer
  can make chat refuse to *submit* a grant (`ago-chat`'s own `Module.QuantityImpactStale`, HTTP 409);
  it can never make the calendar apply a *wrong* one.

## Alternatives considered

- **A calendar-side HTTP endpoint chat polls synchronously.** Rejected by `23-88`'s own Decided
  section before this ADR was written: a live synchronous call on this path would make lowering a
  quota depend on the calendar's reachability, a dependency that does not exist today, and would be
  unusable from an unattended future automatic trigger with no human session to poll on behalf of.
- **A shared NuGet package for the reply's own wire format.** Rejected for the identical reason
  `adr/0095`'s own alternatives already reject one for the provisioning contract: two callers with no
  third in sight, and `Ago.Platform.*` must never learn a product's shape (`adr/0012`).
