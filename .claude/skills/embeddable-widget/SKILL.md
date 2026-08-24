---
name: embeddable-widget
description: Build or change the AGO Chat widget - the script embedded on third-party sites. Covers isolation, bundle size, bootstrap, reconnect, and the security rules for running on a page you do not control. Use for any change in the ago-widget repository.
---

# The embeddable widget

The widget runs on someone else's page, next to their CSS, their globals, and their bugs. Every rule
here exists because the widget cannot assume anything about its host.

## Hard constraints

- **Style isolation via Shadow DOM.** No global CSS, no CSS reset applied to the host, no `!important`
  arms race. The host's styles must not leak in and ours must not leak out.
- **No global namespace pollution.** One optional global (`window.AgoChat`), everything else in a
  module scope. Never touch `window.$`, prototypes, or existing globals.
- **Bundle budget** (gzipped, enforced in CI, stated in the README): a hard ceiling, checked on every
  build. No framework whose runtime dwarfs the feature. A dependency that adds meaningfully to the
  bundle needs a written justification.
- **Load without blocking the host.** `async` script, lazy-init, nothing heavy before first
  interaction, no synchronous layout work on load.
- **Never break the host page.** Every entry point is wrapped so an internal failure degrades to "no
  widget", never to a broken site. An exception escaping into a shop's page is the worst possible bug.

## Bootstrap

`data-site` on the script tag identifies the tenant. The site key is public and grants only the
ability to start a visitor session - anything else requires the signed visitor token. The handshake
returns the site's widget settings (cached server-side per `caching.md`) and the visitor's history
cursor. **Shipped in `11-03`**: the handshake call itself now fires eagerly at mount time rather than
lazily on first open (position has to be known before the closed launcher ever renders), and the
returned primary color/launcher position are actually applied to the rendered widget - a missing or
malformed value falls back to the widget's own built-in default silently, per the "never break the
host page" rule above.

## Connection behaviour

- Reconnect with exponential backoff **and jitter**. Without jitter a rolling deploy turns every
  widget on the internet into a synchronised retry storm (`adr/0010`).
- Resume by sending the last known `sequence` per conversation; render the delta. Never re-fetch
  everything on reconnect.
- Order strictly by `sequence`, never by arrival or a client clock.
- `clientMessageId` on every send, so a retry after a flaky connection cannot create a duplicate
  message; reconcile on the ack.
- Honour `429` and `Retry-After`; back off rather than hammering.
- Long-polling fallback must work - corporate proxies still block WebSockets.

## Storage and privacy

- Visitor token in `localStorage` under a namespaced key, scoped to one site. No cookies on the host
  domain, no fingerprinting, no reading anything the host page put in storage.
- Never log or transmit page content, form values, or URLs beyond what the tenant explicitly enabled.

## Uploads

Presigned direct upload only (`adr/0008`): ask the API for a slot, PUT to storage, confirm. Show
progress from the PUT, enforce the size ceiling client-side as a courtesy while assuming the server
enforces it for real.

## Accessibility and UX baseline

Keyboard reachable, focus trapped only while open, `aria-live` for incoming messages, respects
`prefers-reduced-motion`, readable at 200% zoom. This is small work that a reviewer notices
immediately, because most portfolio widgets skip it.

## Testing

Unit tests for the protocol layer (sequence handling, dedup, backoff). One integration page under
`ago-widget/demo/` that loads the built bundle exactly as a shop would - a plain HTML file
with one script tag, deliberately styled hostilely to prove isolation.
