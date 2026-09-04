# the embed snippet on `/calendar/setup` cannot work

- **Stage**: 22
- **Status**: in review (2026-09-04), `ago-console#102`
- **Found**: 2026-09-04, by the interface inventory (`docs/design/ui-inventory.md`), and confirmed by
  reading `ago-widget/src/config.ts` rather than by reasoning about it.

## The finding

`/calendar/setup` shows a tenant the tag to paste on their own site, described as *"One tag: the chat
widget and the booking flow arrive together."* It was this:

```html
<script src="https://…/ago-chat.js"
        data-site="YOUR-CHAT-SITE-KEY"
        data-booking="${publicKey}"
        data-booking-api="${calendarApiBaseUrl}"
        async></script>
```

**Four things are wrong with four different consequences.**

1. **The host is a literal ellipsis.** Nothing loads.
2. **The filename is `ago-chat.js`.** `#342` renamed the bundle to `widget.js` so the internal product
   name stops leaking into a tenant's HTML — `InstallSnippetPage` in the same repository carries the
   comment recording that rename, and emits the right name.
3. **`data-booking-api` is read by nothing.** `parseConfig` accepts exactly `data-site`, `data-api`,
   `data-booking`, `data-demo-notice`, `data-public-demo`.
4. **`data-booking` is given the tenant's calendar public key**, while the widget evaluates
   `script.dataset["booking"] === "true"`. A real key is not the string `"true"`, so
   `bookingModuleEnabled` is **false**.

## Why the fourth is the dangerous one

The first two are obvious the moment anyone looks. The fourth **fails silently and looks like
success**: with the host and filename fixed by hand, the widget loads, chat works, and the booking
chip simply never appears. Nothing errors. A shop owner concludes booking is not switched on and
contacts support; support looks at the tenant's modules and sees it enabled.

This sits on the flow `docs/design/flows.md` names as the weakest in the product — a tenant between
signing up and having something working on their own site.

## How it got this way

`InstallSnippetPage` does the same job correctly: it composes the URL from `apiBaseUrl`, uses the real
public key it fetched, and names `widget.js`. This page was copied from an older version of it and
never followed it forward — including past `#342`.

## What the fix deliberately leaves alone

**The site key stays a placeholder.** It is the *chat* site's key, and reading it needs
`site:configure` (`GET /api/v1/sites/{siteId}/installation`). This screen is reached with
`calendar:configure`. Fetching it would either fail for a calendar-only operator or widen this
screen's gate, and neither is a bug fix. The copy names where to get the key instead.

**Whether a tenant should meet two embed snippets at all is not answered here.** One page hands out
the chat tag, another hands out the chat-plus-booking tag, and the second is gated on a permission
that cannot read the value the first one owns. That is an information-architecture question, it is
recorded in `ui-inventory.md`, and it belongs to the design pass — not to a fix that must land before
a deploy.

## Done when

- [ ] Every attribute in the snippet is one `ago-widget/src/config.ts` actually reads, and the
      values are the ones it accepts — checked against that file, not remembered.
- [ ] The URL is composed from configuration the way `InstallSnippetPage` composes it, so the two
      cannot drift again.
- [ ] The tenant is told where to get the site key rather than left with a placeholder and no route.
