# 25-173 · A connected channel only ever shows as a card above the composer

- **Stage**: 25
- **Status**: ready — **not yet verified against the real code**
- **Depends on**: `25-172` (this item reuses whatever icon assets/rendering mechanism that item lands -
  do not re-source or re-derive the four brand icons here)
- **Found**: 2026-09-19/20, while reviewing `25-172`'s icon replacement: the author's original ask was
  two things - real icons in the existing card, and a second, circular placement next to the launcher
  button. Deliberately split (`CLAUDE.md` rule 15: two different promises, "fix the icons" and "add a
  second placement + a setting for it") - filed here, not built alongside `25-172`, per the author's own
  explicit instruction to file this one rather than implement it now.

## What is actually true today

`25-149`'s channel-switcher card is the only place a visitor sees the channels a site has connected -
one row per channel, rendered above the composer, dismissible once and remembered per visitor
(`WidgetStorage`). There is no second placement, and no way for a tenant to choose one over the other.

## Goal

Two things, decided by the author, 2026-09-20:

1. **A second visual placement**: a row of small circular icons, one per connected channel, positioned
   next to the widget's own round launcher button (the closed-state chat toggle) - branded-logo circles,
   the same visual language `25-172`'s card icons use, just relocated and re-sized for this context.
2. **A per-tenant choice between the two placements**, surfaced in the console at **Каналы → Виджет**
   (`ago-console`'s `/channels/widget`, `WidgetConfigPage.tsx`) as a single setting, worded by the author
   as: *"показывать каналы: Баннеры над окном диалога / Круглые значки под окном диалога"* ("show
   channels: Banners above the chat window / Round icons below the chat window").

## Where this likely lives, to save the next session's own discovery pass

- **Domain**: a new fixed, validated field on `Ago.Chat.Domain.WidgetConfig`
  (`Ago.Chat.Domain/WidgetConfig.cs`), following the exact shape every other field on that type already
  uses (`Position`'s own two-member enum is the closest precedent, not `RequireContactConsent`'s bool -
  this is a choice between two named renderings, not an on/off flag). Something like
  `ChannelSwitcherPlacement { AboveComposer, BelowLauncher }`, defaulting to `AboveComposer` for every
  existing row - the same "an existing site must not change behaviour the moment this column exists"
  posture every other `WidgetConfig` field states for itself.
- **Migration**: one column, additive, matching `WidgetConfig`'s own migration history
  (`Stage11AddSiteWidgetConfig` and its followers) - not expand/contract, a plain new nullable-or-
  defaulted column.
- **Wire**: `SiteConfigDto`/the visitor-bootstrap payload already carries `WidgetConfig` to
  `ago-widget` for every other field on this type (`PrimaryColorHex`, `Position`, ...) - this rides the
  identical path, no new endpoint.
- **`ago-widget`**: `ui/widget.ts`'s `loadChannelSwitcherCard`/`buildChannelSwitcherRow` (25-149) becomes
  one of two renderers, chosen by the new config field - the "below launcher" renderer is new code, sized
  and positioned relative to `.ago-toggle` (check that class's own current CSS in `ui/styles.ts` before
  assuming a size), one circle per `channelLinks` entry, reusing `25-172`'s icon assets and rendering
  mechanism directly rather than inventing a second one.
- **`ago-console`**: `WidgetConfigPage.tsx` gains the two-option control (a segmented control or radio
  pair, matching whatever this page's own existing convention is for a small closed choice - check
  `AutoOpenDelaySeconds`'s own control on this same page first) with the author's exact wording above.

## Scope

- The new placement renders correctly with 1, 2, 3 and 4 connected channels (today's real maximum -
  `channelLinks` can only ever carry Telegram/MAX/VK/WhatsApp, `25-147`'s own scope).
- Switching the console setting changes what a visitor sees on their **next** bootstrap - this is
  ordinary `WidgetConfig` bootstrap-time behaviour, identical to `Position`/`PrimaryColorHex`, not a
  live-reload requirement.
- The existing above-composer card's own dismiss-and-remember behavour (`WidgetStorage`) is preserved
  for sites still on that placement; the new below-launcher placement has no equivalent "dismiss" concept
  to build (a persistent row of small badges, not an interruption) - state this choice explicitly rather
  than silently deciding it either way.

## Out of scope

- Re-deriving, re-approving or re-sizing the brand icon assets themselves - `25-172` owns that; this
  item consumes whatever it lands.
- A third placement, or per-channel placement choice (some channels above, some below) - one setting,
  two values, for the whole card.
- Any change to which channels can appear (`25-147`'s own scope stands).

## Open questions

- **Exact circle size/spacing next to the launcher** - not decided, needs a live mockup against the
  real `.ago-toggle` the way `25-172`'s icons were approved against a live HTML review before being
  implemented. Do the same here before writing widget CSS from a guess.
- **Console control shape** (segmented control vs. radio pair vs. dropdown) - whichever matches this
  page's own existing pattern most closely; not yet checked against the real `WidgetConfigPage.tsx`.

## Done when

- [ ] `WidgetConfig` carries the new placement field, migrated additively, defaulting to today's only
      behaviour (`AboveComposer`) for every existing site.
- [ ] `ago-console`'s `/channels/widget` page lets a tenant choose between the two placements, worded
      exactly as the author specified, and persists the choice through the existing `UpdateWidgetConfig`
      write path.
- [ ] A site set to the new placement renders one small circular branded icon per connected channel next
      to the launcher button, visually reviewed and approved the same way `25-172`'s icons were - a live
      HTML mockup shown before this box is ticked, not asserted from the code.
- [ ] A site left on the default placement is pixel-for-pixel unaffected - this item adds a second
      renderer, it does not touch the first one's own output.
