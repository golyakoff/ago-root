# 25-131 · The booking chip sends a trigger word nobody configured

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: 2026-09-17, the author clicking the widget's own "Записаться" button on a real tenant's
  site: it inserted `/booking`, not `/записаться` - the trigger word actually configured for that
  tenant's calendar module.

## What is actually true today

`EnabledModule.TriggerWords` (`Ago.Chat.Domain`) is a real, per-site, replaceable list - confirmed
live against the database for the tenant that reported this:

```
module_key | trigger_words
calendar   | ["/записаться"]
```

**`/booking` is not in that list at all.** `TriggerCommandMatcher.Match` (`Ago.Chat.Domain`) is an
exact, case-insensitive, first-token match against exactly the words a site's own `EnabledModule` row
carries - there is no implicit, always-present fallback trigger. `RouteConversationToModuleHandler`
calls this matcher with the site's real, current trigger words on every visitor message.

`ago-widget`'s own booking chip (`modules/booking/chip.ts`) hardcodes `triggerText: "/booking"` for
both locales, unconditionally - `bookingChipSpec()` returns static copy with no knowledge of any
particular site's actual configuration. `ui/widget.ts`'s `loadBookingModuleChip` only ever checks
`session.enabledModules.includes("calendar")` (a presence-only list of module keys,
`AuthEndpoints.VisitorSessionResponse.EnabledModules: IReadOnlyList<string>`) - the visitor-facing
session response carries no trigger-word information at all.

**Net effect, confirmed for a real tenant, not a hypothetical**: clicking the widget's own booking
button sends the literal text `/booking` as an ordinary chat message. It matches no trigger word this
site actually registered, `TriggerCommandMatcher.Match` returns `null`, and the booking module never
starts - the visitor sees their own message sent and then nothing, the identical "trigger accepted,
then silence" shape `25-121` fixed for a different cause. **This is not cosmetic wording drift; the
button is non-functional for any site whose configured trigger words do not include `/booking`.**

The only existing visitor-facing signal (`session.enabledModules`) predates trigger words being
tenant-replaceable at all, and the one endpoint that already returns real trigger words
(`ModuleEndpoints.HandleGetAsync`, `GET /api/v1/sites/{siteId}/modules`) is gated on
`RequireOperatorIdentity` - a visitor holds no operator identity and cannot call it.

## Scope

- The visitor-facing session/handshake response (`AuthEndpoints.VisitorSessionResponse`, both the mint
  and renew paths) needs to carry each enabled module's own real trigger words, not just its key - the
  smallest additive change that gives the widget ground truth. Decide the exact shape (a parallel map,
  or `EnabledModules` becoming a list of `{moduleKey, triggerWords}` objects instead of a bare string
  list) and state why - check `OperatorPermissionsResponse.EnabledModules`'s own comment
  (`AuthEndpoints.cs:272`) for whether that shape is shared and would need updating too, or is
  independent.
- `ago-widget`'s `loadBookingModuleChip` (`ui/widget.ts`) and `bookingChipSpec()`
  (`modules/booking/chip.ts`) use the site's own real, first configured trigger word for `invokeModule`
  instead of the hardcoded `"/booking"` constant. The chip's own visible `label`/`ariaLabel` (the
  Russian "Записаться"/English "Book" copy `25-126` already restyled) are unaffected - only the
  invisible command text that actually gets sent changes.
- A site with an empty trigger-word list for its own enabled `calendar` module (if that state can even
  exist - check `EnableModuleForSiteAsOwnerHandler`'s own validation) needs a defined, sane behavior -
  state what it is, do not leave it to fall through unhandled.

## Where this is likely to go wrong

- **Do not add a hardcoded fallback trigger word on the backend side either.** The whole point of
  `TriggerWords` being tenant-replaceable is that a site may not want `/booking` to mean anything -
  inventing a permanent, unremovable `/booking` alias would silently reintroduce the exact coupling
  this item exists to remove.
- **This is a genuine two-repo item** (`ago-chat` wire shape, `ago-widget` consumption) - write the
  whole vertical slice yourself, deciding the exact field name and shape once in the backend, then
  having the widget consume exactly what was actually built.
- **A real, live tenant is currently affected** - once the fix ships, confirm against this exact
  tenant's own site (or an equivalent fixture reproducing `trigger_words: ["/записаться"]`, `/booking`
  absent) that clicking the chip now sends a message the site's own configured trigger word actually
  matches, not just that the wire shape compiles.

## Done when

- [ ] The widget's own booking chip sends the site's actual configured trigger word, proven against a
      site whose trigger words do not include `/booking` at all (the real, live-reported case).
- [ ] The visitor-facing session response's new field is additive and does not change any existing
      consumer's behavior for a site that never customized its trigger words.
- [ ] A site with no calendar module enabled at all still shows no chip, unchanged.
