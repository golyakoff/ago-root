# Ago.Chat.Api: two hubs, visitor tokens, operator auth stub, real DI

- **Stage**: 1
- **Status**: ready
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
  served from `Ago.Chat.Api`'s `wwwroot` or opened as a local file pointed at the running API — **not**
  the real widget (`ago-widget`'s Shadow-DOM build is Stage 5). Exists solely to prove the "done when"
  by hand; delete or clearly mark throwaway if it would otherwise look like a shipped feature.
- Manual verification, documented with what was actually run (matching how `0-03`'s runbooks were
  verified): two browser tabs, messages both directions, reload one tab, history is still there.

## Out of scope

- The real widget and operator console — Stage 5.
- Redis connection registry / cross-node delivery — Stage 3; Stage 1 is one instance, so hub state
  can live in-process.
- OIDC — Stage 5; this item's operator auth is an explicitly temporary stub.
- Rate limits, CORS beyond "allow the demo site" — Stage 5.

## Done when

- [ ] Two browser tabs (or the test harness's two panes) — one as the visitor, one as the seeded
      demo operator — exchange messages in both directions through one running `Ago.Chat.Api`.
- [ ] Reloading the visitor tab shows the same history via `GetConversationHistory`, not a fresh
      conversation.
- [ ] `Ago.Chat.Architecture.Tests` passes unchanged — nothing in `Ago.Chat.Module`/`Ago.Chat.Api`
      violates the existing rules.
- [ ] `docs/runbooks/local-dev.md` gains the real commands/URLs for this, verified by running them,
      matching the evidence bar `0-03` set.

## Open questions

None. The operator-auth stub's shape (`POST /dev/operator-session`) is confirmed.
