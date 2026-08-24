# ADR-0029: Widget config is fixed fields, read at bootstrap

- **Status**: Accepted
- **Date**: 2026-08-24
- **Stage**: 11

## Context

`11-01` gives `Site` its first configurable, tenant-visible surface — a primary color and a launcher
position, reachable through an authenticated API and carried on the widget's own handshake. Two
judgment calls need a stated default rather than silent implementation, each with a real alternative a
reviewer would expect to see named:

1. How much styling surface to expose at all — two named fields, or something closer to a general
   theming system (arbitrary CSS, a free-text theme blob).
2. When a config change actually reaches an already-embedded widget — read once at bootstrap, or
   pushed live into a connection that is already open.

Both have a well-understood default this item follows rather than surveys at length (`6-03`'s own
precedent for a decision with one clearly right-sized answer).

## Decision

**Fixed, named, validated fields — not arbitrary CSS or a free-text theme blob.** `WidgetConfig`
carries exactly two values: a primary color (`#RRGGBB`, nullable — `null` means "use the widget's own
built-in default") and a launcher `Position` (`BottomRight` | `BottomLeft`). Nothing else, and no
open-ended styling channel.

The reason is a security boundary, not a taste preference. The widget's Shadow DOM isolation
(`embeddable-widget` skill) exists specifically to protect the widget's own rendering *from* the host
page it is embedded in. A config field that injects arbitrary style rules the other direction — into a
shadow tree the widget's own script controls, sourced from a value a tenant operator supplies through
an API — reopens that boundary from the inside. CSS is not inert data here: it can exfiltrate state via
attribute selectors, redress content by repositioning elements over each other, or abuse `:has()`/
animation-timing side channels even confined to a shadow root. None of that requires `<script>` — it is
a real attack surface with plain style rules alone. Two named, typed, validated fields sidestep the
question entirely: there is no rule syntax to sanitize because there is no rule syntax accepted.

**Config is read once, at bootstrap (page load) — not pushed live to an already-open widget.**
`POST /api/v1/visitor-sessions` is the one place the widget ever asks for its site config, and it asks
exactly once, at handshake time. Stage 11's own done-when text — "a site owner changes color/position
from the console and sees it reflected in the embedded widget on their own page" — reads as page-load
behavior, not as a promise about a tab that has been open since before the change. There is no existing
channel that would carry a mid-session config push anyway: the realtime protocol's `reconnect`/resume
mechanism resumes the same logical session and never re-runs the handshake (`realtime.md`), so
"pushing" this would mean building new mechanism, not reusing one. `caching.md`'s own framing for site
config — "changed rarely" — is the same judgment this decision leans on: building a live-push channel
for a value nobody expects to change mid-session is infrastructure this item has no stated need for.

**Named limitation, stated plainly**: a visitor with the widget already open on their page will not see
a changed color or position until that page is reloaded (a fresh handshake). This is a real, accepted
gap, not something silently redefined away by scoping the done-when text around it.

## Consequences

- Two typed fields, one migration, one CHECK constraint — the entire surface area is small enough to
  reason about completely; there is no sanitizer to keep correct as new CSS features ship.
- `11-04` (a real, open, unresolved product question — does "theme" ever need to grow past color and
  position: logo/avatar, a light/dark toggle, secondary colors, fonts) is explicitly *not* answered by
  this ADR. If that surface ever needs to grow, it is a new decision, not an extension slipped in here.
- An operator who changes a color expecting every currently-open visitor tab to update immediately will
  be wrong about that until they understand the bootstrap-time model — worth surfacing in `11-02`'s own
  console copy (e.g. "changes apply on next page load"), not silently assumed to be self-evident.
- No new realtime infrastructure, no new message type, no new hub method — the entire feature rides on
  a request/response pair the widget already makes.

## Alternatives considered

- **Arbitrary CSS or a free-text theme string, applied inside the widget's shadow root** — rejected:
  reopens the exact isolation boundary Shadow DOM exists to hold, for a feature this item has no
  concrete requirement to open. Revisit only alongside a real, scoped answer to what a sanitizer would
  actually need to allow — not as a default.
- **A structured but open-ended theme object (arbitrary key/value style tokens, still validated but not
  a fixed shape)** — a middle ground, rejected as premature: nothing in this item's own scope names a
  third field anyone actually needs yet, and a schema built to be "extensible" ahead of a real second
  caller is exactly the premature generalization `clean-architecture.md`'s qualifying rule warns against
  applying to a platform layer, and the same discipline applies here to a product-level config shape.
- **A live-push channel (a new hub method or a broadcast over the existing realtime connection) so an
  open widget updates without a reload** — rejected for now: real infrastructure (a new message type,
  a new subscription, a new client-side apply path in the widget bundle) for a value `caching.md`
  already characterizes as low-frequency. Nothing blocks building this later as its own item if a real
  need shows up; this ADR just declines to build it speculatively alongside `11-01`.
