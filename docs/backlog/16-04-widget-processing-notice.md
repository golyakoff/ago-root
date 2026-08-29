# The widget's processing notice, and who is answerable for what

- **Stage**: 16
- **Status**: done (2026-08-29, `ago-chat#122` + `ago-console#60` + `ago-widget#37`) — mechanism built
  and verified live end to end (real Postgres migration, a real running `Ago.Chat.Api`, and a real
  browser against the hostile demo page); the legal confirmation named in Open questions is still
  `ago-business`'s open gate, unaffected by this item's own done-when.
- **Depends on**: `11-01-widget-config-data-model-and-api.md` (shipped) — this is a third and fourth
  per-site configuration field in the same shape `adr/0029` already established, not a new
  configuration system

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

- [x] An ADR records the controller/processor split and the notice mechanism, with alternatives —
      `adr/0076`.
- [x] Two optional fields exist per site, editable in the console, delivered at bootstrap.
      `Ago.Chat.Domain.WidgetConfig.NoticeText`/`NoticeUrl`, validated at construction (whitespace/length
      bound on text, absolute `https://` on the URL — the `6-03` scheme-only reflex, not its SSRF check;
      `WidgetConfig`'s own remarks explain why not). One HTTP round trip, `UpdateWidgetConfigHandler`
      (`ago-chat`); `ago-console`'s existing `/settings/widget` screen gained a second panel
      ("Processing notice") in the same `<form>`/one Save button as the launcher fields, both English
      and Russian console strings. Carried on `POST /api/v1/visitor-sessions`'s response
      (`SiteConfigDto`/`VisitorSessionResponse`), the same additive-field-on-the-cached-DTO shape
      `11-01`/`11-10` already established — proven against real Postgres+RabbitMQ+Redis
      (`WidgetConfigCacheInvalidationEndToEndTests`, extended, not duplicated).
- [x] The widget renders them escaped, validates the URL, and shows nothing when both are empty.
      `ui/appearance.ts`'s `parseNoticeText`/`parseNoticeUrl` (courtesy re-check, never trust the wire
      value blindly — the same posture `parseWidgetColor`/`parseWidgetPosition` already take), a new
      `.ago-processing-notice` element built empty/hidden at construction and populated by
      `applyProcessingNotice` once `bootstrapSession` resolves, positioned directly under the header
      and above `.ago-messages` — the same place the `8-06` demo notice sits, for the same reason.
      `textContent`, never `innerHTML`; the link is `target="_blank" rel="noopener noreferrer"`, the
      same pattern `renderAttachmentInto` already uses. `ui/widget.test.ts`'s new "the panel's
      processing notice" block (9 tests) proves: the text renders before any message is typed, with the
      panel still closed and the composer still disabled and no `HubConnection` built at all; the link
      carries the right `href`/`target`/`rel`; text-only and link-only both render correctly; both
      empty renders nothing (`hidden`, empty `textContent`); markup-shaped text renders as literal text
      (an `<img onerror>` payload never becomes a DOM element); a non-`https://` URL drops the link but
      keeps the text; the link's own word ("Read more"/"Подробнее") follows the resolved locale.
- [x] Verified on a real third-party page. Actually run, not simulated: `Stage16AddSiteWidgetNotice`
      applied from scratch against a real local Postgres via `Ago.Chat.Migrator`; a real
      `Ago.Chat.Api` process, started against that database, answered
      `POST /api/v1/visitor-sessions` for the seeded `demo_site` tenant (its `sites` row's notice
      columns set directly, and its `allowed_origins` extended, both by hand for this verification —
      the same shape `11-01`'s own early verification used before a console screen existed) with
      `widgetNoticeText`/`widgetNoticeUrl` present on the wire; the widget's own hostile demo page
      (`demo/index.html`, served so `Origin` is real) loaded the freshly built bundle in a real browser
      tab against that Api, and direct DOM inspection confirmed: `.ago-processing-notice` present and
      not `hidden`, its text exactly the configured sentence, its link's `href`/`target`/`rel` correct,
      and — the point of `16-04`'s own Goal — `.ago-panel` still `hidden` and `.ago-input` still
      `disabled` at that moment, i.e. the notice was visible before the visitor could have typed
      anything or the widget had opened a connection. Opening the panel afterward kept the notice
      visible and in the correct DOM position (before `.ago-messages`).
- [x] `personal-data.md`'s "Who answers to whom" points at the ADR instead of describing a direction —
      done in this same change.

## A real gap this item's own brief left silent, resolved rather than guessed at

This item's Scope (above, unedited) explicitly requires a console surface: *"Console surface to edit
both, in `11-02`'s existing widget-config screen."* Built accordingly, in `ago-console`'s existing
`WidgetConfigPage.tsx` — a second `Panel` ("Processing notice") inside the same `<form>` the launcher
fields already use, one Save button, one PUT. Named here because the worker brief for this item's own
repository list omitted `ago-console` (naming only `ago-chat`/`ago-widget`/`ago-root`) while this
file's own Scope did not — the four repositories actually touched are `ago-chat`, `ago-console`,
`ago-widget`, `ago-root`, and a fourth worktree (`ago-console`, branch
`feat/16-04-widget-processing-notice`) was created to match what this file already asked for.

## Open questions

- **The legal confirmation itself** — whether a notice suffices, whether consent must be collected,
  and whether the processing clause in the tenant agreement says what it needs to. Belongs to
  `ago-business` and to a lawyer, tracked there, not here. This item deliberately builds the mechanism
  that any of those answers would need, and stops short of asserting which answer is right.

## What remains unverified

- **The console screen's own live verification** (an operator actually saving a notice through
  `/settings/widget` against a real running stack, the way `11-02`'s own Done-when was eventually
  confirmed) was not done - `npm run typecheck`/`lint`/`test`/`build` are all green for `ago-console`
  (442/442 tests), and the same field values were proven end to end through the API and the widget by
  hand, but the console form itself was not driven through a real browser. A reasonable next step, not
  a gap in what already shipped.
- **An unrelated, pre-existing bug found while starting `Ago.Chat.Api` locally for this item's own
  live-verification step** — already fixed and merged (`ago-chat#120`, 2026-08-29), landed by the
  managing session ahead of this item: `IBillingSubscriptionRepository`/`IBillingWebhookApplier` were
  referenced by several billing handlers but never registered themselves in
  `AddPostgresPersistence`, so `GetBillingStatusHandler`/`ProcessYooKassaWebhookHandler` would have
  thrown on their first real call. Not this item's own bug; found while unblocking this item's live
  verification, fixed and verified separately, not part of this item's diff.
