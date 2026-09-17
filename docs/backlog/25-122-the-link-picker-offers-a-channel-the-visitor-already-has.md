# 25-122 · The link picker offers a channel the visitor already has

- **Stage**: 25
- **Depends on**: nothing
- **Status**: done — `ago-console#251`. Not yet deployed live (bundled with the next console deploy).
- **Found**: 2026-09-17, the author looking at `ChannelIdentitiesPanel` for a visitor with a Telegram
  identity already linked and verified, and asking why the "link a channel" dropdown still lists
  Telegram as a choice.

## What is actually true today

`ChannelIdentitiesPanel.tsx`'s own `LINKABLE_CHANNEL_KINDS` is a fixed six-member array
(`Telegram, WhatsApp, Vk, Max, Avito, Sms`), rendered into the link-picker `<Select>` unconditionally.
The component already has the visitor's own linked-and-verified `identities` list in state (it is what
the rows above the picker render from) but never reads it when building the picker's own options - so
an operator can pick a channel kind the visitor already has a confirmed identity for, generate a code,
and hand it to a visitor who has nothing to do with it (their existing identity for that kind is
already linked; re-sending the same `/linkidentity` code flow for it accomplishes nothing).

The component's own existing doc comment on `LINKABLE_CHANNEL_KINDS` already names a *different*,
deliberate simplification (the picker does not narrow to only the channel kinds this site has actually
configured a bot for) - this item is not that one. This item is specifically: exclude a kind the
*visitor* already has a verified identity for, which has nothing to do with which kinds the site has
configured.

## Scope

- Filter `LINKABLE_CHANNEL_KINDS` against `identities` (by `kind`) when building the picker's options -
  a kind already present in `identities` is not offered.
- If the currently-selected `pickerValue` becomes unavailable (the visitor just linked that kind, or a
  fresh page load already has it linked), fall back to the first still-available kind rather than
  rendering a `<select>` whose selected value matches no `<option>`.
- If every kind is already linked, hide the whole "link a channel" row (picker + button) - there is
  nothing left to offer.
- The site-level simplification the existing doc comment already names (not narrowing by which kinds
  the site has actually configured) is unchanged and out of scope here.

## Done when

- [x] A visitor with one linked-and-verified channel sees the picker offer only the other five kinds.
- [x] A visitor with every kind linked sees no link-a-channel row at all.
- [x] Linking a new channel (identity list updates) removes that kind from the picker without a reload -
      the picker's own options are derived from `identities` state on every render, so any future update
      to that state (unlink, preference change, or a live-refresh mechanism) already reflects correctly;
      no new plumbing needed.
- [x] Existing tests for the unfiltered case are updated - two new tests added, the existing
      "Generate code" test unaffected (its own fixture links nothing, so Telegram stays offered).
