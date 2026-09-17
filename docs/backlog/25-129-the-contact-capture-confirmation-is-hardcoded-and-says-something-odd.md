# 25-129 · The contact-capture confirmation is hardcoded, and says something odd

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: 2026-09-17, the author noticing the widget's own post-"Представиться" confirmation text
  ("Спасибо - мы свяжемся с вами.") is both wrong (the visitor is already mid-conversation; nobody is
  going to separately "get back to" them) and un-configurable.

## What is actually true today

`ui/contactCapture.ts:232`: once a visitor submits their name/phone/email, the control replaces itself
with a fixed sentence, `strings.contactCaptureConfirmation` - a plain, hardcoded, widget-owned i18n
string (`i18n/ru.ts`: `"Спасибо - мы свяжемся с вами."`), the same for every tenant, on every site.
`ContactCaptureResult.name` (the visitor's own submitted name) is already in scope at the exact call
site that sets this text - nothing new needs to be threaded through to reach it.

## Scope

**Backend (`ago-chat`)**: a new, additive, nullable field on `WidgetConfig` alongside
`NoticeText`/`AutoOpenGreetingText` - this is a *site-owner* (tenant) setting, not a per-conversation or
per-operator one, matching exactly how `NoticeText`/`AutoOpenGreetingText` are already scoped and
stored. Name it for what it is (e.g. `ContactCaptureConfirmationText`), threaded through the same
handlers/DTOs those two fields already go through (`GetWidgetConfigHandler`/`UpdateWidgetConfigHandler`,
`WidgetConfigDto`, `Site.WidgetConfig`) - read those two fields' own full path end to end before writing
this one, they are the template. Check whether this needs a migration (a genuinely new column) or can
reuse an existing generic-text slot - do not assume either way.

**Console (`ago-console`)**: a new field on the tenant's widget settings screen (wherever
`NoticeText`/`AutoOpenGreetingText` are already configured - find that screen, do not guess a new one),
with a sensible label and a placeholder showing the default. Supports the same `{name}` interpolation
the widget will support (state clearly what placeholder syntax was chosen, e.g. `{name}`, and use it
consistently on both sides of the wire).

**Widget (`ago-widget`)**: `protocol/types.ts` gains the new field (mirroring `widgetNoticeText`'s own
`string | null` shape); `ui/appearance.ts` gains a `parseContactCaptureConfirmationText`-shaped
normaliser (`parseAutoOpenGreetingText`'s own doc comment and shape is the closer of the two existing
precedents - read it, not just `parseNoticeText`, since this field's fallback story is closer to that
one's). `ui/contactCapture.ts`'s own confirmation render substitutes the tenant's configured text
(with `{name}` replaced by the real submitted name) when set, falling back to a **new, better** default
sentence when the tenant has not configured one - the new default itself should read like "Спасибо,
{name}, ваши контакты добавлены." (or the closer equivalent this project's own copy conventions
prefer), not the old "мы свяжемся с вами" wording, since the old wording is exactly the defect being
fixed and must not survive as the unconfigured fallback either.

## Where this is likely to go wrong

- **This is a tenant/site-level setting, never an operator- or conversation-level one** - do not wire
  it through any operator-facing screen or per-conversation config; the console's own widget-settings
  screen (the one `NoticeText`/`AutoOpenGreetingText` already live on) is the only place a tenant sets
  this.
- **`{name}` substitution happens in the widget**, where the real submitted name is already in scope -
  do not try to interpolate it server-side, since the server never sees which visitor is about to
  submit before they do.
- **The new default replaces the old hardcoded string as the fallback** - an unconfigured site must not
  keep showing "мы свяжемся с вами"; the fix is the new default, not just a way to override the old one.
- **This is a genuine three-repo item** - write the whole vertical slice yourself (backend field →
  console setting → widget consumption) rather than guessing the contract on one side and hoping it
  matches; `docs/architecture/repositories.md` and this session's own recent precedent
  (`widgetNoticeText`/`widgetAttractAttention`, both landed as single, complete cross-repo slices) are
  the model.

## Done when

- [ ] A tenant can set a custom confirmation text in the console's widget settings, and it renders
      (with `{name}` substituted) in the widget after a real contact-capture submission.
- [ ] A tenant who has not configured one sees the new, better default - never the old "мы свяжемся с
      вами" wording.
- [ ] The setting is genuinely tenant-scoped - no operator- or conversation-level path to set it exists.
