# The tenant never learns how to install the widget

- **Stage**: 10
- **Status**: ready — **and it sits directly in the first client's day-one path.**
- **Found**: 2026-09-02, while preparing a walkthrough checklist for `10-03`. Not from a report; from
  asking what the tenant does *after* signup succeeds.

## The gap

`10-03` ends well: a stranger registers through Keycloak, sets a site name and one embed origin, and
lands in the operator queue exactly as a returning operator would.

**And then there is nothing.** The console never tells her what to put on her website.

Checked rather than assumed, on both sides:

- **Console**: no `<script>` snippet anywhere in `ago-console/src`, and `publicKey` does not appear in
  the source at all — the console never so much as *fetches* the key, let alone renders it. There is a
  `WidgetConfigPage`, but it configures appearance; it does not tell her how to install anything.
- **API**: the only occurrences of `PublicKey` in `Ago.Chat.Api` are on the **visitor** side, where
  `POST /api/v1/visitor-sessions` *consumes* one. **Nothing returns a site's public key to the operator
  who owns that site.**

So the gap is not a missing screen on top of a working endpoint. It is both halves.

## Why it is worth its own item rather than a line in `10-03`

`10-03`'s Done-when is about signup completing and the console routing correctly, and it does that.
This is the next step in the same journey, and it is the step at which a real tenant is otherwise
stuck with a working account and no way to connect it to her shop.

For the first client — a single-person business whose website is one of her three intake channels —
the widget not being installable is the same as the widget not existing.

## Scope

- **An endpoint that returns the caller's own site public key**, gated the way every other
  operator-scoped read is. It is not a secret — it is designed to be embedded in a page anybody can
  view (`adr/0029`, `api-design.md`) — but it belongs to a site, so it is returned to that site's
  operators and not to anybody who asks.
- **A place in the console that shows the snippet, ready to copy**, with the key already in it. Copy
  written for someone who has never seen a `<script>` tag: what it is, where it goes, and how to tell
  it worked.
- **The embed origin she gave at signup is what the snippet must match.** If the two disagree the
  widget fails silently at the browser's origin check, which is unusually hard for a non-technical
  person to diagnose — so the screen should show the origin the site is actually configured with, next
  to the snippet, rather than leaving her to remember what she typed.

## Out of scope

- Verifying the installation from our side (a "we have seen a visitor session from your origin" check).
  Genuinely useful, and a bigger thing — it needs a signal, a screen state and a definition of
  "installed". Named here so it is a deliberate follow-up rather than an oversight.
- Changing how the widget bootstraps (`5-09`) or what the key is (`adr/0029`).
- Multiple origins per site. One is what signup collects today; widening that is its own decision.

## Done when

- [ ] An operator can see their own site's public key and a complete, copyable snippet, without asking
      anybody.
- [ ] An operator of one site **cannot** read another site's key — proven by test, since this is a new
      read of a tenant-scoped value and the failure mode is silent.
- [ ] The snippet, pasted onto a page served from the configured origin, produces a working widget —
      verified end to end rather than by inspecting the string.
- [ ] The configured origin is visible on the same screen as the snippet.
- [ ] The copy is comprehensible to someone who has never edited HTML. Judged by the author, not by me.

## Open questions

- **Where does it live** — a step at the end of onboarding, a permanent page, or both? A one-time step
  is missed by anyone who closes the tab; a permanent page is one more thing in the navigation. Both is
  probably right and costs little.
- **Does she need it before or after configuring the widget's appearance?** Installing first means she
  sees her own shop with a default-looking widget, which may be the better first impression than
  configuring something she has not yet seen anywhere.
