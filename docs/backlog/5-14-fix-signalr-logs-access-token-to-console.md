# Fix: the console's SignalR client logs the operator's access token to the browser console

- **Stage**: 5
- **Status**: ready
- **Depends on**: nothing — `ago-console` only

## Goal

`ago-console` stops printing the operator's bearer token to the browser console on every hub
connect. Today `@microsoft/signalr`'s default logging writes the full negotiated WebSocket URL —
`access_token` query parameter included — at `Information` level, so a real, unexpired operator JWT
sits in plain text in devtools for anyone looking over a shoulder, in a screen recording, in a
screenshot pasted into a ticket, or in whatever a browser-extension console collector picks up.

## Context to read first

`docs/conventions/coding-style.md`, line 41: *"Never log message bodies, tokens, presigned URLs or
anything from a visitor's keyboard."* — the rule this violates, stated plainly and already applying
to every other logging decision in this codebase. `CLAUDE.md`'s "Everything is public" section makes
the same point about tokens from the repository-content side.

`ago-console/src/realtime/operatorConnection.ts` — `new signalR.HubConnectionBuilder().withUrl(...)`
with no `configureLogging(...)` call, so the library's own default level applies. The widget has the
same shape (`ago-widget/src/connection.ts`) and needs checking too: its token is a visitor token
rather than an operator one, which is a smaller blast radius (`api-design.md`: a visitor token grants
only that visitor's own conversation) but the same rule and the same one-line fix.

## How this was found

Found live (2026-08-25) while verifying `11-05`'s retrofit in a real browser against a running API —
the console output contained the full `wss://.../hubs/operator?id=...&access_token=eyJ...` line on
every connect. Not a hypothetical: an actual, valid `demo-admin` token was visible in devtools, and
the same would be true for a real operator on the public deployment.

## On writing this down publicly

Kept specific per `architecture/repositories.md`'s rule (added 2026-08-25): the clients' logging
configuration is in public source, so describing it vaguely here would protect nothing and cost the
reasoning. What must never be recorded — here or in a commit message — is an actual captured token.

## Scope

- `configureLogging(...)` on both `HubConnectionBuilder` call sites (`ago-console`, and `ago-widget`
  if the same check confirms it there): a level that suppresses the URL line in production while
  keeping genuinely useful diagnostics. `signalR.LogLevel.Warning` is the obvious candidate — decide
  and state it rather than picking silently.
- Decide whether development keeps verbose logging. If it does, it must be conditional on the build
  mode (`import.meta.env.DEV`), never a value that can ship — and the token is just as real in
  development, so "it's only local" is not on its own a sufficient argument. State whichever way it
  goes and why.
- A check for any *other* place either client hands a token somewhere it could be logged or persisted
  beyond `sessionStorage`/`localStorage`'s existing, intended use.

## Out of scope

- Moving the token out of the query string entirely (a `Sec-WebSocket-Protocol` header or a
  short-lived per-connection ticket). That is a real, larger design change — `realtime.md`'s
  connection protocol, plus a server-side change in `Ago.Chat.Api` — and it is worth its own item if
  the query-string placement itself is judged unacceptable. This item stops the *logging*, which is
  the part that is a one-line fix and a stated convention violation today.
- Server-side logging. `Ago.Chat.Api`'s own logger is not implicated — verified 2026-08-25:
  `appsettings.json` sets `"Microsoft.AspNetCore": "Warning"`, which suppresses the request-starting
  log that would otherwise print the path and query at `Information`. **Narrowed the same day**: the
  API's logger is not the whole server side. The edge access log (no log configuration exists anywhere
  in `ago-deploy`, so NGINX's default combined format applies and logs the full request line) and the
  trace spans (`AddAspNetCoreInstrumentation()` with no filter) have never been looked at, and a token
  written to disk outlives one in a browser console.
  `17-02-does-the-hub-token-reach-the-edge-log.md` owns that half. Still not this item's job — this
  note only stops "not implicated" from reading as "checked".

## Done when

- [ ] Neither `ago-console` nor `ago-widget` prints a URL containing `access_token` to the browser
      console at their default (shipped) logging level — verified by actually connecting against a
      running API and reading the real console output, not by reading the configuration.
- [ ] Whatever development-mode behaviour is chosen is stated in the code with its reasoning, and
      cannot leak into a production build.
- [ ] `npm run typecheck`/`lint`/`test`/`build` stay green in whichever repositories changed.

## Open questions

None — the rule is already written, the violation is confirmed live, and the fix is a documented
API of the library already in use. The only judgment call (what development mode does) is this
item's own to make and record.
