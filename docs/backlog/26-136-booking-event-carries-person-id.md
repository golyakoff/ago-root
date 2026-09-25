# 26-136 · [ago-chat + ago-calendar] The booking event carries the person id and origin conversation

- **Stage**: 26 — S1 (first EXPAND slice) of ADR-0184 (option B). See
  `docs/design/26-134-person-identity-implementation.md`.
- **Status**: ready — in flight (migration lane).
- **Found**: 2026-09-25, scoping ADR-0184.

## The one promise
A chat-origin booking stores the chat person id and the originating conversation id on its calendar
`Event`. Additive only — `customers` is untouched; both suites stay green without any later slice.

## Scope
- **ago-calendar**: `Event.PersonId` (Guid) + `Event.OriginConversationId` (Guid?), set in `Claim`;
  `EventConfiguration` mapping; `BookEventHandler`/`BookingStore` thread them from the inbound request onto
  the Event and **mint a person id when none is supplied** (dormant public/operator path). Inbound module
  wire DTOs (Start / Submit-reply) gain `personId` + `originConversationId` — additive, nullable, tolerated
  when absent. **Migration M1**: add `person_id`, `origin_conversation_id` to `events`, nullable.
- **ago-chat**: `IModuleGateway` (`StartModuleTaskRequest`/`SubmitModuleReplyRequest`), `ModuleWireContract`,
  `HttpModuleGateway`, `RouteConversationToModuleHandler` populate `PersonId = conversation.VisitorId` and
  `OriginConversationId = conversation.Id`, following the existing `KnownPhone` resent-per-call precedent (no
  chat migration).
- Out of scope (later slices): display-name persistence, the `customers` table, `ContactCollected`, merge.

## Done when
- [ ] A chat booking yields `events.person_id` == the visitor's id and `events.origin_conversation_id` ==
      the conversation id (integration test).
- [ ] Additive wire fields tolerated when absent (old-shape test still books); `customers` unchanged; no chat
      migration; M1 applies cleanly.
- [ ] ago-chat and ago-calendar suites green (per-project counts reported). Subsumes **26-112 C1**.
