# AGO Inbox: offline auto-reply (scripted, v1)

- **Stage**: 14
- **Status**: ready — scoped to the scripted keyword variant only; the LLM-backed variant is named
  below as a real, deliberately deferred option, not this item's job
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` — channel-agnostic by design,
  so it does not additionally depend on `14-02`/`14-03` shipping first, only on the concept those items
  also build against

## Goal

When no operator is available, a visitor gets an automatic reply instead of silence — on the widget
itself and on any connected channel (`14-02`'s MAX, `14-03`'s SMS, and whichever of `14-05`'s channels
eventually ship) alike, since the reply mechanism is deliberately built at the level `SendVisitorMessage`'s
own pipeline already unifies every channel into, not per-channel. Off by default, tenant-toggleable —
this is a real, named product capability, not a silent behaviour change to existing tenants' widgets.

## Context to read first

`docs/vision.md`'s corrected "Explicitly out of scope" list (this stage's own doc-consistency fix,
made in the same change that added this stage) — "bots/LLM auto-replies" is no longer blanket out of
scope; this item is exactly the capability that correction exists for, scoped to the scripted variant.
`docs/architecture/authorization.md`'s RBAC model — the new tenant-level toggle needs a permission
gating who can turn it on (`site:configure`, the same permission `5-08`'s admin role already holds for
this class of setting — reuse it, do not invent a new one for a single boolean). `docs/architecture/
caching.md` — the toggle's own value belongs in `Site`'s existing config, read the same cache-aside way
`GetSiteConfigByPublicKeyHandler` already reads every other per-site setting, not a new mechanism.

## Scope

- `Site` gains an `OfflineAutoReplyEnabled` flag (default `false`) and a small set of keyword→response
  scripted rules, configurable per site — the exact rule shape (simple keyword match vs. a small
  decision tree) is an implementation detail this item decides and states, not a genuine open product
  question; keep it deliberately simple, matching the product spec's own "cheap, predictable, no
  external dependency" framing for the v1 variant.
- A check at the point a visitor's message would otherwise wait for an operator (the existing "no
  operator assigned → waiting queue" path, `vision.md`'s own core-scenario 3): if
  `OfflineAutoReplyEnabled` and no operator is online for the site, send the matched scripted reply
  through the same outbound path the visitor's channel already uses (widget hub push, or `14-01`'s
  own outbound side for a channel conversation) — one mechanism, every channel, per this item's own
  Goal.
- Console surface (a small addition to whatever site-settings screen `5-08`'s admin role already
  reaches) to toggle the flag and edit the keyword rules.
- **The LLM-backed variant is explicitly named as a real, later option, not built here**: state
  plainly, in this item's own scope note, that a real LLM-backed conversational reply is a genuine
  per-message external-API cost and a different pricing/tier category from the flat scripted version —
  `CLAUDE.md`'s rule against inventing a "typical production" number applies directly to any specific
  model/provider/per-token price, so this item names the LLM variant as future work with an explicit
  open question (below) rather than picking a provider speculatively.

## Out of scope

- The LLM-backed auto-reply variant — named above, a real future item once the cost/provider question
  has a real answer, not this item's job.
- Per-channel customization of the scripted reply (a different message on SMS vs. the widget) — nothing
  in the product spec asks for this; the same reply text works everywhere in v1.
- Unattended booking triggered from an auto-reply — `21-01`, a separate, genuinely unsolved capability.

## Done when

- [ ] `Ago.Chat.Application.Tests`: a message arriving with no operator online and the flag enabled
      triggers the scripted reply; the same message with the flag disabled does not.
- [ ] Verified live against at least one real channel (the widget, or whichever of `14-02`/`14-03`
      already shipped by the time this item is picked up) — an offline visitor gets a real automatic
      reply, not just a passing unit test.
- [ ] Console toggle proven end to end: enabling/disabling from the console changes live behaviour
      without a redeploy, matching `11-*`'s own "live config, no rebuild" bar for widget customisation.
- [ ] `docs/vision.md`'s corrected out-of-scope note and this stage's own roadmap entry both read
      consistently with what actually shipped.

## Open questions

**Whether/when to build the LLM-backed variant, and which provider/pricing tier it would need** —
genuinely open, not decided here. `CLAUDE.md`'s rule against inventing numbers applies; a future item
should name a real provider and a real, cited per-token/per-message cost (the same research discipline
`adr/0026` applied to VPS hosting) before committing to build it, not before naming it as a real
roadmap possibility.
