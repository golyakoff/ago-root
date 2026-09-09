# 25-16 · Calendar timezone becomes a localized dropdown

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-09, the author testing the calendar setup screen

## What is actually true

`CalendarSetupPage.tsx`'s timezone field is a free-text `<Input>` bound to a plain string, defaulting
to `"Europe/Moscow"`. A tenant types an IANA zone id by hand, in English, with no help and no
validation beyond whatever the calendar API itself rejects.

## Scope

- Replace the free-text input with a `<select>` (or equivalent) offering the zones a tenant would
  actually need, each shown localized to the interface language and in the format
  **"Европа/Москва (+03:00)"** — the zone's own city name(s) translated, the offset live rather than a
  stored guess (`Intl.DateTimeFormat`'s own `timeZoneName: "shortOffset"` — or the equivalent — reads
  the current offset, which matters for a zone with DST elsewhere in the world even though `24-17`
  already settled that this deployment's own zones do not observe it).
- The stored value on write is unchanged: still the IANA zone id. Only the picker changes.
- The list of offered zones should be reasonably short and relevant — a Russian-market chat/calendar
  product's tenants are realistically choosing among a handful of zones, not the full IANA database of
  hundreds. Pick a defensible set (e.g. `Intl.supportedValuesOf("timeZone")` filtered to zones actually
  relevant to this deployment's market, or a curated list) and say which you picked and why.

## Where this is likely to go wrong

- **Localizing the zone name is not the same as translating a lookup table.** `Intl.DisplayNames`
  (`type: "timeZone" language"`) or a curated translation map both work; whichever is chosen, verify it
  actually produces "Европа/Москва" rather than falling back to the raw IANA id when the interface is
  in Russian — some `Intl` implementations do not localize timezone city names at all, and this must be
  checked live, not assumed.
- **An existing site's stored zone id must still resolve to a selectable option** — a dropdown that
  cannot represent the value already saved would force a tenant to lose their setting on the first
  visit to this screen.

## Done when

- [ ] The timezone field on `CalendarSetupPage.tsx` is a dropdown, not free text.
- [ ] Each option is shown in the interface's own language, formatted "City/City (+HH:MM)", the offset
      read live rather than hardcoded.
- [ ] An existing site's saved zone still shows correctly selected when the page loads.
