# whether a shop bought the calendar is written on the shop's own page

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. `adr/0151` is the decision it contradicts.
- **Found**: 2026-09-08, by the author, on the first working calendar grant.

## What the product promises, and what this breaks

**A shop drops one `<script>` tag on its site and never touches it again.** That is the premise in
`vision.md`, and it is what a shop is actually buying: an integration they do once.

`CalendarSetupPage` tells a tenant who has just been granted the calendar to paste a **new** snippet
carrying `data-booking="true"`, and `ago-widget`'s `parseConfig` reads exactly that:

```ts
bookingModuleEnabled: script.dataset["booking"] === "true",
```

So enabling a product a tenant has paid for requires **editing their own page**. If they miss it, the
grant succeeds, the module is registered, the quota is set, and the booking chip silently never
appears.

## It is also in the wrong place, not merely inconvenient

**Every other widget property already comes from the server.** `VisitorSessionResponse` carries the
primary colour, the position, the locale, the notice text and the notice URL — all fetched, none
declared on the page. Booking availability is the single exception.

And `SiteConfigDto` mentions modules **nowhere**: the server never tells the widget what this account
has. The one fact that is not the tenant's to assert is the only one the tenant's page asserts.

**That contradicts `adr/0151` directly.** An entitlement is granted by the platform and is not the
tenant's to configure. Here a shop's own HTML claims it — and a shop that writes
`data-booking="true"` with no grant is making a claim nothing on the page can check.

## How this survived

`22-22` looked straight at it. That item found `data-booking` was being handed the calendar's public
key while the widget compares it to the literal `"true"`, so **a real key evaluated to false and the
chip silently never rendered** — and fixed the comparison rather than asking why an entitlement was an
attribute at all. Its own comment even records the open question it did not answer: *whether a tenant
should meet two embed snippets at all.*

## Scope

- **The site's own configuration says whether booking is available**, delivered the way the colour and
  the locale already are, and the widget stops reading `data-booking`.
- **A grant reaches a live page within the refresh window `adr/0140` already sets** — a day — with no
  edit by the tenant. Whether that is fast enough for a tenant watching the console is worth stating;
  it is the same window every other appearance change lives with.
- **The old attribute is ignored, not honoured.** Any page still carrying it must not be able to turn
  booking on for an account that has not been granted it, or the fix leaves the hole it closed.

## Where this is likely to go wrong

- **The widget must not learn what a module is.** `adr/0065` keeps `Ago.Chat.*` ignorant of products;
  the same reasoning applies here. *"This site has a module with key K"* is what the response can
  carry — not a `bookingEnabled` boolean that names one product, and not a chip the widget knows how
  to draw only for calendars.
- **Existing installations.** Whatever ships must work for a page that was pasted before this and never
  touched again, which is the entire point.
- **`InstallSnippetPage` composes its own snippet too.** Two screens emitting embed code is the
  information-architecture question `22-22` recorded and declined; this item makes it sharper, because
  after the fix one of the two has nothing product-specific left to say.

## Done when

- [x] Granting the calendar makes booking appear on an untouched page. Proven end to end by
      `ux-gate/booking-module.spec.ts`: its fixture page (`demo/booking.html`) now carries nothing
      about booking at all, and the chip renders only because the stubbed handshake reports
      `enabledModules: ["calendar"]`.
- [x] The setup screen stops asking a tenant to change their site. `CalendarSetupPage` emits no
      embed snippet, and a test asserts the rendered screen contains no `data-booking`, so it
      cannot come back unnoticed.
- [x] A page asserting `data-booking="true"` without a grant gets no booking - the attribute is
      unread rather than merely undocumented. `config.test.ts` proves `readConfig` returns an
      identical config with it, without it, and with a real-looking calendar key as its value.
