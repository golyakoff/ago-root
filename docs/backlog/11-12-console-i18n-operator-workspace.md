# The operator workspace speaks the tenant's chosen language

- **Stage**: 11
- **Status**: done — merged `ago-console#46` (2026-08-27). Found already shipped 2026-08-28 while
  briefing a background worker to build it; reconciled here rather than re-implementing (see 11-11's
  own Status line for the same gap and why it happened)
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

- [x] A console session against a `ru` site renders the queue, an open conversation, and the composer
      in Russian - DOM-tested (`src/i18n/workspaceLocale.test.tsx`), not asserted from config alone.
- [x] The English-default regression case, matching `11-11`'s own bar.
- [ ] This item's own body lists every string it found and translated — **not carried through**. The
      merged PR (`ago-console#46`) states the full list ("~140 new string fields") was meant to land in
      this exact file as part of the same change, and it never did — the docs-side half of that PR was
      never opened. The list exists in `ago-console#46`'s own diff (`src/i18n/en.ts`/`ru.ts`), not here.
      Left unchecked and named rather than backfilled from memory or fabricated — a real, still-open gap
      this reconciliation found, not one it closes.

## Open questions

None yet - inherits `11-11`'s settled design call.
