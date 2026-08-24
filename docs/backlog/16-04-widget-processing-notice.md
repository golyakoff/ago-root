# The widget's processing notice, and who is answerable for what

- **Stage**: 16
- **Status**: ready — the product shape is decided (author, 2026-08-25: the widget carries the notice);
  what remains open is the legal confirmation, which is `ago-business`'s gate and does not block
  building the mechanism
- **Depends on**: `11-01-widget-config-data-model-and-api.md` (shipped) — this is a third per-site
  configuration field in the same shape `adr/0029` already established, not a new configuration system

## Goal

A visitor opening the widget can see, before they type anything, who processes what they are about to
write and where to read the details — with the text and the link supplied by the tenant, since it is
the tenant's relationship with their own customer. And the split of responsibility behind that — AGO
as controller for its own account holders, as processor acting on the tenant's instruction for
visitors' conversations — is written down as an ADR instead of being implied by the code.

## Context to read first

`docs/architecture/personal-data.md`'s "Who answers to whom" — the working direction this item turns
into an ADR, and its reasoning. `adr/0029` — the widget-config decision this item extends: fixed,
named, validated fields, read at bootstrap, never arbitrary injected content. That constraint applies
here with more force than it did to a colour, since this field is text and a link supplied by a third
party and rendered inside somebody's page. `docs/backlog/11-03-widget-bootstrap-applies-config.md` —
how config reaches the widget today. `docs/backlog/11-01`'s handshake response — where the field goes.
The `embeddable-widget` skill's security rules — what may and may not be rendered in a script running
on a page AGO does not control.

## Scope

- **An ADR** naming the controller/processor split, its consequences (tenant-initiated deletion and
  export are product requirements, `16-02`/`16-03`), and the fact that AGO supplies the notice
  mechanism while the tenant owns the text and its accuracy. Written as a decision with alternatives,
  the way `adr/README.md` requires; the lawyer's confirmation is recorded when it arrives rather than
  waited for before writing anything down.
- **Two per-site fields** in `11-01`'s existing widget configuration: notice text and a URL to the
  tenant's own policy. Both optional — a tenant that has its own arrangement and does not want a
  notice in the widget must be able to leave them empty, and the widget then shows nothing.
- **Rendered safely**: the text is text, escaped, never HTML; the URL is validated (`https://` only,
  the same reflex `6-03` applied to webhook endpoints) and opened in a new context. This is exactly
  the "arbitrary injection" risk `adr/0029` refused for styling, appearing again in a field that
  looks harmless.
- Console surface to edit both, in `11-02`'s existing widget-config screen.
- Default: empty, and therefore nothing shown. A default notice written by AGO would be AGO asserting
  a legal position on the tenant's behalf, which is the one thing this item must not do.
- Verified on a real embedded page, not only in the console.

## Out of scope

- **A consent gate** — blocking the chat until the visitor clicks something. That is a different
  product decision with a real conversion cost, and whether it is required at all is exactly the legal
  question this item does not answer. If the lawyer says a notice is insufficient, that becomes its own
  item with its own UX argument.
- Cookie or storage banners. The widget's own token storage is functional to the product; whether it
  needs its own disclosure is part of the same legal question.
- Writing the tenant's policy text for them, or validating that what they wrote is true.
- AGO's own published policy and offer — `ago-business`, in Russian, published on `ago-landing`.
- Anything about AGO Calendar's booking widget (`20-06`), which will need the same treatment and
  should reuse this one rather than invent a second.

## Done when

- [ ] An ADR records the controller/processor split and the notice mechanism, with alternatives.
- [ ] Two optional fields exist per site, editable in the console, delivered at bootstrap.
- [ ] The widget renders them escaped, validates the URL, and shows nothing when both are empty.
- [ ] Verified on a real third-party page.
- [ ] `personal-data.md`'s "Who answers to whom" points at the ADR instead of describing a direction.

## Open questions

- **The legal confirmation itself** — whether a notice suffices, whether consent must be collected,
  and whether the processing clause in the tenant agreement says what it needs to. Belongs to
  `ago-business` and to a lawyer, tracked there, not here. This item deliberately builds the mechanism
  that any of those answers would need, and stops short of asserting which answer is right.
