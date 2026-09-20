# 25-173 · A connected channel only ever shows as a card above the composer

- **Stage**: 25
- **Status**: ready — every open question below is decided by the author, 2026-09-20, against a live
  HTML mockup (the same discipline `25-172`'s icons were approved under). Nothing left for a worker to
  guess or ask about.
- **Depends on**: `25-172` (this item reuses whatever icon assets/rendering mechanism that item lands -
  do not re-source or re-derive the four brand icons here)
- **Found**: 2026-09-19/20, while reviewing `25-172`'s icon replacement: the author's original ask was
  two things - real icons in the existing card, and a second, circular placement next to the launcher
  button. Deliberately split (`CLAUDE.md` rule 15: two different promises, "fix the icons" and "add a
  second placement + a setting for it") - filed here, not built alongside `25-172`.

## What is actually true today

`25-149`'s channel-switcher card is the only place a visitor sees the channels a site has connected -
one row per channel, rendered above the composer, dismissible once and remembered per visitor
(`WidgetStorage`). There is no second placement, and no way for a tenant to choose one over the other.

## Goal

1. **A second visual placement**: a horizontal row of small circular icons, one per connected channel,
   at the launcher's own height, growing away from it toward the panel's opening side - **not** stacked
   above the launcher (an earlier mockup draft got this wrong; the author corrected it with a screenshot
   showing the row beside the button, at the same vertical centre, the way a real chat widget's
   launcher-adjacent badges actually sit).
2. **A per-tenant choice between the two placements**, plus a size choice for the new one, both in the
   console - see Scope for the exact fields and their exact values, all confirmed live against a mockup
   (not guessed).

## Decided, against a live mockup - nothing left open

**Layout.** A horizontal row, vertically centred on the launcher (`.ago-toggle`, 56px/`3.5rem`), starting
right after it and growing toward whichever side the panel already opens from (`.ago-root`'s own
`right: 1.25rem` default, or `left: 1.25rem` under `.ago-position-left` - the row follows the same side
the launcher itself is pinned to, never a fixed side of its own).

**Three sizes, not a free number - a closed set of three, each with its own confirmed gap:**

| Size (Russian label) | Circle diameter | Gap between circles |
|---|---|---|
| Крупный | `56px` - exactly `.ago-toggle`'s own size | `10px` |
| Средний (**default**) | `46px` | `14px` |
| Мелкий | `34px` | `20px` |

The gap *grows* as the circles shrink, confirmed deliberately by the author (not a rendering mistake to
"fix" later) - smaller circles need more breathing room between them to still read as separate tap
targets.

**Console: a new, separate card, not new fields bolted onto an existing one.** `WidgetConfigPage.tsx`
gains a second `<Panel title="Каналы">` (the same `Panel` component every other section of this page
already uses - see `widgetPanelTitle`'s own `"Кнопка запуска"` card as the direct sibling), placed
**immediately after** the existing `"Кнопка запуска"` panel, containing exactly two fields, both plain
`<Select>`s inside `<Field>` - the identical shape `widgetPositionFieldLabel`'s own Select already uses
on this same page, for consistency (checked against the real page, not assumed):

1. **"Показывать каналы"** - `Баннеры над окном диалога` / `Круглые значки под окном диалога`.
2. **"Размер значков"** - `Крупный` / `Средний` / `Мелкий`, a plain three-option `<Select>` (an earlier
   mockup draft used radio buttons; the author asked for a `<Select>` instead, for consistency with every
   other closed-choice field on this page - the wording above `"Показывать каналы"`'s Select as the
   direct precedent) - **shown only when field 1 is set to the circles option**, hidden otherwise.

## Where this likely lives, to save the next session's own discovery pass

- **Domain**: two new fixed, validated fields on `Ago.Chat.Domain.WidgetConfig`
  (`Ago.Chat.Domain/WidgetConfig.cs`), following the exact shape `Position`'s own two-member enum
  already establishes for a closed choice (not `RequireContactConsent`'s bool):
  - `ChannelSwitcherPlacement { AboveComposer, BelowLauncher }`, defaulting to `AboveComposer`.
  - `ChannelSwitcherIconSize { Large, Medium, Small }`, defaulting to `Medium` - meaningful only when
    `ChannelSwitcherPlacement` is `BelowLauncher`, but still a real, always-present field (not nullable
    "only when relevant") - the same posture every other always-present `WidgetConfig` field takes,
    simpler than teaching the type and its consumers a conditional-presence rule for one field.
  Both default to today's only behaviour for every existing row - the same "an existing site must not
  change behaviour the moment this column exists" posture every other `WidgetConfig` field states for
  itself.
- **Migration**: two columns, additive, matching `WidgetConfig`'s own migration history
  (`Stage11AddSiteWidgetConfig` and its followers) - not expand/contract.
- **Wire**: `SiteConfigDto`/the visitor-bootstrap payload already carries `WidgetConfig` to
  `ago-widget` for every other field on this type (`PrimaryColorHex`, `Position`, ...) - both new fields
  ride the identical path, no new endpoint.
- **`ago-widget`**: `ui/widget.ts`'s `loadChannelSwitcherCard`/`buildChannelSwitcherRow` (25-149) becomes
  one of two renderers, chosen by `ChannelSwitcherPlacement`. The new "below launcher" renderer reads
  `ChannelSwitcherIconSize` for its own circle diameter/gap per the table above, is positioned relative
  to the real `.ago-toggle`/`.ago-root` CSS in `ui/styles.ts` (read the current values before writing new
  rules - they may have drifted since this item was filed), and reuses `25-172`'s icon assets and
  rendering mechanism directly rather than inventing a second one.
- **`ago-console`**: `WidgetConfigPage.tsx` gains the new `<Panel title="Каналы">` described above,
  placed via ordinary JSX ordering right after the existing `"Кнопка запуска"` panel - not inside it.

## Scope

- The new placement renders correctly with 1, 2, 3 and 4 connected channels (today's real maximum -
  `channelLinks` can only ever carry Telegram/MAX/VK/WhatsApp, `25-147`'s own scope).
- All three sizes render correctly, at the exact diameter/gap values in the table above.
- The size field is hidden in the console whenever the placement field is set to the above-composer
  option, and reappears the moment it's switched back - client-side conditional rendering, no page
  reload needed to see the field appear/disappear (the value itself still only takes effect for a
  visitor on their next bootstrap, per the next bullet).
- Switching either console setting changes what a visitor sees on their **next** bootstrap - ordinary
  `WidgetConfig` bootstrap-time behaviour, identical to `Position`/`PrimaryColorHex`, not a live-reload
  requirement.
- The existing above-composer card's own dismiss-and-remember behaviour (`WidgetStorage`) is preserved
  for sites still on that placement; the new below-launcher placement has no equivalent "dismiss" concept
  - a persistent row of small badges, not an interruption.

## Out of scope

- Re-deriving, re-approving or re-sizing the brand icon assets themselves - `25-172` owns that; this
  item consumes whatever it lands.
- A fourth size, a custom pixel value, or per-channel size choice - three named sizes, one choice, for
  the whole row.
- A third placement, or per-channel placement choice (some channels above, some below) - one setting,
  two values, for the whole card.
- Any change to which channels can appear (`25-147`'s own scope stands).

## Done when

- [ ] `WidgetConfig` carries both new fields, migrated additively, defaulting to today's only behaviour
      (`AboveComposer`/`Medium`) for every existing site.
- [ ] `ago-console`'s new `"Каналы"` panel, placed immediately after `"Кнопка запуска"`, lets a tenant
      choose the placement and (when relevant) the size, worded exactly as decided above, persisting
      through the existing `UpdateWidgetConfig` write path. The size field shows/hides live as the
      placement selection changes.
- [ ] A site set to the new placement renders a horizontal row of circular branded icons at the launcher's
      own height, growing away from it, at the exact diameter/gap the chosen size specifies - visually
      confirmed against a live render, not asserted from the code.
- [ ] A site left on the default placement/size is pixel-for-pixel unaffected - this item adds a second
      renderer, it does not touch the first one's own output.
