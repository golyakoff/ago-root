# 26-285 · Visitor avatar style option (Emoji default / Initials) — an Android app setting

- **Stage**: 26. Kind: design + implementation (ago-android only). Author's intent, 2026-09-29 (verbatim):
  the emoji-pair avatar is a great default but "too playful for serious users", so make it a toggle.
- **Status**: design written — awaiting the four author decisions in "Author decisions" below, then one
  implementation slice.
- **Repos touched**: `ago-android` only. No backend, no `ago-chat`, no console. (Rationale in §C — the
  localized names already live in `:app`.)

This is a **per-device UI preference**, the same category as Тема (`26-17`) and Язык интерфейса
(`26-92`). It changes only the **anonymous emoji-pair visitor avatar**; a named person's initials avatar
is unaffected (§B).

---

## A. The settings-propagation pattern (matched to Тема / Язык exactly)

Theme and language are both a **port declared in `:app` beside its UI consumer, implemented over
`androidx.datastore`, exposed as a `Flow`, read at the root as Compose state**. The new
`VisitorAvatarStyle` follows the identical shape, with one deliberate difference noted at the end.

### Storage (mirror `ThemePreferences`)

- Port `ThemePreferences` — `app/src/main/kotlin/ago/chat/android/ui/theme/ThemePreferences.kt`
  (a `Flow<ThemeMode>` + `suspend setMode`).
- Impl `DataStoreThemePreferences` — `app/src/main/kotlin/ago/chat/android/session/DataStoreThemePreferences.kt`
  (reads the **unqualified** `DataStore<Preferences>`, key `"theme_mode"`).
- Enum `ThemeMode` — `app/src/main/kotlin/ago/chat/android/ui/theme/ThemeMode.kt`.
- DI: `AppModule.provideThemeDataStore` builds the singleton `DataStore<Preferences>` at file
  `theme.preferences_pb`; `AppModule.provideThemePreferences` binds impl→port
  (`app/src/main/kotlin/ago/chat/android/di/AppModule.kt` lines ~942-953).

**New, parallel:**

- `VisitorAvatarStyle` enum `{ Emoji, Initials }`, default `Emoji` — new file (see §D).
- Port `VisitorAvatarStylePreferences` (`Flow<VisitorAvatarStyle>` + `suspend setStyle`).
- Impl `DataStoreVisitorAvatarStylePreferences` — **reuses the same unqualified
  `DataStore<Preferences>`** (`theme.preferences_pb`) with a new key `"visitor_avatar_style"`. Both
  theme and avatar-style are pure UI preferences read at the `MainActivity` root, so they belong in the
  same store; `DataStoreThemePreferences` already keeps `"theme_mode"` there. (Minor cosmetic caveat:
  the file is literally named `theme.preferences_pb`; reusing it for a second UI key is functionally
  clean but the name reads narrower than its contents. Renaming the provider to
  `provideUiPreferencesDataStore` is possible but is scope creep — recommend leaving the filename and
  adding a one-line comment. Alternative: a dedicated `visitor_avatar.preferences_pb` file with its own
  `@Qualifier`, the way `@LanguageDataStore` isolates the language file — heavier, and unnecessary since
  nothing pre-`onCreate` reads this value the way `attachBaseContext` reads the language one.)
- DI: add `AppModule.provideVisitorAvatarStylePreferences(impl): VisitorAvatarStylePreferences`.

### How the value reaches composables — CompositionLocal, not a threaded param

**Theme is read once at the root** (`MainActivity.setContent`, `MainActivity.kt` lines ~222-235):
`themePreferences.mode.collectAsState(...)` resolves `ThemeMode` → a `darkTheme: Boolean` handed to
`AgoChatTheme`, which wraps the whole tree. There is no event bus — the `DataStore` is a `@Singleton`,
so a write from `SettingsViewModel` reaches this `collectAsState` for free ("applied immediately, no
restart", `MainActivity.kt`'s own comment).

`VisitorAvatarStyle` is read the **same way, at the same place**, and published through a
**`CompositionLocal`** — the codebase's own precedent for a rarely-changing ambient UI value is
`LocalAgoStatusColors` (`app/src/main/kotlin/ago/chat/android/ui/theme/AgoStatusColors.kt` line 48,
a `staticCompositionLocalOf`, provided via `CompositionLocalProvider` inside `AgoChatTheme`,
`Theme.kt` line 170). Concretely:

- Define `val LocalVisitorAvatarStyle = staticCompositionLocalOf { VisitorAvatarStyle.Emoji }`.
- In `MainActivity.setContent`, field-inject `VisitorAvatarStylePreferences` (beside the existing
  `themePreferences`), `collectAsState(initial = VisitorAvatarStyle.Emoji)`, and wrap the app content
  in `CompositionLocalProvider(LocalVisitorAvatarStyle provides style) { … }` **inside** the
  `AgoChatTheme { }` lambda (so it covers `SignInHost` and the whole signed-in shell).
- `VisitorAvatar` reads `LocalVisitorAvatarStyle.current` directly.

`staticCompositionLocalOf` (not `compositionLocalOf`) for the identical reason `LocalAgoStatusColors`
uses it: the value flips only when the operator toggles the setting — rare — so the cheaper "re-run
everything under the provider on change, track no reads" behaviour is correct, and per-read tracking
would buy nothing.

**Where the toggle goes in the settings screen.** `SettingsScreen`
(`app/src/main/kotlin/ago/chat/android/shell/SettingsScreen.kt`) renders Тема (lines 271-292) then Язык
интерфейса (lines 299-312) as two `SingleChoiceSegmentedButtonRow`s, each preceded by a `SectionLabel`.
The new «Аватары посетителей» section is a **third identical block placed directly after the Язык
`item {}` (line 312) and before the `if (switchableSites.size > 1)` site-switcher block (line 314)** —
i.e. immediately under language, exactly as the author asked. Same segmented-button UI:

```kotlin
item { SectionLabel(stringResource(R.string.settings_avatar_style_section)) }
item {
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        VisitorAvatarStyle.entries.forEachIndexed { index, entry ->
            SegmentedButton(
                selected = entry == avatarStyle,
                onClick = { onAvatarStyleSelected(entry) },
                shape = SegmentedButtonDefaults.itemShape(index, VisitorAvatarStyle.entries.size),
                icon = {},
                label = { Text(text = avatarStyleLabel(entry)) },
            )
        }
    }
}
```

with a private `avatarStyleLabel(style)` mirroring `themeModeLabel`/`appLanguageLabel` (lines 701-721).

`SettingsScreen` gets two new **defaulted trailing parameters** (`avatarStyle: VisitorAvatarStyle =
VisitorAvatarStyle.Emoji`, `onAvatarStyleSelected: (VisitorAvatarStyle) -> Unit = {}`), matching the
existing "every trailing param is defaulted so `SettingsScreenTest`'s named call sites cost nothing"
convention (lines 210-214).

`SettingsViewModel` (`app/src/main/kotlin/ago/chat/android/shell/SettingsViewModel.kt`) gets the port
in its constructor and, mirroring `themeMode`/`setThemeMode` (lines 80-81, 191-193):

```kotlin
public val avatarStyle: StateFlow<VisitorAvatarStyle> =
    visitorAvatarStylePreferences.style.stateIn(viewModelScope, SharingStarted.Eagerly, VisitorAvatarStyle.Emoji)

public fun setAvatarStyle(style: VisitorAvatarStyle) {
    viewModelScope.launch { visitorAvatarStylePreferences.setStyle(style) }
}
```

**The one deliberate difference from Язык.** Language needs a second, Android-specific "apply" step
(`applyAppLanguage`, which recreates the `Activity`) and a one-shot `languageApplied` `Channel`
(`SettingsViewModel` lines 88-100). Avatar style needs **none of that** — it is pure Compose state, like
Тема: collecting the `Flow` at the root is the whole apply. So `setAvatarStyle` is modelled on
`setThemeMode` (fire-and-persist), **not** on `setLanguage`. Teaching note: this is the same reason
`MainActivity.attachBaseContext` exists for language but not for theme — a colour scheme (and here, an
avatar style) is Compose state with nothing underneath it to pre-build, where a locale is a property of
`Resources` itself.

`SettingsRoute` collects `avatarStyle` and forwards `viewModel::setAvatarStyle` into `SettingsScreen`,
mirroring the `themeMode`/`onThemeModeSelected` wiring at lines 103, 156-157.

---

## B. The avatar itself + every touchpoint

### The composable

`VisitorAvatar` — `app/src/main/kotlin/ago/chat/android/ui/components/VisitorAvatar.kt`. Today it draws
the creature emoji centred in a `primaryContainer` circle with the food emoji overhanging the
bottom-right (lines 66-104). It takes `emojiCreature`/`emojiFood`/`modifier`/`diameter`, resolves the
pair via `visitorEmojiPair(...)` and returns early (draws nothing) when the pair is absent.

**Change:** read `val style = LocalVisitorAvatarStyle.current`. When `style == Initials` and the pair is
present and its localized initials resolve (§C), draw an **initials circle** instead of the emoji badge;
otherwise fall through to the existing emoji rendering. The initials circle reuses the **exact** circle
`ClientAvatar` and `AccountAvatarAction.AvatarCircle` already draw for a named person — `Box(...
clip(CircleShape).background(primaryContainer))` with `Text(initials, color = onPrimaryContainer, style
= titleSmall.copy(fontWeight = Bold))` — so a visitor-in-initials-mode and a named client render as one
visual family. `clearAndSetSemantics {}` stays (the avatar is decorative; the name is spoken separately
on the adjacent identity line — lines 58-64).

### Every call site (the "консистентно" core)

There are exactly **three** live render sites of `VisitorAvatar(` (all others are doc-comment
references):

| # | File:line | Screen | What it passes |
|---|---|---|---|
| 1 | `app/.../bookings/ContactsScreen.kt:605` | Клиенты list + detail — **via `ClientAvatar`** | `emojiCreature`, `emojiFood`, `diameter = size`, `modifier` |
| 2 | `app/.../conversations/ConversationListScreen.kt:853` | Диалоги (conversation row) | `emojiCreature`, `emojiFood`, `modifier` |
| 3 | `app/.../thread/contactpanel/ContactDetailPanel.kt:316` | Thread contact-detail panel | `emojiCreature`, `emojiFood` |

**None of the three call sites needs to change.** Because `VisitorAvatar` reads the setting from the
`CompositionLocal` itself, every site respects it for free — this is the whole reason CompositionLocal
beats threading a parameter (§teaching). Call site #1 is `ClientAvatar`
(`ContactsScreen.kt` lines 582-624): its three-arm fallback already **delegates its emoji-pair arm to
`VisitorAvatar`** (line 604-610), so Клиенты (list at 42dp, detail header at 48dp) inherits the toggle
with no edit to `ClientAvatar` at all.

Booking screens (`WorkerSlotsScreen`, `WorkerRecutScreen`, `ConfirmedBookingsScreen`,
`PhoneRevealsReportScreen`, `RestrictedVisitorsScreen`) render the visitor **as text** via
`VisitorIdentityText` / `restrictedVisitorLabel`, not as an avatar — they draw no emoji avatar, so they
are out of scope (the emoji still names the visitor in text, per author item 1 "keep being named by
their emoji pair"). The thread app-bar title (`ThreadScreen.kt` ~line 550) deliberately draws no avatar
at all. `AppShellScreen.kt:602` is a doc-comment reference, not a render.

### This toggle governs the anonymous emoji avatar ONLY — named people are unaffected

Confirmed reading of the author's intent. The **named-person initials avatar** is `initialsFor`
(`app/src/main/kotlin/ago/chat/android/ui/components/AccountAvatarAction.kt` lines 256-271) plus its
callers: `AccountAvatarAction` (the signed-in operator's own avatar) and `ClientAvatar`'s **first** arm
(`displayName != null`, `ContactsScreen.kt` lines 588-602). Those derive initials from a **real name**
and never reach `VisitorAvatar`, so they render name-initials regardless of this setting. The author's
own wording — "business mode renders **initials circles instead of the big animal emoji + food badge**"
— is specifically about the emoji-pair avatar, which is what this toggle switches. No conflict; the
setting is scoped to the anonymous emoji-pair avatar only.

---

## C. Initials from localized emoji names — rules + edge cases

### Where the localized names live (client-side, confirmed)

`visitorEmojiPairName(pair)` — `app/src/main/kotlin/ago/chat/android/ui/components/VisitorEmojiPairName.kt`
lines 36-45 — maps each glyph key to a **string resource** (`CREATURE_NAME_RESOURCES` /
`FOOD_NAME_RESOURCES`, lines 69-116) and resolves it via `stringResource`, in whichever of `ru` /
`values-en` is active. The 40 glyph→resource entries are copied byte-for-byte from
`ago-chat`'s `VisitorEmojiDictionary.cs` and covered by a completeness test. `visitorEmojiNameResource(glyph)`
(line 66) returns `null` for an unknown glyph, and the pair-name falls back to the bare glyph in that case
(line 42-43).

**This is entirely client-side.** The localized names already exist in `:app`; the stored pair
(`emojiCreature`/`emojiFood` glyph keys, read off the visitor row — never hash-derived, per
`reference_visitor_emoji_pair_is_stored`) is already on every row that renders an avatar. **No backend
data is needed** and none should be added. Premise verified — proceeding.

### The rule

Initials = **first character of the localized creature name + first character of the localized food
name, uppercased** (locale-invariant `uppercase()` with no `Locale` argument, exactly as `initialsFor`
does at `AccountAvatarAction.kt` line 267 — a name may be Cyrillic or Latin and must not depend on the
device locale).

Add to `VisitorEmojiPairName.kt`, beside the existing name helpers:

- `@Composable fun visitorEmojiInitials(pair: VisitorEmojiPair): String?` — resolves both names through
  the existing `visitorEmojiNameResource` + `stringResource`, then returns
  `visitorEmojiInitialsText(creatureName, foodName)`; returns **`null` when either glyph is absent from
  the dictionary** (see edge cases).
- `internal fun visitorEmojiInitialsText(creatureName: String, foodName: String): String` — the plain
  join, pulled out so a JVM `test` drives it with no composition host, exactly the `visitorEmojiPairNameText`
  split (lines 53-56). Body: `"${creatureName.trim().first()}${foodName.trim().first()}".uppercase()`.

### Edge cases

- **Multi-word food** («Картошка фри», «Хот-дог»): the first *character* of the whole localized string is
  already the first letter of the first word (`"Картошка фри".first() == 'К'`). No word-splitting needed —
  taking `.first()` of the trimmed name is sufficient and simpler than the brief's "first word only"
  framing (they coincide).
- **Single-character name**: yields that one character. (`ЛА`-style two-letter output degrades to one
  letter per side gracefully.)
- **Non-Cyrillic locale (`values-en`)**: "Fox"/"Orange" → "FO". Works identically.
- **Missing localized name** (a future dictionary glyph not yet in the `:app` table): `visitorEmojiNameResource`
  returns `null`, so the name falls back to the raw emoji glyph — and `String.first()` of an emoji returns
  a **broken UTF-16 surrogate half**, never a usable initial. Therefore `visitorEmojiInitials` returns
  `null` when either name is unresolved, and `VisitorAvatar` **falls back to the emoji badge** for that one
  avatar even in Initials mode. In practice the 40 glyphs are fixed and the completeness test guarantees
  full coverage, so this branch is defensive, not expected — but it prevents a broken glyph. (Author
  decision D5.)
- **Absent pair** (visitor predating the emoji-pair column): unchanged — `VisitorAvatar` draws nothing at
  all, in either mode (existing behaviour, lines 73, and the parent row already omits the gap,
  `ConversationListScreen.kt` line 850-851).

---

## D. Slice plan (rule 15), files, decisions

### The one promise

**The setting toggle exists under Язык интерфейса, persists per device, defaults to Эмодзи, and flipping
it to Инициалы re-renders every anonymous emoji-pair visitor avatar (Диалоги, Клиенты list + detail,
thread contact panel) as an initials circle derived from the localized emoji names — while named people
keep their name-initials avatar unchanged.**

**One slice, not split.** A half that adds the setting + storage without wiring `VisitorAvatar`'s dual
render "lands nothing visible" (author's own framing); a half that changes the avatar with no setting to
drive it lands a dead code path. The promise is one thing that lands green together: preference (port +
impl + DI + enum + CompositionLocal) **and** the `VisitorAvatar` dual-render **and** the settings toggle.
File it as **26-285** implementation.

### Files to change

**New:**
- `app/src/main/kotlin/ago/chat/android/ui/components/VisitorAvatarStyle.kt` — `enum class
  VisitorAvatarStyle { Emoji, Initials }` (default = first entry, `Emoji`) + `val LocalVisitorAvatarStyle
  = staticCompositionLocalOf { VisitorAvatarStyle.Emoji }`.
- `app/src/main/kotlin/ago/chat/android/ui/components/VisitorAvatarStylePreferences.kt` — port
  (`Flow<VisitorAvatarStyle>` + `suspend setStyle`), doc-commented like `ThemePreferences`.
- `app/src/main/kotlin/ago/chat/android/session/DataStoreVisitorAvatarStylePreferences.kt` — impl over
  the unqualified `DataStore<Preferences>`, key `"visitor_avatar_style"`, modelled on
  `DataStoreThemePreferences`.

**Edited:**
- `app/src/main/kotlin/ago/chat/android/ui/components/VisitorAvatar.kt` — read the CompositionLocal;
  dual-render (emoji badge / initials circle); initials arm reuses the `ClientAvatar` circle styling.
- `app/src/main/kotlin/ago/chat/android/ui/components/VisitorEmojiPairName.kt` — add `visitorEmojiInitials`
  (`@Composable`) + `visitorEmojiInitialsText` (plain).
- `app/src/main/kotlin/ago/chat/android/shell/SettingsViewModel.kt` — inject port; `avatarStyle`
  StateFlow + `setAvatarStyle`.
- `app/src/main/kotlin/ago/chat/android/shell/SettingsScreen.kt` — `SettingsRoute` collect+forward; two
  new defaulted `SettingsScreen` params; new section block under Язык; `avatarStyleLabel` helper.
- `app/src/main/kotlin/ago/chat/android/MainActivity.kt` — field-inject port; `collectAsState`; provide
  `LocalVisitorAvatarStyle` inside `AgoChatTheme`.
- `app/src/main/kotlin/ago/chat/android/di/AppModule.kt` — `provideVisitorAvatarStylePreferences`.
- `app/src/main/res/values/strings.xml` — `settings_avatar_style_section` = «Аватары посетителей»,
  `settings_avatar_style_emoji` = «Эмодзи», `settings_avatar_style_initials` = «Инициалы».
- `app/src/main/res/values-en/strings.xml` — the same three keys: "Visitor avatars", "Emoji", "Initials".

**Call sites deliberately NOT changed:** `ContactsScreen.kt:605` / `ClientAvatar`,
`ConversationListScreen.kt:853`, `ContactDetailPanel.kt:316` — all inherit the toggle through the
CompositionLocal.

**Tests:**
- New `VisitorEmojiInitialsTest` (JVM) — drives `visitorEmojiInitialsText` for the multi-word,
  single-char, and mixed-locale cases (mirror `VisitorEmojiPairNameTest`).
- Edit `SettingsViewModelTest` — fake `VisitorAvatarStylePreferences`, assert `setAvatarStyle` persists
  and `avatarStyle` reflects it (mirror the existing theme assertions).
- Optional Compose UI: `SettingsScreenTest` — the new segmented row renders + selects; and/or a
  `VisitorAvatar` render test asserting the initials circle appears when `LocalVisitorAvatarStyle` is
  `Initials`.
- Gate: `ktlint` / `testDebugUnitTest` / `assembleDebug` / `compileDebugAndroidTestKotlin` green (per
  `26-284`'s own Done-when).

### Author decisions (questions with recommendations)

1. **Default = Эмодзи.** Confirmed by author intent — no question, just recording it (enum order puts
   `Emoji` first; CompositionLocal + `stateIn` defaults are `Emoji`).
2. **Initials-circle styling — reuse the exact `ClientAvatar`/`AccountAvatarAction` circle?**
   Recommend **yes**: `primaryContainer` fill, `onPrimaryContainer` text, `titleSmall` bold. This is the
   whole point of "консистентно" — a visitor-in-initials looks like the same avatar family as a named
   client/operator.
3. **Per-device (like Тема / Язык) or per-account?** Recommend **per-device** — identical DataStore
   mechanism, no server, no entitlement. A "serious mode" is a viewing preference of the person holding
   the phone, not a tenant policy.
4. **Initials font at the 42dp/48dp `diameter` overrides — scale, or fixed `titleSmall` like
   `ClientAvatar`?** Recommend **fixed `titleSmall` bold**, matching `ClientAvatar` (which uses
   `titleSmall` at both its 42dp list and 48dp header sizes) rather than the proportional scaling the
   emoji glyph uses — so the initials avatar and the named-client avatar stay pixel-consistent.
5. **Unresolved localized name → initials or emoji fallback?** Recommend **fall back to the emoji badge**
   for that one avatar (returns `null` initials), never a broken surrogate-half glyph. Defensive only —
   the 40-glyph dictionary is complete.

### ADR

**No ADR.** This is a per-device UI preference, the exact category Тема (`26-17`) and Язык (`26-92`)
established without an ADR. The one decision with any weight — CompositionLocal vs. threaded parameter —
is a Compose-idiom choice, not an architectural guarantee being weakened, and it follows the existing
`LocalAgoStatusColors` precedent. No `docs/adr/` row.

---

## Teaching note (Clean Architecture / Compose state)

**Port placement.** `VisitorAvatarStylePreferences` lives in `:app` beside `VisitorAvatar`, not in
`:core:domain`, because nothing outside the UI layer reads it — the identical reasoning `ThemePreferences`
states for itself. The dependency rule additionally *forbids* it lower: `:core:domain` may hold no
`androidx.*` import, and the impl is built on `androidx.datastore`. The alternative — declaring the port
in `:core:domain` "for symmetry" — would be premature generalisation and would drag an Android storage
concern into a pure JVM module.

**Propagation — CompositionLocal, not a threaded parameter.** The setting is an *ambient, rarely-changing,
cross-cutting UI value read by a leaf composable* — the same shape as `MaterialTheme.colorScheme` (itself
a CompositionLocal) and this app's own `LocalAgoStatusColors`. A `staticCompositionLocalOf` provided once
at the `MainActivity` root reaches all three avatar call sites with zero signature changes. The
alternative — threading a `VisitorAvatarStyle` parameter from each of three unrelated ViewModels, through
each screen, down to each row — would couple `SettingsViewModel`'s concern to `ConversationListViewModel`,
`ContactsViewModel`, and the thread panel, forcing every intermediate composable to forward a value it
does not use. Compose's own guidance reserves CompositionLocal for exactly this: a value used by many
composables, changed rarely, that would otherwise be tunnelled through unrelated layers. (The trade-off
CompositionLocal costs — an implicit dependency that is easy to miss — is acceptable here because the
value has one obvious owner and one obvious meaning, the same bargain `LocalAgoStatusColors` already
accepts.)
