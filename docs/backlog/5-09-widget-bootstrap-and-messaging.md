# Widget: bootstrap, connection, messaging, demo host page

- **Stage**: 5
- **Status**: done
- **Depends on**: `5-01-per-site-cors.md` (the widget is inherently cross-origin - nothing here is
  provable for real until CORS actually allows it)

## Goal

`ago-widget` stops being an empty repository and becomes the real script `vision.md` describes: one
`<script data-site="...">` tag, and a visitor can hold a conversation. This is the other half of Stage
5's own done-when bar, alongside `5-07`'s console.

## Context to read first

**`.claude/skills/embeddable-widget/SKILL.md` in full** - this is not general context, it is the
constraint list this entire item must satisfy: Shadow DOM isolation, the `window.AgoChat` single-global
rule, the bundle-size ceiling enforced in CI, load-without-blocking, and "every entry point wrapped so
an internal failure degrades to no-widget, never a broken host page." `realtime.md`'s client protocol
section - identical requirement set to `5-07`'s console (`clientMessageId`, sequence-based ordering and
resume, jittered reconnect, the `reconnect` hint), implemented independently here since the widget and
console share no code (different repos, different runtime constraints - a widget cannot import a
console's dependency tree). `api-design.md`'s "Widget-facing constraints" (rate limits, `429`/
`Retry-After` handling). `ago-widget/README.md`'s own pointers.

## Scope

- Bootstrap: reads `data-site` off its own `<script>` tag, calls the visitor-session endpoint, mounts a
  Shadow DOM root, renders a minimal chat UI (open/close toggle, message thread, send box) styled
  entirely inside the shadow tree.
- Connection: SignalR client (or a hand-rolled minimal client if the full SignalR JS client blows the
  bundle budget - measure first, decide, and state the decision and the number, `CLAUDE.md`: "measure
  or stay silent"), visitor token in `localStorage` under a namespaced key, reconnect with backoff and
  jitter, resume by `lastKnownSequence`, obey `429`/`Retry-After` and the server's `reconnect` hint.
- `clientMessageId` on every send, reconciled on the ack - `realtime.md`'s wire contract already
  describes the server side; this is the client that first makes it real (matching `5-07`'s console,
  built independently, since neither runtime can share the other's code).
- Accessibility baseline named in the skill: keyboard reachable, trapped focus while open, `aria-live`
  for incoming messages, respects `prefers-reduced-motion`, readable at 200% zoom.
- CI: bundle-size check that fails the build over budget, unit tests for the protocol layer.
- `ago-widget/demo/`: a plain HTML host page, deliberately hostile (host page's own colliding CSS,
  globals, `!important` rules) to prove the isolation claims for real, not just by inspection.

## Out of scope

- Attachment upload/view - `5-10`.
- Anything about the operator side - `5-06`/`5-07`, a different repository, no shared code by design.
- A hosted CDN deployment pipeline - this item builds and tests the bundle; where it is actually
  published in a real deployment is out of scope for a portfolio-project local cluster.

## Done when

- [x] Manually verified against the local cluster, from the hostile demo host page, cross-origin
      through `5-01`'s real CORS policy (not same-origin, not with CORS disabled for the test) - a
      visitor opens the widget, sends and receives messages in real time, survives a forced disconnect/
      reconnect with no gap and no duplicate, and the host page's own styles/globals are provably
      unaffected (a screenshot or an automated DOM-isolation assertion, either is acceptable evidence).
      Verified live: `demo/` served from `http://localhost:8080` (the demo site's own allowed
      origin) against a real running `Ago.Chat.Api`. The widget mounted inside its Shadow DOM host,
      sent and received messages, and a real node death (the `Ago.Chat.Api` process killed and
      restarted with a stable `Auth:SigningKey`, matching how a real multi-replica overlay is
      configured rather than the single-dev-instance default `3-06` documents) was followed by a
      jittered reconnect (~10s) and a resume with the exact prior message present exactly once - no
      gap, no duplicate. Isolation proven programmatically, not just eyeballed: the host page's own
      hostile `!important` CSS and `Comic Sans MS` font stayed on the host page only, the widget's
      own colours/fonts were unaffected by either, a host-page global (`window.$`) the widget never
      touches still threw as the host page defined it, and the same embed snippet included twice
      produced exactly one widget instance (`window.AgoChat`'s "already embedded" guard).
- [x] `clientMessageId` dedup proven the same way `5-07`'s console proves it. Proven at two levels:
      the sender's own connection receiving its message twice by design (immediate echo, then the
      real fan-out redelivery - realtime.md's Fan-out path) never rendered a duplicate bubble across
      every send in the live session, and `protocol/dedup.test.ts` unit-tests `SeenMessageIds`
      directly (first-seen vs. repeat, capacity eviction). `VisitorHub.SendMessageAsync` still has
      no `clientMessageId` parameter (realtime.md's Client protocol section already called this "a
      design intent, not wired up" before this item, and that has not changed) - `clientMessageId`
      here is a *local* correlation id only, used to key an optimistic bubble until the real
      `MessageDto` echo reconciles it (`protocol/dedup.ts`'s doc comment has the detail), not a
      wire-level idempotency key. A genuine retry after an ambiguous mid-flight failure is
      deliberately *not* auto-retried (`connection.ts`'s `SendOutcomeUnknownError`) rather than
      risking a real duplicate the server has no way to catch - the same gap `5-07`'s own item text
      already flagged as possibly needing a small `ago-chat` addition, not newly discovered here.
- [x] Bundle size is measured, stated as a real number in the README, and CI fails a build that exceeds
      it. **18.4 KB gzipped** (68.6 KB raw), `ago-widget/README.md`. `build.mjs` gzips the real
      output and fails the build over a 45 KB budget; CI (`ago-widget/.github/workflows/ci.yml`)
      runs the same build on every push.
- [x] An internal widget error (thrown deliberately in a test) never surfaces as an unhandled exception
      on the host page - every entry point's own wrapping is what is being proven here. Proven live,
      not just by code inspection: `Storage.prototype.setItem` was monkey-patched to throw during a
      real send (exercising `connection.ts`'s `rememberSequence` -> `storage.setLastKnownSequence`
      path), with `window.onerror`/`unhandledrejection` listeners installed first - zero uncaught
      errors, and the message still sent and rendered correctly (`storage.ts`'s own try/catch
      degrades to "can't resume across a reload," never a throw).
- [x] Unit tests for the protocol layer (sequence handling, dedup, backoff), matching the skill's own
      testing bar. 16 tests across `protocol/backoff.test.ts`, `protocol/dedup.test.ts`,
      `protocol/sequence.test.ts`, `storage.test.ts`.

## Two real bugs found live, fixed here

Neither was visible from code review alone - both only showed up once the widget ran against a real
`Ago.Chat.Api` from a real cross-origin page:

1. **The send button never re-enabled after the first connect.** `renderConnectionState` computed
   `sendButton.disabled` once, at the moment the connection state changed - correct for that instant,
   but nothing re-ran the check as the visitor typed into an initially-empty textarea, so the button
   stayed disabled forever. Fixed by re-evaluating on every `input` event
   (`widget.ts`'s `updateSendButtonEnabled`).
2. **`@microsoft/signalr`'s default `withCredentials: true` broke the negotiate preflight** against
   the real per-site CORS policy, which does not (and should not) set
   `Access-Control-Allow-Credentials` - the widget never uses cookies. Fixed with an explicit
   `withCredentials: false` in `connection.ts`; written up for reuse in `api-design.md`'s
   Widget-facing constraints section, since `5-06`'s console will hit the identical default.

## Open questions - resolved

**SignalR vs. a hand-rolled client**: real `@microsoft/signalr`, confirmed by measurement rather than
guessed - the whole widget bundle is 18.4 KB gzipped, well inside the 45 KB budget this item set, and
the real client's version negotiation, WebSocket/long-polling fallback, and reconnect state machine
are worth far more than the bytes a hand-rolled client would have saved. `ago-widget/README.md` has
the number and the reasoning.
