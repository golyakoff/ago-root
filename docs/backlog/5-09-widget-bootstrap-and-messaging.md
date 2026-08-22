# Widget: bootstrap, connection, messaging, demo host page

- **Stage**: 5
- **Status**: ready
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

- [ ] Manually verified against the local cluster, from the hostile demo host page, cross-origin
      through `5-01`'s real CORS policy (not same-origin, not with CORS disabled for the test) - a
      visitor opens the widget, sends and receives messages in real time, survives a forced disconnect/
      reconnect with no gap and no duplicate, and the host page's own styles/globals are provably
      unaffected (a screenshot or an automated DOM-isolation assertion, either is acceptable evidence).
- [ ] `clientMessageId` dedup proven the same way `5-07`'s console proves it.
- [ ] Bundle size is measured, stated as a real number in the README, and CI fails a build that exceeds
      it.
- [ ] An internal widget error (thrown deliberately in a test) never surfaces as an unhandled exception
      on the host page - every entry point's own wrapping is what is being proven here.
- [ ] Unit tests for the protocol layer (sequence handling, dedup, backoff), matching the skill's own
      testing bar.

## Open questions

**Needs the author's decision, but not blocking - can be resolved during the item itself with the
stated fallback**: full SignalR JS client vs. a minimal hand-rolled WebSocket/long-polling client, to
be decided once the bundle-size measurement makes the trade-off concrete rather than guessed at.
Default to trying the real SignalR client first (less protocol code to get right and re-verify against
`realtime.md`) and falling back to a hand-rolled client only if it provably blows the budget this item
sets.
