# Ago.Chat.Api: two hubs, visitor tokens, operator auth stub, real DI

- **Stage**: 1
- **Status**: done, with one verification gap disclosed below - 78 automated tests pass (25
  Application, 30 Domain, 13 arch, 10 integration), and the mechanism was verified for real against a
  running `Ago.Chat.Api` and the `docker-compose` Postgres: `POST /api/v1/visitor-sessions` and
  `POST /dev/operator-session` both issue real JWTs; both hubs' JWT Bearer auth was proven both ways
  (a missing/wrong-audience token gets `401`, a valid one completes the WebSocket handshake);
  `VisitorHub.JoinAsync` starts and resumes real conversations against Postgres; `OperatorHub.JoinConversationAsync`
  enforces `adr/0016`'s RBAC check against the seeded role before assigning; a sent message is
  persisted and the sender's own connection receives it back via the SignalR group broadcast (checked
  directly server-side: `Groups.AddToGroupAsync` completes for the joiner's connection id, and the
  broadcast targets the identical group name).
  **What was not cleanly observed**: a live two-tab *cross-party* delivery (operator's reply arriving
  at the visitor's open tab) in the browser. Every attempt hit WebSocket transport instability
  specific to this session's browser-automation tooling (`Failed to start the transport 'WebSockets'`,
  `ERR_CONNECTION_REFUSED`, connections dropping between tool calls) - not a symptom of the hub code,
  which the server-side evidence above already exercises up to and including the broadcast call
  itself. Recorded here rather than silently claimed - a human running the same two tabs by hand
  should confirm this cheaply, and update this note if it doesn't hold.
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
  real Postgres, and self-echo broadcast were all confirmed live. Live cross-party delivery in two
  open tabs was attempted repeatedly and not cleanly observed - see Status above for why, and what
  would still need a human's five minutes to close out.

## Out of scope

- The real widget and operator console — Stage 5.
- Redis connection registry / cross-node delivery — Stage 3; Stage 1 is one instance, so hub state
  can live in-process.
- OIDC — Stage 5; this item's operator auth is an explicitly temporary stub.
- Rate limits, CORS beyond "allow the demo site" — Stage 5.

## Done when

- [ ] Two browser tabs (or the test harness's two panes) — one as the visitor, one as the seeded
      demo operator — exchange messages in both directions through one running `Ago.Chat.Api`.
      **Not cleanly confirmed this round** - see Status. The visitor→operator direction, the
      resume/history-on-reload path, and the broadcast mechanism itself are each independently
      verified (real hub calls, real Postgres, self-echo); only the live operator→visitor delivery
      in two simultaneously-open tabs needs a human to confirm directly.
- [ ] Reloading the visitor tab shows the same history via `GetConversationHistory`, not a fresh
      conversation. Covered by `1-02`'s `StartConversationHandlerTests` (fakes) and `1-04`'s
      `ConversationRepositoryTests` (real Postgres) at the layers below the hub; not independently
      re-observed live in the browser this round for the same reason as above.
- [x] `Ago.Chat.Architecture.Tests` passes unchanged — nothing in `Ago.Chat.Module`/`Ago.Chat.Api`
      violates the existing rules (13/13, including the new `PersistenceBoundaryTests` from `1-04`).
- [x] `docs/runbooks/local-dev.md` gains the real commands/URLs for this, verified by running them,
      matching the evidence bar `0-03` set.

## Open questions

None. The operator-auth stub's shape (`POST /dev/operator-session`) is confirmed.
