# 25-210 · The panel title becomes a tenant-configurable greeting, with a friendlier built-in default

- **Stage**: 25
- **Status**: done — `ago-chat#351`, `ago-console#269`, `ago-widget#129`
- **Found**: 2026-09-22, the author, while picking sizes for `25-211`'s channel-switcher header bar:
  the header needs a title, the widget already hardcodes one ("Напишите нам"/"Chat with us",
  `chatWithUs` in `ago-widget/src/i18n/{ru,en}.ts`), and the author wants it (a) a friendlier default
  and (b) a tenant-editable setting rather than a fixed string, since the two chat-panel-shaped
  surfaces (the real panel and `25-211`'s new switcher header) both need to show the same words.
- **Depends on**: none. `25-211` depends on this - its header bar renders whatever this item produces.

## What this item is

Today `this.strings.chatWithUs` is the *only* source for the chat panel's own `<h1>` (`.ago-header
h1`, `ui/widget.ts`) - a fixed, non-configurable string, one per locale. This item does two things,
and they are one promise together: the **built-in default changes**, and a **tenant may override it**.

## Scope

- **The built-in default text changes**: `ago-widget/src/i18n/ru.ts`'s `chatWithUs` becomes
  `"Чем мы могли бы вам помочь?"` (was `"Напишите нам"`); `en.ts`'s own becomes a real English
  equivalent (state the exact string chosen and why, e.g. `"How can we help you?"` - not a literal
  word-for-word translation of the Russian, an equivalent greeting).
- **A new field on `Ago.Chat.Domain.WidgetConfig`** - read `WidgetConfig.cs` first; this joins
  `PrimaryColorHex`/`Position` on their terms, **not** `NoticeText`'s: those two are the type's only
  precedent for "no value configured yet still renders something," because a chat panel always needs
  a title the identical way it always needs a launcher position. `null` means "use the widget's own
  built-in default" (the new text above), never "show nothing" - do not copy `NoticeText`'s
  null-means-blank posture here, it is the wrong precedent for this field. Name it, validate it (a
  bound matching `MaxAutoOpenGreetingTextLength`'s own 300-character reasoning - this is one drawn
  line, not a legal disclosure needing `NoticeText`'s 500), and follow the constructor/`Default`
  pattern every other field on this record struct already establishes.
- **The Application/Api/wire path**: `UpdateWidgetConfig`/`GetWidgetConfig` (read the existing
  use cases - `NoticeText`'s own round trip is the template), `SiteConfigDto` gains the field for the
  cached, per-handshake bootstrap payload every other `WidgetConfig` field already rides.
- **`ago-console`'s `WidgetConfigPage.tsx`**: one more text field, next to the existing notice/greeting
  controls it already has (`widgetConfigApi.ts` for the wire shape) - a label, a bound character
  counter matching the 300-char limit, and a placeholder showing the built-in default so an empty
  field visibly means "the default text above," not "unset and therefore blank."
- **`ago-widget` consumption**: wherever `this.strings.chatWithUs` is read today, prefer the site's
  own configured value when present, fall back to the (new) i18n default otherwise - the identical
  "site value overrides, i18n string is the fallback" shape `AutoOpenGreetingText`/
  `ContactCaptureConfirmationText` already establish for their own consumers.

## Out of scope

- `25-211`'s own header-bar layout, sizing, or the channel-switcher's row dividers - this item only
  produces the text and the setting; `25-211` is the one that renders it.
- Any other panel string becoming configurable - scoped to this one title, the one the author asked
  about.

## Done when

- [x] `ago-widget`'s built-in default text changed in both locales, with the exact English string
      recorded here. **"How can we help you?"** - a real greeting equivalent, not a literal
      translation of the Russian.
- [x] `WidgetConfig` gains the new field, validated, with `null` meaning "use the built-in default" -
      proven by a test that an unset site renders the new default text, not an empty title.
- [~] The console can set and clear the override; clearing it reverts to the built-in default -
      **proven at the component/round-trip test level** (`WidgetConfigPage.test.tsx` against a mocked
      API, plus `ago-chat`'s own `UpdateWidgetConfigHandlerTests`), not against a fully running
      console+API+widget stack together. A true end-to-end live proof was not performed - stated
      plainly rather than assumed.
- [x] The widget's real chat-panel header (`.ago-header h1`) reads the configured value when set.
- [x] `dotnet format`/`build`/`test` (ago-chat), `npm` typecheck/lint/test (ago-widget, ago-console)
      all green; ago-widget `build`/`ux-gate`, ago-console `ux-gate` too.

## Outcome

Landed as `ago-chat#351`, `ago-console#269`, `ago-widget#129`. `WidgetConfig.PanelTitle` (new,
nullable, `MaxPanelTitleLength = 300`) joins `PrimaryColorHex`/`Position`'s "always renders something,
null means the built-in default" terms, deliberately not `NoticeText`'s "null means render nothing" -
a chat panel always needs a title. Rides the existing `UpdateWidgetConfig`/`GetWidgetConfig` round
trip and `SiteConfigDto`/`VisitorSessionResponse` wire path every other `WidgetConfig` field already
uses; new migration `Stage25AddSiteWidgetPanelTitle`. Console gains a field in the "Launcher" panel
with a bound character counter and a placeholder showing the real built-in default. Widget's
`chatWithUs` default text changes in both locales; `ui/widget.ts` resolves the site's own configured
value when present, falling back to the new default otherwise - never blank.

**Verified independently, beyond the implementing worker's own report**: re-ran `dotnet format`/
`build`/full test suite (ago-chat: Domain 784, Application 1486, FakeCrm 21, Architecture 52,
Concurrency 90, Integration 1496 - all green), `npm run typecheck`/`lint`/`test` for both console
(1672/1672) and widget (552/552), widget `build` (38.8 KB gzipped, budget 46 KB) and `ux-gate`
(16/16). All counts matched the worker's own report exactly.
