# 26-303 — Phone-input control: study Tinkoff ID's, compare to ours, propose adopting it

**Status:** research only — no code. The author reviews before any implementation is dispatched.
**Scope:** ago-android. The author dislikes our current phone-number input and points to Tinkoff ID's
(`https://id.tbank.ru/auth/step`) as the reference to adopt.

## 0. Method & sources — how the reference was studied

The live Tinkoff ID auth page **could not be observed** from this worker's browser: navigation to
`https://id.tbank.ru/...` was denied/failed in this sandboxed context (it is a bank auth page; the
`cid` is session-bound and the domain is gated). Per the brief, this study therefore **falls back to
public sources** documenting the same control — and it is a well-documented one, because Tinkoff/T-Bank
open-sourced the exact building blocks their own auth screens use:

- **Taiga UI `InputPhone`** — T-Bank's public Angular design system's phone field.
  <https://taiga-ui.dev/components/input-phone>, <https://github.com/taiga-family/taiga-ui>
- **Maskito** — T-Bank's open-source text-masking library that `InputPhone` builds on; its phone kit is
  the canonical `+7 (___) ___-__-__` mask with paste normalisation.
  <https://maskito.dev>, <https://github.com/taiga-family/maskito>
- A Maskito/Taiga changelog entry (v5.18.0, 2026-08-03) fixing "InputPhone drops the `8` after country
  code on paste of `+7 8xx`" — direct evidence that **paste normalisation of a leading `8`/`+7` is a
  first-class, deliberately-handled behaviour** of the reference control.
  <https://github.com/taiga-family/taiga-ui/blob/main/CHANGELOG.md>
- T-Bank login help (phone-then-SMS-code auth flow). <https://www.tbank.ru/bank/help/apps/eng/>

Everything below about the reference is grounded in those public sources, not in a live capture. If the
author wants a pixel-exact capture, it needs a hand-run in an interactive (non-sandboxed) browser
session with a fresh `cid` — flag this and I can note the deltas.

## 1. The Tinkoff / T-Bank phone control — observed traits (from public sources)

| Trait | Behaviour |
|---|---|
| **Country code** | `+7` is **fixed and always shown** (RU auth). The user types only the 10 national digits; the prefix is not deletable and not something the caret sits before. (Taiga's international variant adds a flag/selector, but the ID auth screen is the fixed-`+7` variant.) |
| **Live mask** | Formats **as you type**: `+7 (921) 000-00-00`. Non-digits typed are ignored; digits flow into the next slot. Mask template `+7 (___) ___-__-__`. |
| **Placeholder** | The mask template itself acts as the guide (`+7 (___) ___-__-__`); the field reads as a formatted number even when empty. |
| **Auto-focus** | The field is focused on page load; the numeric keyboard is up immediately on mobile. |
| **Keyboard** | Numeric / tel keyboard (`inputmode=tel`). |
| **Paste normalisation** | Pasting `89211234567`, `+7 921 123-45-67`, `7 921 1234567`, or `9211234567` all normalise to the **same** `+7 (921) 123-45-67`. Leading `8`/`+7`/`7`, spaces, dashes, parens are stripped/re-mapped. (The v5.18.0 fix above is precisely this path.) |
| **Max length** | Capped at the mask — exactly 10 national digits; extra digits are rejected, not appended. |
| **Inline validation → action gating** | The primary action ("Continue" / "Get code") **enables only when the number is complete** (10 national digits). Validity is expressed by *enabling forward motion*, not by showing an error glyph after a failed submit. Errors appear only after a real failure (e.g. wrong code), not while typing a still-incomplete number. |
| **Look / placement** | A **single, large, centred field** that owns the screen — the number *is* the step — not a small field in a dense form row. |

The essence: **one prominent field, a fixed `+7`, a live format mask, paste that "just works", and a
button that lights up exactly when the number is valid** — no after-the-fact error state during entry.

## 2. Our current phone input (ago-android) — concrete state

Phone is a **plain `String`** end-to-end. There is **no `PhoneNumber` domain value type** and **no
custom `VisualTransformation`/mask anywhere in `app/src/main`** (the only `VisualTransformation` in the
app is the built-in `PasswordVisualTransformation` in
`channels/ChannelConnectScreen.kt:186` — not a format mask). Display-side masking for *revealed* numbers
exists as `core/domain/.../bookings/BookingIdentity.kt:32` `MaskedPhone`, but that is output, not input.

There are exactly **two editable phone-entry sites** (grep for `KeyboardType.Phone` in
`app/src/main` returns only these two):

### 2a. Manual-booking wizard, phone step — the main one
`app/src/main/kotlin/ago/chat/android/bookings/ManualBookingScreen.kt:350-359`

```
OutlinedTextField(
    value = wizard.phone,
    onValueChange = onPhoneChanged,
    label = { Text(bookings_manual_phone_label) },          // "Телефон клиента"
    placeholder = { Text(bookings_manual_phone_placeholder) }, // "+7 921 000-00-00"
    singleLine = true,
    enabled = lookup !is PhoneLookupState.Searching,
    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
    modifier = Modifier.fillMaxWidth(),
)
```

- **No mask**: whatever the user types is stored verbatim (`onPhoneChanged` copies `text` straight into
  `wizard.phone`, `ManualBookingViewModel.kt:162-172`). No `+7` prefix, no grouping.
- **No inline validation glyph**: the field is never `isError`. The «Найти клиента» button is enabled on
  `wizard.phone.isNotBlank()` (`ManualBookingScreen.kt:377`) — *any* non-blank text, not a valid number.
- **Auto-search heuristic**, not validation: `onPhoneChanged` fires the lookup once
  `digitsOnly().length >= 11` (`ManualBookingViewModel.kt:168-171`, `PHONE_AUTO_SEARCH_DIGITS = 11`,
  line 533). `digitsOnly()` = `filter { it.isDigit() }` (line 528). So `8` and `+7` both count as
  "11 digits" inconsistently — `89211234567` (11) and `+79211234567` (11) both trip it, but the value
  actually sent to the API (`searchPhone`/`submit`, lines 194 & 486) is the **raw trimmed string**, not a
  normalised E.164. Normalisation is left entirely to the server.
- **No paste normalisation**, no max length, no auto-focus wiring here (default focus behaviour only).

### 2b. Contact-detail editor (conversation contact panel)
`app/src/main/kotlin/ago/chat/android/thread/contactpanel/sections/ContactDetailsSection.kt:286-293`,
keyboard selection at `:317-322`.

```
OutlinedTextField(
    value = draft,
    onValueChange = onDraftChanged,
    singleLine = true,
    keyboardOptions = KeyboardOptions(keyboardType = editorKeyboardType(kind)), // "Phone" -> KeyboardType.Phone
    ...
)
// save enabled on draft.isNotBlank()  (:298)
```

- The doc comment at `:313-316` is explicit: **"never a client-side format mask, since neither this port
  nor the server enforces one beyond non-empty."** This is the deliberate current stance the item
  proposes to revisit. Save gates on non-blank only.

### Not phone inputs (checked, excluded)
`team/InviteColleagueSheet.kt` is **email** (`KeyboardType.Email`, `:167`); `ClientDetailScreen.kt`
only *displays* a revealed phone; `analytics/PhoneRevealsReport*` is a report, not an input.

## 3. Comparison — Tinkoff control vs ours

| Characteristic | Tinkoff / T-Bank | Ours (both sites) |
|---|---|---|
| Mask / live formatting | `+7 (921) 000-00-00` formatted as typed | none — raw text stored verbatim |
| Country code | fixed `+7`, non-deletable, always shown | none; user must type `+7`/`8`/nothing |
| Paste | normalises `8…`/`+7…`/spaces/dashes to one canonical form | verbatim; no normalisation (server-side only) |
| Validation | valid ⇒ **enable** "continue"; no error during entry | non-blank ⇒ enable; no real validity check |
| Focus / keyboard | auto-focused, numeric/tel keyboard | `KeyboardType.Phone`; no explicit auto-focus |
| Error UX | error only after a real failure, never while typing | no `isError` at all |
| Size / placement | single large centred field, owns the step | standard form field in a column (2a) / inline editor row (2b) |
| Canonical output | mask yields a clean national/E.164 value | raw string; normalisation deferred to server |
| Domain type | (framework-level masked value) | plain `String`, no `PhoneNumber` type |

## 4. What would change if we take theirs as the base — concrete deltas

1. **Add a live `VisualTransformation` mask** rendering the raw digit state as `+7 (XXX) XXX-XX-XX` while
   the *stored* value stays digits-only (offset mapping keeps the caret correct).
2. **Fix the `+7` prefix.** Store only the 10 national digits; render `+7 ` as a fixed, non-editable
   lead. Removes the "did the user type 8 or +7 or nothing?" ambiguity that today makes the
   `>= 11 digits` auto-search heuristic fuzzy.
3. **Normalise input & paste.** Filter to digits in `onValueChange`; when the first pasted/typed digit
   is `8` **or** the run starts with `7`+10, drop it so the national part is exactly 10 digits. This is
   the single most user-visible win and the one the reference itself treats as a named bug class.
4. **Cap at 10 national digits** — extra digits rejected, not appended.
5. **Gate the action on validity, not non-blank.** «Найти клиента» / save enables when national digits
   == 10, i.e. the number is complete — replacing `isNotBlank()`. This also lets the auto-search
   heuristic key off "exactly 10 national digits" instead of the ambiguous 11-with-country-code count
   (`PHONE_AUTO_SEARCH_DIGITS`).
6. **Send a canonical value.** With digits-only national state, `searchPhone`/`submit` can send a clean
   `+7XXXXXXXXXX` (E.164) instead of a raw string — server still validates, but the contract stops
   depending on the user's punctuation.
7. **(2a only) presentation:** auto-focus the field when the phone step opens and give it a numeric
   keyboard already selected (it is `KeyboardType.Phone` today; add `requestFocus`). Making it larger /
   more centred is optional polish — the mask + gating are the substance.
8. **(2b) revisit the "never a mask" stance.** Applying the shared control here means editing the
   `:313-316` doc comment in the same change (docs-are-part-of-the-deliverable).

Deltas 1-6 are behaviour; 7-8 are placement/consistency. 1-6 are what the author is actually reacting to.

## 5. Compose implementation sketch

**State model:** the field's stored value is **digits-only, national (max 10)**. The mask is
presentation.

```kotlin
// core/ui (or app ui/components) — one reusable composable + one VisualTransformation
private const val NATIONAL_LEN = 10

/** Keeps digits, drops a leading 8 or 7 country prefix, caps at 10. Handles paste. */
internal fun normalizeRuNational(raw: String): String {
    var d = raw.filter(Char::isDigit)
    if (d.length > NATIONAL_LEN && (d.startsWith("8") || d.startsWith("7"))) d = d.drop(1)
    return d.take(NATIONAL_LEN)
}

/** Renders "1234567890" as "+7 (123) 456-78-90" with correct caret offset mapping. */
internal class RuPhoneVisualTransformation : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText { /* build "+7 (ddd) ddd-dd-dd",
        return TransformedText(masked, offsetMapping) — original↔transformed index math */ }
}

@Composable
fun RuPhoneField(
    value: String,                       // digits-only national state
    onValueChange: (String) -> Unit,     // receives normalizeRuNational(input)
    modifier: Modifier = Modifier,
    label: String, enabled: Boolean = true, autoFocus: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = { onValueChange(normalizeRuNational(it)) },
        visualTransformation = RuPhoneVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
        singleLine = true, enabled = enabled, label = { Text(label) },
        modifier = modifier /* + FocusRequester when autoFocus */,
    )
}
fun ruPhoneComplete(value: String) = value.length == NATIONAL_LEN
```

**Library vs hand-rolled.** Per the "don't add a NuGet/dependency without saying what it replaces" rule:
**hand-roll it.** A single-country `+7 (XXX) XXX-XX-XX` mask is ~40 lines of `VisualTransformation` +
offset mapping and one normalise function — a well-trodden Compose pattern. Adding a masking library
(e.g. a Compose port of a mask lib) to cover one fixed national format is not worth a new dependency,
its transitive surface, or its version upkeep; we'd use <5% of it. Revisit **only** if/when we need
true multi-country input with per-country masks and a flag selector (Taiga's `InputPhoneInternational`
territory) — that is a different, larger feature and would justify a library evaluation on its own.
The offset-mapping math is the one fiddly part and is exactly what unit tests should pin.

## 6. Where it applies — one reusable composable

Both editable sites consume the same `RuPhoneField`:
- `ManualBookingScreen.kt` phone step (2a) — the primary target; also lets the auto-search heuristic and
  the `submit` body switch to a canonical value.
- `ContactDetailsSection.kt` contact editor (2b) — for the `"Phone"` kind only; `"Email"`/`"Name"`
  keep their current keyboards. Update the `:313-316` "never a mask" comment.

Keeping it one composable is the point: the author's complaint is about *the control*, so it should be
fixed once and reused, not patched per screen. New user-facing strings (e.g. an "enter 10 digits" hint
if we add one) must be **string resources in both `values/` and `values-en/`** — no literals
(project rule; ago-android literal-string ban).

## 7. Slice plan

One control, two consumers, but the promises differ, so this is more than one ticket. Suggested cut
(each lands green on its own):

- **26-303-A — the reusable control.** Add `RuPhoneField` + `RuPhoneVisualTransformation` +
  `normalizeRuNational`/`ruPhoneComplete` with unit tests for normalisation (paste `8…`, `+7…`,
  spaces/dashes, over-length) and offset mapping. No screen wired yet? A pure-UI control with tests is a
  legitimate slice, but if the "one promise that lands green" test (rule 15) feels thin, fold it into B.
- **26-303-B — adopt in the manual-booking wizard (2a).** Wire `RuPhoneField`, switch action-enable to
  `ruPhoneComplete`, feed a canonical `+7XXXXXXXXXX` to `searchPhone`/`submit`, re-key the auto-search
  heuristic off 10 national digits, auto-focus the step. This is the delta the author will see first.
- **26-303-C — adopt in the contact-detail editor (2b).** Wire it for the `"Phone"` kind, gate save on
  completeness, and update the `:313-316` doc comment. Separate promise (a different screen, different
  save path), so a separate ticket.

**Gates every slice must clear (project rules + ago-android specifics):**
- `compileDebugAndroidTestKotlin` — changing a Composable's params breaks `androidTest` compile, a
  *separate* CI gate from unit tests + `assembleDebug`; grep `androidTest` callers of any signature
  touched.
- Android CI: require **both** `build-test` **and** `instrumented-tests` = COMPLETED/SUCCESS by name
  before calling a PR done (`publish-apk` may be SKIPPED).
- All new strings as resources in **both** `values/` and `values-en/`.
- No new dependency (hand-rolled per §5).

## 8. Open question for the author

The live reference could not be captured in this sandbox (§0). If pixel-exact placement/sizing matters
(the "single large centred field" look, §1 last row), that needs a hand-run interactive capture — say
the word and I'll note any deltas from the hand-rolled `+7 (XXX) XXX-XX-XX` behaviour proposed here.
Otherwise the behavioural deltas in §4 (mask, fixed `+7`, paste, validity-gating) are the substance and
don't depend on the capture.
