# Fix: the console's SignalR client logs the operator's access token to the browser console

- **Stage**: 5
- **Status**: done — `.configureLogging(signalR.LogLevel.Warning)` on both `HubConnectionBuilder`
  call sites. The widget did have the identical defect, confirmed live rather than assumed, so this
  turned out to be two repositories rather than the one the "Depends on" line below predicted.
  The mechanism, pinned down exactly in `@microsoft/signalr@8`: `HubConnectionBuilder` with no
  `configureLogging` gets `ConsoleLogger(LogLevel.Information)`, and `WebSocketTransport` logs
  `WebSocket connected to {url}` at `Information` — *after* appending `access_token=` to that url.
  `Warning` was chosen as the **lowest** level that suppresses that line, keeping the diagnostics
  worth having (HTTP request errors and timeouts, the page-freeze warning that predicts a dropped
  connection, an unhandled server→client method name) rather than going to `Error`/`None`.
  Development keeps **no** verbose exception, in either client, and the reason is stronger than
  "the token is just as real locally": the token-bearing line sits at `Information`, which is
  *above* `Debug` and `Trace` on this library's ladder, so every level verbose enough to be worth
  switching to also prints the token. There is no dev setting that is both more informative and
  token-free, which makes the `import.meta.env.DEV` shape this item floated a way to reintroduce
  the leak rather than a way to keep diagnostics. (`ago-widget` could not have taken it anyway —
  `build.mjs` is one esbuild invocation with no dev/production mode and no `import.meta.env`.)
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
  beyond `sessionStorage`/`localStorage`'s existing, intended use. **Done — nothing else found.**
  Every other token use in both clients is an `Authorization: Bearer` request header (`ago-console`'s
  `api/*.ts`, `ago-widget`'s `attachments.ts`), never a query parameter, so nothing else can land in
  a URL. The hub query string is the sole exception, and moving it is this item's stated Out of scope.
  There are five `console.*` calls between the two repositories and none passes a token: three
  `console.error(message, err)` in `ago-console`, and `ago-widget`'s single `errors.ts` sink, which
  already carries its own "console.error only, never console.log" note. Nor can the error object
  smuggle one in — no `Error` `@microsoft/signalr` throws interpolates the token-bearing url
  (`HttpConnection`'s only url-carrying throw is `Cannot resolve '{url}'`, raised while normalising
  the `withUrl` argument, before any token is appended). Storage is as documented: `ago-console` keeps
  the OIDC user in `sessionStorage` via `WebStorageStateStore`, `ago-widget` keeps the visitor token
  under its own namespaced `localStorage` key. One residual this item cannot close: a *failed*
  request is logged by the browser itself, with the full url, independently of any application
  logging — one more reason the query-string placement deserves its own item.

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

- [x] Neither `ago-console` nor `ago-widget` prints a URL containing `access_token` to the browser
      console at their default (shipped) logging level — verified by actually connecting against a
      running API and reading the real console output, not by reading the configuration.
      **`ago-widget`**: fully end to end. `demo/index.html` served on `http://localhost:5173` (the
      demo site's `allowed_origins` carries both `:8080` and `:5173`, so no CORS bend was needed)
      against `Ago.Chat.Api` on `:5009`. Before, on opening the bubble, the console carried
      `Information: WebSocket connected to ws://localhost:5009/hubs/visitor?id=…&access_token=eyJ…`
      with a complete, valid visitor JWT. After, in a fresh tab with `localStorage` cleared: the
      negotiate returned 200, a real conversation id was created and stored, the composer was
      enabled — and the console was **empty**.
      **`ago-console`**: verified at the level below fully-interactive, and the gap is worth naming.
      A real operator token needs a Keycloak password login, which the session doing this work could
      not perform. Instead the console's *own* `OperatorConnection` class — same constructor, same
      `HubConnectionBuilder`, same `configureLogging` line — was driven over a real WebSocket from a
      throwaway harness page on the Vite dev server, using a credential-free visitor token from
      `POST /api/v1/visitor-sessions` with the hub path temporarily pointed at `/hubs/visitor`
      (reverted immediately; neither the harness nor the substitution is in the commit). Before:
      the same `Information: WebSocket connected to …&access_token=eyJ…` line. After: `CONNECTED`,
      with nothing in the console but Vite's own HMR client.

      **The remaining gap — a real `/hubs/operator` connect with a real operator JWT — was then
      closed by the managing session**, which can use these public throwaway credentials. Signed in
      as `demo-operator` against the local stack, the workspace loaded 50 real conversations and the
      hub badge read **`Live`** — a genuinely successful WebSocket connect, not a failed one that
      would have proven nothing. With that connection open, a console search for
      `access_token|WebSocket connected|eyJ` returned **no matches at all**, while the console was
      demonstrably not empty (Vite's HMR client, React's devtools notice and unrelated HTTP errors
      were all present). The `Information`-level line that carried the token is gone from the real
      operator path, observed rather than inferred from the shared code path.
- [x] Whatever development-mode behaviour is chosen is stated in the code with its reasoning, and
      cannot leak into a production build. Nothing is conditional, so there is no build mode for it
      to leak across — see the Status note above for why a conditional would have been the wrong
      shape here rather than merely unnecessary.
- [x] `npm run typecheck`/`lint`/`test`/`build` stay green in whichever repositories changed.
      `ago-console` 71 tests in 8 files; `ago-widget` 36 tests in 6 files, bundle 20.5 KB gzipped,
      unchanged against the 45 KB budget.

## Open questions

None — the rule is already written, the violation is confirmed live, and the fix is a documented
API of the library already in use. The only judgment call (what development mode does) is this
item's own to make and record.
