# The operator workspace speaks the tenant's chosen language

- **Stage**: 11
- **Status**: ready
- **Depends on**: `11-11-console-i18n-foundation-and-shell.md` (the string-table mechanism and locale
  resolution this item reuses without rebuilding).

## Why this exists

`11-11` translates the shell an operator sits inside; this item translates the screen they actually
work in - the queue (`OperatorShell`'s `/` route), the conversation thread, the composer, connection
states, empty/loading/error states, and every button and label `11-06`'s workspace built. This is the
highest-traffic surface in the product and the reason the family is split rather than done as one item
- it deserves its own enumeration pass, not a rushed one folded into `11-11`'s.

## Scope

- Enumerate every user-facing string across the workspace's own files (queue list, conversation view,
  composer, connection/reconnection indicator, attachment states, empty states, error states) by
  reading the source, `11-10`'s six-sweep model.
- Extend `11-11`'s `ConsoleStrings`/`en.ts`/`ru.ts` rather than starting a second table.
- Same locale source as `11-11` - the active site's `WidgetLocale`, already wired by then.

## Out of scope

- Everything `11-13` and `11-11` already claim.
- Translating a conversation's actual message content, an attachment's filename, or anything else that
  is data rather than UI chrome - unchanged from `11-11`'s identical boundary.

## Done when

- [ ] A console session against a `ru` site renders the queue, an open conversation, and the composer
      in Russian - DOM-tested, not asserted from config alone.
- [ ] The English-default regression case, matching `11-11`'s own bar.
- [ ] This item's own body lists every string it found and translated.

## Open questions

None yet - inherits `11-11`'s settled design call.
