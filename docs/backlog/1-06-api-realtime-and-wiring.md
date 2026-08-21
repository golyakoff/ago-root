# Ago.Chat.Api: two hubs, visitor tokens, operator auth stub, real DI

- **Stage**: 1
- **Status**: done - 78 automated tests pass (25 Application, 30 Domain, 13 arch, 10 integration),
  and the mechanism was verified for real against a running `Ago.Chat.Api` and the `docker-compose`
  Postgres: `POST /api/v1/visitor-sessions` and `POST /dev/operator-session` both issue real JWTs;
  both hubs' JWT Bearer auth was proven both ways (a missing/wrong-audience token gets `401`, a valid
  one completes the WebSocket handshake); `VisitorHub.JoinAsync` starts and resumes real conversations
  against Postgres; `OperatorHub.JoinConversationAsync` enforces `adr/0016`'s RBAC check against the
  seeded role before assigning; a sent message is persisted and delivered live to both parties.
  **A real bug was found and fixed during manual verification, not a tooling artifact**: the first
  round of two-tab testing showed the sender always receiving their own broadcast but the *other*
  party's open tab never receiving it, with no connection drops observed. Root cause: each `Hub`
  subclass in SignalR owns its own `HubLifetimeManager<THub>`, so a group named `conversation:{id}`
  in `VisitorHub` and a group of the identical name in `OperatorHub` are two entirely separate
  groups - `Clients.Group(...)` inside a hub method only ever reaches connections that joined that
  group through that same hub type. Broadcasting to the other party requires that party's hub's own
  `IHubContext<THub>`, not `this.Clients`. Fixed by injecting `IHubContext<OperatorHub>` into
  `VisitorHub` and `IHubContext<VisitorHub>` into `OperatorHub`, and broadcasting to both the own-hub
  group and the counterpart hub's group on every send (`Hubs/VisitorHub.cs`, `Hubs/OperatorHub.cs`).
  Re-verified live afterwards, twice, in genuinely separate browser tabs, both directions, each with
  its own fresh conversation: operator→visitor and visitor→operator both arrived in the peer's tab
  with no reload, in both runs.
- **Depends on**: `1-02-application-use-cases.md`, `1-03-platform-system-clock.md`,
  `1-04-postgres-persistence.md`, `1-05-seed-demo-tenant.md`

## Goal

`Ago.Chat.Api` stops being a health-check-only shell (`0-03`). `ChatModule.ConfigureServices` wires
the real dependency graph; two SignalR hubs let a visitor and an operator exchange messages through
one running instance; a visitor gets a token on first contact; the seeded demo operator can
authenticate. This is Stage 1's "done when": two browser tabs, one API instance, history survives a
reload.

## Context to read first

`docs/architecture/realtime.md`, `docs/architecture/authorization.md`, `docs/adr/0016-*` (the RBAC
check `/hubs/operator` methods must pass through before dispatching), `docs/architecture/clean-architecture.md`
(Hosts section — a hub method is transport, not logic), `docs/architecture/api-design.md`.

## Scope

- `ChatModule.ConfigureServices`: registers `AgoChatDbContext`, `IConversationRepository`,
  `IConversationReadStore`, the three use-case handlers, `IClock` (`1-03`'s `SystemClock`),
  `IIdGenerator` (`UuidV7Generator`, already exists).
- `/hubs/visitor`: on first connect with no token, issues one (signed, scoped to the site from
  `data-site`/a query parameter), starts or resumes the visitor's conversation
  (`StartConversation`), pushes history. `SendMessage` dispatches to the use case.
- `/hubs/operator`: authenticated by a throwaway dev endpoint, `POST /dev/operator-session`, trading
  the seeded demo operator's id (printed by `1-05`'s script) for a self-issued JWT carrying the
  operator's `site_id` and its one hardcoded `"Operator"` role (`adr/0016`). Named and documented so
  it is impossible to mistake for a production auth path (`repositories.md` — everything here is read
  by a stranger); replaced outright by OIDC at Stage 5, not evolved into it. Exposes `SendMessage` and
  a trivial `JoinConversation` (direct-assign, per `1-01`'s scope note — not the Stage 4 assignment
  engine), both going through `1-02`'s `IPermissionChecker` before dispatching.
- Hub methods map argument -> command -> `Result`, and `Result` -> hub response/error. No business
  logic in a hub method (`clean-architecture.md`).
- A minimal static test harness: plain HTML + the SignalR JS client, two panes (visitor / operator),
  served from `Ago.Chat.Api`'s `wwwroot` (`dev-harness.html`, only mapped in Development) — **not**
  the real widget (`ago-widget`'s Shadow-DOM build is Stage 5). Exists solely to prove the "done when"
  by hand, clearly labelled as throwaway in its own markup.
- `ISiteRepository` (`Abstractions/`) and its EF implementation - not named in this file's original
  scope, needed for `/api/v1/visitor-sessions` to resolve a site from its public key. Same reasoning
  as `1-02`'s `IVisitorRepository`: completes a port `1-04`'s schema already supports, not a new
  concern.
- `AssignConversation` (`UseCases/`) - a small Application addition `1-02` didn't include: the
  `conversation:assign` permission check plus `Conversation.AssignTo` (`1-01`), called from
  `OperatorHub.JoinConversationAsync`. Unit-tested the same way as `1-02`'s other handlers.
- Manual verification, documented with what was actually run (matching how `0-03`'s runbooks were
  verified): the HTTP endpoints, JWT auth on both hubs, `JoinAsync`/`JoinConversationAsync` against
  real Postgres, self-echo broadcast, and live cross-party delivery in two genuinely separate browser
  tabs (both directions, two independent runs) were all confirmed live - see Status above for the
  hub-isolation bug this surfaced and the fix.

## Out of scope

- The real widget and operator console — Stage 5.
- Redis connection registry / cross-node delivery — Stage 3; Stage 1 is one instance, so hub state
  can live in-process.
- OIDC — Stage 5; this item's operator auth is an explicitly temporary stub.
- Rate limits, CORS beyond "allow the demo site" — Stage 5.

## Done when

- [x] Two browser tabs (or the test harness's two panes) — one as the visitor, one as the seeded
      demo operator — exchange messages in both directions through one running `Ago.Chat.Api`.
      Confirmed live in two genuinely separate tabs, both directions, two independent runs - see
      Status for the hub-isolation bug this exercise found and the fix applied.
- [x] Reloading the visitor tab shows the same history via `GetConversationHistory`, not a fresh
      conversation. Covered by `1-02`'s `StartConversationHandlerTests` (fakes) and `1-04`'s
      `ConversationRepositoryTests` (real Postgres) at the layers below the hub, and observed live:
      tab-5's `Join` fetched the demo conversation's prior messages via history, not a new one.
- [x] `Ago.Chat.Architecture.Tests` passes unchanged — nothing in `Ago.Chat.Module`/`Ago.Chat.Api`
      violates the existing rules (13/13, including the new `PersistenceBoundaryTests` from `1-04`).
- [x] `docs/runbooks/local-dev.md` gains the real commands/URLs for this, verified by running them,
      matching the evidence bar `0-03` set.

## Open questions

None. The operator-auth stub's shape (`POST /dev/operator-session`) is confirmed.
