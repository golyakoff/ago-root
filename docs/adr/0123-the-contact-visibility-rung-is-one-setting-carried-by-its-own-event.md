# ADR-0123: The contact-visibility rung is one setting on the account, carried across the product boundary by its own minimal event — and rung three does not exist in the type system

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 23 (`23-11`)

## Context

`decisions.md` §5 named a three-rung ladder for contact visibility. Its own amendment (2026-09-04)
found the ladder had been built once, over AGO Calendar's `customers` (`20-12`), and not over chat's
own `visitor_contact_details` — so a tenant sold "your staff cannot casually copy the customer list"
would have had that promise for bookings and not for callbacks, which is decision 4's own headline
case. This item builds the setting on the account side, in `ago-chat`'s `sites` row, and applies it to
chat's own store.

Two questions were left open by the backlog item, deliberately, for this ADR to answer: how the fact
crosses into `ago-calendar` (`23-12`, a separate repository and a separate database), and whether a
reveal is evidence belonging beside `24-12`'s `access_records` — landed the day before, in the same
stage — or in a table of its own.

## Decision

**Rung three ("Never") does not exist as a value of `Ago.Chat.Domain.ContactVisibility`.** Not an
unreachable member, not a value behind a flag. Absent. §5 is explicit that the third rung must not be
sold until the system can place the call itself — click-to-call, system-sent messages — because
without that mechanism "never visible" is not protection, it is an operator who cannot do the job. A
value present in the code, even one nothing constructs, is a value a future screen or a future sales
conversation can point at and offer. `UpdateContactVisibilityHandler` rejects the string `"Never"` for
the same reason it rejects `"visible-ish"`: there is no denylist, because there is no third member to
deny.

**One domain write raises one domain event, mapped to two integration events, because the two
audiences are genuinely different.** `Site.UpdateContactVisibility` raises
`SiteContactVisibilityUpdated`. It maps once to the existing `SiteSettingsChanged` — chat's own
cache-invalidation trigger, which has never crossed the product boundary — so the existing
`SiteCacheInvalidationConsumer` evicts the cached `SiteConfigDto` with no new consumer code, and
`ContactVisibility` joins that DTO on the same terms `Tier` already does: an additive field, never put
on the wire for the anonymous widget handshake. It maps a second time to a new contract,
`ContactVisibilityChanged`, with a minimal payload and the complete current value rather than a delta
— the identical discipline `RoleAssignmentsChanged` already states for itself — and that is the one
`23-12`'s calendar-side consumer reads.

Folding the cross-boundary fact into `SiteSettingsChanged` would make calendar depend on a contract
whose whole reason to exist is chat-internal. Inventing a second chat-internal consumer for the new
contract would duplicate `SiteCacheInvalidationConsumer` for no reason the cache has.

**A reveal writes a dedicated `contact_reveals` table, not a widened `AccessRecordKind`.**
`adr/0113`'s own Consequences invite widening that enum when "a fifth boundary-crossing read this
ADR's own defensible set does not cover" turns up — and a reveal is not that shape. `access_records`
names reads crossing a tenant or conversation boundary the operator would not otherwise cross:
`18-07`'s cross-conversation history, the platform owner's cross-tenant surfaces. A reveal crosses
none. The revealing operator already holds `ConversationRead` on this exact conversation — the same
permission that already lets them read every other unmasked field in the identical response.

What a reveal records is narrower and product-specific: that one field the tenant's own setting chose
to mask was shown, on purpose, for attribution. §5's own counter-instruction — reveal counts belong in
an audit view, never in the report a person is judged on — argues for a table with its own screen and
its own caveat text, not a stream folded into a log whose original purpose a higher-volume,
ordinary-operator-triggered event would dilute.

`contact_reveals` follows `access_records`' own *shape*: raw Npgsql, no aggregate, no foreign key on
`site_id` or `contact_detail_id`, keyset-paged, its own 365-day prune job. The backlog item's text
pointed at `webhook_deliveries` instead, having been written before `24-12` landed; `access_records`
is the more recently reasoned precedent for exactly this "receipt with no invariant beyond one row per
event" case.

**Masking happens in the read model, never in the console, and reveal is ungated by the rung.**
`ListVisitorContactDetailsHandler` returns an already-masked value under `MaskedWithReveal`; the real
value never reaches the browser as part of a list, proven by a test that searches the whole serialised
response rather than the one field a careless edit might mask. `RevealVisitorContactDetailHandler`
checks only `ConversationRead`, never the rung — the rung governs what the *list* shows, not who may
reveal, and gating reveal on it too would be a second check with nothing behind it.

## Consequences

**Positive.** A tenant on `MaskedWithReveal` gets the promise decision 4 needed for chat's own store,
with no shared type crossing the product boundary and no new chat-internal cache machinery. The reveal
audit trail is small, cheap, and answerable on its own terms without diluting `access_records`'
existing report.

**Negative, stated rather than discovered.** Two integration events from one domain write is a shape
this codebase has not used before — every prior example is the reverse, several domain events
converging on one contract — so a future reader extending `Site`'s write paths must notice this
precedent rather than assume one event per write. `contact_reveals` is a second small table with its
own prune job beside `access_records`', which is more moving parts than one unified table; accepted
because the two answer different questions to different audiences.

**What is not built here.** `ago-calendar` consumes nothing yet. The contract is published and its
shape is fixed, but `23-12` is the item that reads it, so the redelivery idempotence of *that*
consumer is unverified by construction — there is no consumer to test. There is also no console
screen for the rung itself or for the reveal audit trail; both are reachable today only through the
API, and each needs its own item.

## Alternatives considered

**Widen `AccessRecordKind` with a `ContactReveal` member.** Rejected: the read this table exists to
log is not the boundary-crossing shape that enum's members share, and commingling would dilute
`24-12`'s report with a higher-volume, differently-caused stream.

**Fold the rung into `SiteSettingsChanged` and let `23-12` consume that.** Rejected:
`SiteSettingsChanged`'s own remarks are explicit that it has never crossed the product boundary and
exists for one chat-internal consumer. Making calendar depend on it would blur a boundary this project
has kept clean since `RoleAssignmentsChanged` was introduced for the identical purpose.

**Add `Never` as an unreachable member, gated off at every call site.** Rejected outright by §5's own
instruction, for the reason in the Decision above.
