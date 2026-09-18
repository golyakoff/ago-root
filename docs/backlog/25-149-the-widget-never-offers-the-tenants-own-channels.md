# 25-149 · The widget never offers the tenant's own channels

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-18. The author's own request, reference: a Jivo-style card - Telegram, MAX (and
  every other channel a tenant has connected), each a tappable row with an icon, plus a "Написать в
  чат" row that falls through to the ordinary in-page conversation.
- **Depends on**: `25-148` merged (the wire contract this item renders). Touches `ago-widget` only -
  the "one worker per cross-repo task" rule does not apply here, since `25-148` already fixed the
  contract; there is nothing left to guess at.

## Scope

- A card, inserted directly above the composer (`this.composer.parentElement.insertBefore(...)`, the
  identical position `loadBookingModuleChip` already uses) - not a floating surface over the launcher.
  The panel already owns the focus trap, the Escape handler and the notice; a second floating surface
  would need its own, for a purely visual nuance against the reference screenshot.
- One row per entry in `session.channelLinks` (built when the session resolves, the same timing
  `loadBookingModuleChip` already uses so an auto-opened panel gets the card too) plus one final
  "Написать в чат" row, visually distinct (no brand colour). A session with an empty `channelLinks`
  shows no card at all - never an empty or single-row husk.
- Each channel row is a real `<a href="..." target="_blank" rel="noopener noreferrer">`, not a
  JS-driven navigation - a real link gives long-press/copy/open-in-app for free on a page this widget
  does not control. Icon: the provider's own official brand mark (the author's own decision,
  2026-09-18 - "as in the reference screenshot"), inline SVG through the existing `createSvgIcon`
  helper, one per `ChannelKind` this item covers (Telegram, MAX, VK, WhatsApp - Avito never appears,
  per `25-147`'s own scope). **An unrecognised `kind` on the wire renders with a neutral fallback icon
  and its own label, never dropped from the list and never a crash** - a channel this build does not
  yet have an icon for should still work as a link.
- "Написать в чат": hides the card, marks it dismissed, focuses the composer. Sends nothing. Does
  **not** call `connect()` - `completeSend`'s own lazy connect-on-first-send is what actually opens
  the hub, and this row must not undo that laziness (`adr/0148`).
- **Cadence, the author's own decision, 2026-09-18: shows on every panel open until dismissed** - not
  a one-time-per-visit reveal. Dismissal (either "Написать в чат" or the visitor's first sent message)
  persists per stored visitor identity in a new `WidgetStorage` key (`channel-switcher-dismissed` or
  similar), following the exact `WIDGET_STORAGE_DISCLOSURE`/getter-setter convention `has-known-
  contact-detail` used for `25-136` - **a new disclosure-array entry is a required part of this item,
  not optional documentation**.
- Styling reuses existing tokens only, nothing parallel: card background/radius from `.ago-panel`,
  row spacing/margin from `.ago-module-chip`, divider from `.ago-composer`'s own `border-top`. Brand
  colour per row is a small, widget-local per-`kind` constant, deliberately independent of
  `--ago-accent` - the same "must contrast against whatever a tenant configured" reasoning
  `--ago-unread-badge-bg`'s own comment already gives for itself.
- Accessibility: the card as a `role="group"` region with a label, inside the existing focus trap;
  each row's accessible name names the channel. New `WidgetStrings` entries for "Написать в чат" and
  the group's own label - channel names themselves are proper nouns, never translated.

## Where this is likely to go wrong

- **Coexistence with the auto-open greeting (`23-64`) and `25-140`'s own fix**: the greeting draws
  inside `.ago-messages`; this card sits below it, above the composer - they must not visually or
  structurally collide, and an auto-opened panel must not regain `25-140`'s fixed "Подключение…"
  phantom text because this card's own construction touched something adjacent.
- **Coexistence with `25-141`'s unread badge**: unrelated surfaces (closed launcher vs. open panel)
  - confirm a visitor with unread messages still sees their own transcript, with this card above the
  composer, not the card replacing the transcript.
- **VK is included in this first version by the author's own explicit decision, 2026-09-18**, despite
  `25-147`'s own note that the whole VK integration has never been exercised against a real token -
  if VK's row turns out to link somewhere wrong once tested live, that is `25-147`'s own bug to fix,
  not a reason to silently drop VK's row here.
- Do not build a second, parallel connection-timing or storage mechanism for the dismissal flag -
  reuse `WidgetStorage`'s existing per-identity clearing (`clearConversation`-style) so a new visitor
  identity is not silently born "already dismissed."

## Done when

- [ ] A site with two connected channels shows two rows plus "Написать в чат"; a site with none shows
      no card at all
- [ ] Tapping a Telegram row opens the tenant's own bot (`https://t.me/<username>?start=<code>` per
      `25-148`) in a new tab
- [ ] "Написать в чат" hides the card, focuses the composer, sends nothing, and never forces a
      connection
- [ ] The card reappears on every subsequent open until dismissed, then stays hidden for that visitor
      identity across a reload - with its own `WIDGET_STORAGE_DISCLOSURE` entry
- [ ] The card renders correctly on an auto-opened panel without reintroducing `25-140`'s phantom
      status text
- [ ] An unrecognised `kind` renders with a fallback icon rather than being dropped or crashing the
      list
- [ ] A visitor with unread messages still sees their own transcript, unaffected by this card
