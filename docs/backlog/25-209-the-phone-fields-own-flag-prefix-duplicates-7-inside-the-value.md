# 25-209 · The phone field's own flag prefix duplicates `+7` inside the value

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, the author, live on the widget's contact-capture card: the "🇷🇺 +7"
  prefix chip and the actual typed value both show `+7` side by side - `🇷🇺 +7 | +7 (916) 291-11-29`
  - reading as a confusing, doubled country code rather than one clean field.

## What is actually true today, confirmed against real code

**`ago-widget`**: `25-186` added a non-interactive `🇷🇺 +7` prefix span
(`ui/contactCapture.ts`'s `phonePrefix`) beside the phone `<input>`, explicitly leaving the mask
untouched - its own comment says so: *"the mask's own input/output is unchanged, only what sits
beside the field in the DOM changed."* But `phoneFormat.ts`'s `formatRussianDigits` (`25-28`, also
untouched) still writes the full `+7 (916) 291-11-29` shape into the input's own value - so both the
prefix and the value now show the country code, which is exactly the visible bug.

**`ago-console`**: `PhoneInput.tsx` (`25-186`, the design-system twin of the widget's own treatment)
has the structurally identical shape - a `🇷🇺 +7` prefix wrapping a plain `Input`. It happens not to
show the same visible duplication today only because its one real caller
(`ContactDetailsPanel.tsx`) never feeds it a `+7`-prefixed value - but the component itself would
reproduce the identical bug the moment anything does, so this is one defect in one shape, shipped
in two places, not two unrelated bugs.

## The real design decision this fix cannot dodge

`phoneFormat.ts`'s own escape hatch lets a visitor override the Russian default by typing an
explicit `+<non-7 country code>` - the field is not actually locked to Russia, only defaulted to it.
Once the input value itself stops repeating `+7` (this item's whole point), **a fixed `🇷🇺 +7` prefix
chip sitting beside a visitor's own `+1 555 019 4567` becomes actively wrong, not merely redundant** -
it asserts a country the typed number contradicts.

**Resolution, stated explicitly rather than left implicit**: the prefix chip reflects the RU default
only while the field is in that default shape. The moment `phoneFormat.ts`'s escape hatch engages
(`hasExplicitPlus && !digits.startsWith("7")`), the prefix hides (or blanks) and the input's own value
carries the full `+<code>...` the visitor actually typed, unprefixed by anything - the identical
"never assert a fact the input contradicts" reasoning already governs every other honest-state
control in this codebase. `ago-console`'s `PhoneInput.tsx` gets the equivalent behaviour: an `invalid`
or "non-default" signal it does not have today, or a prop letting its caller say the value is not a
plain Russian subscriber number.

## Scope

- **`ago-widget/src/ui/phoneFormat.ts`**: the Russian-shaped branch's own output stops repeating the
  country code - `formatRussianDigits` (or `formatPhoneInput`'s own return for that branch) produces
  `(916) 291-11-29`, not `+7 (916) 291-11-29`. The non-Russian escape-hatch branch is unchanged (it
  still returns the full `+<code>...` it already does - there is no separate prefix chip content to
  duplicate there once the chip itself hides, per the resolution above).
- **`ago-widget/src/ui/contactCapture.ts`**: the `phonePrefix` span hides (or its own content
  changes) once the escape hatch engages - read `formatPhoneInput`'s own return value or re-derive
  the identical condition, do not duplicate the digit-sniffing logic a second time if avoidable.
- **`ago-console/src/components/PhoneInput.tsx`**: gains whatever minimal signal its one real caller
  needs to say "this value is not a plain RU subscriber number" - name the actual mechanism chosen
  (a boolean prop, inferring it from the value's own shape, or something else) and why.
- **Whatever already-stored values exist** (a console operator's own saved visitor phone numbers, if
  any are persisted in the `+7 (916)...` shape this item is retiring) - confirm whether anything reads
  a phone value expecting the old shape and needs no change (a free-text field with no format
  contract) or a real one.

## Out of scope

- The flag itself, or offering a real country picker - `PhoneInput.tsx`'s own doc comment already
  states why a dropdown is wrong here (one country to choose from).
- Validating a typed phone number as real/reachable - both files already disclaim this, unchanged.

## Done when

- [ ] Typing a Russian mobile number into either the widget's contact-capture phone field or the
      console's `PhoneInput` shows the country code exactly once, in the prefix chip, never inside
      the value too.
- [ ] Typing an explicit `+<non-7 code>` in the widget's own escape hatch stops showing the `🇷🇺 +7`
      prefix (or otherwise stops asserting Russia) - proven live, not only reasoned about.
- [ ] `ago-console`'s `PhoneInput.tsx` gets the equivalent capability, with its own real caller
      updated if it needs to pass the new signal.
- [ ] Existing tests for `phoneFormat.ts`/`PhoneInput.tsx` updated to the new expected value shape,
      not deleted to dodge them.
- [ ] Both repos: typecheck/lint/test (and `ago-widget`'s own `build`/`ux-gate`) all green.
