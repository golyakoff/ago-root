# Say on the demo page that anyone can read what you type there

- **Stage**: 8
- **Status**: in progress — the copy is written and verified rendered at desktop and phone width in a
  real browser against real builds of both repositories; the third done-when box (the *live*
  deployment) stays open until this is deployed, and is the only thing left
- **Depends on**: nothing

## Goal

A stranger typing into the public demo widget knows, before they type, that their message is readable
by anyone who opens the demo console. Today nothing says so anywhere.

## Why

The demo operator account is public by design — the credentials are handed out so a reviewer can see
the product work. The consequence, which was never stated, is that every conversation started from
`demo-shop1`/`demo-shop2` is visible to every stranger with the console open at the same time.

For a demo with invented data that is fine. It stops being fine the moment it is not said, because
people type real things into chat boxes — a name, a phone number, a question about their own business.
`architecture/personal-data.md`'s central point applies exactly here: message content is the one part
of this system's personal data that cannot be minimised by design, only by not collecting it. Telling
people is the cheapest control available and the only one that works before the fact.

## Scope

- One line on both demo pages, above or inside the widget, plain and unhedged: this is a public demo,
  anyone can read what you write here, do not type anything real.
- The same in the console's own sign-in area or first screen, so the person on the operator side knows
  they are looking at strangers' messages rather than a sandbox of their own.
- Nothing dressed up. A polite banner that people skim is worth less than a blunt sentence.

## Out of scope

- `16-04`'s tenant-configurable processing notice — the real product mechanism, for real tenants. This
  item is two lines of copy on our own demo pages and must not wait for it.
- Making the demo private, or gating it behind a form. It exists to be opened by strangers.
- Deleting demo conversations on a schedule. Worth having, and it is `15-04`'s mechanism plus a policy;
  not this.
- `8-07`'s per-viewer demo tenants, which would make this notice narrower but not unnecessary — the
  public demo pages stay shared even then.

## Done when

- [x] Both demo pages say it, in the widget's own flow rather than in a footer. The sentence is
      inside the widget panel, between the header and the message list, on both pages.
- [x] The console says it too, on the way in — and, deliberately, does not stop saying it afterwards.
      See **Outcome** for why "on the way in" alone could not be honoured literally.
- [ ] Checked on the live deployment, on a phone-width screen as well. **Phone width: done** (375×812
      and 375×667, both demo pages and the console, measured in a real browser). **Live deployment:
      not done** — this was built and verified against local builds; nothing has been deployed to
      `demo-shop1`/`demo-shop2`/`console` yet, and this box stays open until someone opens the three
      real URLs on a phone.

## Outcome

**What the copy says.** Three statements of fact and one instruction, in that order, everywhere:

- Widget panel, both demo pages: *"This is a public demo. Anyone who opens the demo operator console
  can read what you type here. Do not type anything real."*
- Console shell, on the demo deployment only: *"This is a public demo console. Its login is published
  on the demo pages, so anyone can sign in here — every conversation in it was typed by a stranger,
  who was told you can read it. Do not type anything real."*
- Above the fold on each demo page, additionally: the same fact naming the published login as the
  reason. `public-demo-2` adds one clause the other does not need, because that page's whole subject
  is tenant isolation and the reassurance it gives is easy to over-read: *"Isolation from the other
  tenant is real; privacy from other visitors of this one is not."*

**Why the wording is shaped that way.** Naming the *mechanism* (the login is printed on this page)
rather than asserting the conclusion (this is not private) is what makes it credible rather than
boilerplate; a reader can check it against the credential box a few centimetres below. The final
sentence is an instruction, not a caveat, because the item's own point is that a notice people skim
is worth less than one that tells them what to do. Nothing hedges — no "please note", no "may be",
no icon, no dismiss control. Both sides of the demo are told the *same* fact from their own side,
which is the pairing the item asks for.

**Nothing is dismissible, on either side.** The fact does not stop being true once read, and the
mistake it guards against — typing a real phone number, or answering as if the queue were a private
sandbox — is available on every keystroke rather than once at open time. A close button would remove
the warning from precisely the moments it applies.

**The console could not honour "on the way in" literally, and says so instead.** This repository has
no sign-in screen: `RequireAuth` redirects to Keycloak from an effect, so the only thing `ago-console`
renders on the way in is a spinner replaced within a few hundred milliseconds by a page Keycloak
owns. A notice living only in that flash would satisfy the letter of the item and none of its intent.
It is therefore rendered by the shell frame — present on that spinner, on the OIDC callback, and
standing on every operator screen afterwards. That is a deliberate widening of the item's scope, and
the item was slightly wrong to assume a sign-in screen existed to put copy on.

**Both notices are switched on per deployment, never hard-coded.** The widget reads
`data-public-demo="true"` from the `<script>` tag (set on our own two demo pages and nowhere else);
the console reads `VITE_PUBLIC_DEMO=true` from `.env.production`. Both default to off and both
require the exact string `"true"`. The reason is that neither bundle is demo-only — the same widget
is what a real shop embeds and the same console is what a real tenant signs into, so hard-coding the
sentence would make it a lie the first time either happens, and hard-coding its absence would leave
the public deployment silent. Both are *flags*, not free-text notice strings, so that `16-04`'s
tenant-configurable processing notice is left free to choose its own server-driven shape rather than
inheriting a host-page-authored string from here.

**Legibility on two different palettes.** `public-demo` is light and `public-demo-2` is dark, so the
page-level line is styled separately per page rather than written once and inherited: 15.45:1 on the
light page, 12.07:1 on the dark one (WCAG 2.1, measured on the rendered pages, not estimated). The
widget's own line is identical on both — 8.74:1 — because the panel's background is white regardless
of the host page. The console strip reuses the existing `--ago-danger`/`--ago-danger-tint` pair
rather than introducing an unmeasured colour, 6.90:1 as `tokens.css` already records. Spending the
danger colour on something that is not an error is deliberate: it is the loudest thing the palette
already contains, and this should be the loudest thing on the screen.

**What was verified, and how.** Both demo pages served from a real build of the widget bundle
(`AGO_API_BASE_URL` set, `npm run build`), and the console served from a real production `vite build`
that picked `.env.production` up. Measured in a live browser at 1440×900, 1280×720, 375×812 and
375×667: the notice's position in the panel/shell, its computed colours and contrast ratios, that no
page overflows horizontally at 375, and that the widget panel and its composer still fit a 667px-tall
viewport with the strip added. Widget bundle: 20.5 → 21.0 KB gzipped, both numbers measured on the
same machine with and without this change.

**Not verified, and left open on purpose.** (1) The live deployment — see the third done-when box.
(2) The console's *signed-in* screens: reaching them needs a password typed into Keycloak's own form,
which the session that wrote this could not do. The strip was confirmed rendering on the callback
screen, in the same shell position both shells use, and the `100dvh` workspace variant's layout was
exercised by injecting its class — but nobody has yet seen the strip above a real conversation queue.

## Open questions

None.
