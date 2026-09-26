# Виджет на сайте (widget config) — Android tenant-admin design

Implementation-ready design for the **Виджет на сайте** area of the Android tenant-admin app — the
next focused chunk of the console→app parity initiative, after `docs/design/tenant-channels-android.md`
(Каналы) and alongside `docs/design/tenant-management-android.md`. It is written so a sonnet worker can
build each slice with no design decisions left, matching the channels doc's structure and quality bar.

**Parity is decided, not re-questioned.** Every field the console's `WidgetConfigPage` writes, the app
writes — no capability cut. Gate: `site:configure`.

**The split is decided, not re-questioned.** The console renders one `<form>` of seven stacked panels
and 16 fields; the author has decided the app must **split widget config into coherent logical-group
screens**, not one giant scrolling form. This doc fixes the grouping (three group editors behind one
hub), justifies it, and — because a partial PUT silently resets absent booleans — designs the
full-DTO round-trip explicitly as the central correctness concern.

## Base freshness

Worktree `docs/tenant-widget-android` branched from `origin/main` at `c2b2a01` (the channels-doc commit,
`docs(design): Каналы area for Android tenant-admin`), verified `HEAD == origin/main` at creation. The
primary `ago-root` checkout was stale at `79a358d`; this branch is off the true tip.

---

## 1. The contract (read from source, not assumed)

`GET`/`PUT /api/v1/sites/{siteId}/widget-config`, route group `RequireAuthorization("RequireOperatorIdentity")`;
the **`site:configure`** check is inside `GetWidgetConfigHandler`/`UpdateWidgetConfigHandler` (Application
level), so — unlike the token channels — the row gate and the call gate are the **same permission**, and
there is no rail-vs-server gap to design around. Source: `ago-chat`
`src/Ago.Chat.Api/WidgetConfig/WidgetConfigEndpoints.cs`; console
`ago-console/src/api/widgetConfigApi.ts` + `src/pages/WidgetConfigPage.tsx` + `widgetConfigValidation.ts`.

**The PUT body is the whole `WidgetConfigDto`.** `updateWidgetConfig` `JSON.stringify`s the entire object;
the server's `UpdateWidgetConfigRequest` binds a **missing `bool` to `false`** and `RequireContactConsent`
carries `[JsonRequired]` precisely because omitting it silently turns a real consent gate off. Every field
the app sends must therefore be the *complete* current config, never a subset. This is the correctness
trap §3 is built around.

### 1.1 The 16 fields

| # | Field | Wire type | Meaning (source remark) | Blank/absent semantics |
|---|---|---|---|---|
| 1 | `primaryColorHex` | `string?` | Launcher/panel accent colour. | `null` = widget's own built-in default. |
| 2 | `position` | enum str `BottomRight`\|`BottomLeft` | Launcher corner. | always present. |
| 3 | `locale` | enum str `En`\|`Ru` | Widget UI language. | always present. |
| 4 | `panelTitle` | `string?` | Chat panel `<h1>`, also the channel-switcher header (`25-210`/`25-211`). | `null` = **built-in default greeting**, *not* "render nothing". |
| 5 | `attractAttention` | `bool` | Launcher animates to draw attention while closed (`23-63`). `prefers-reduced-motion` overrides regardless. | off. |
| 6 | `autoOpenEnabled` | `bool` | Widget auto-opens after a delay (`23-64`/`adr/0148`). | off. |
| 7 | `autoOpenDelaySeconds` | `int` ∈ {15,30,45,60,90,120} | Delay before auto-open. | `30` (server default). |
| 8 | `autoOpenGreetingText` | `string?` | Tenant's auto-open greeting line. | `null` = none. **Required (non-blank) when `autoOpenEnabled`.** |
| 9 | `channelSwitcherPlacement` | enum str `AboveComposer`\|`BelowLauncher` | Where connected channels appear (`25-173`). | `AboveComposer`. |
| 10 | `channelSwitcherIconSize` | enum str `Large`\|`Medium`\|`Small` | Circle size when `BelowLauncher`; always present even when `AboveComposer`. | `Medium`. |
| 11 | `noticeText` | `string?` | Tenant's data-handling notice sentence (`16-04`). | `null` = show no notice. |
| 12 | `noticeUrl` | `string?` | Tenant's policy page for the notice. `https://` only (client courtesy). | `null` = none; independent of `noticeText`. |
| 13 | `requireContactConsent` | `bool` **`[JsonRequired]`** | Gate: no contact detail recorded until the visitor accepts the tenant's consent document (`23-108`). | off — **omission silently disables a live gate**. |
| 14 | `contactCaptureConfirmationText` | `string?` | Sentence echoed to a visitor after they submit contact details; may contain literal `{name}` (`25-129`). | `null` = widget's own default sentence. |
| 15 | `acceptUnverifiedPhone` | `bool` | Temporary relaxation of booking's verified-phone rule while `14-15` has no SMS gateway (`25-39`). | off. |
| 16 | `allowAttachmentUploadsByDefault` | `bool` | New conversations start with an upload grant already on (`25-104`). Seeds the thread composer's paperclip (see `navigation.md`). | off. |

`autoOpenDelaySeconds` crosses the wire as a plain `int`; the other four enums cross as their PascalCase
member name (`.ToString()` on the server, `PositionConverter`/`LocaleConverter` storage spelling is
unrelated). `WidgetConfigResponse` echoes the same 16 fields; the app re-seeds its committed config from
that echo after every PUT.

---

## 2. The group split (decided) and why it diverges from the console's 7 panels

The console groups the 16 fields into **seven** panels inside one form: Launcher, Channel switcher,
Consent notice, Contact consent, Contact-capture confirmation, Booking (temporary), Attachments. Seven
short panels stacked in one desktop form is fine; **on a 400dp phone a 16-field, seven-concern single
scroll is the exact "too long to navigate" shape the author's split decision rejects.**

The app regroups the seven console panels into **three group editor screens**, each answering one
question a tenant actually holds in their head:

| Group screen | Fields | The one question it answers | Console panels folded in |
|---|---|---|---|
| **Внешний вид** (Appearance) | `primaryColorHex`, `position`, `locale`, `panelTitle`, `channelSwitcherPlacement`, `channelSwitcherIconSize` | *What does the visitor see before interacting?* | Launcher (visual half) + Channel switcher |
| **Поведение и приветствие** (Behaviour & greeting) | `attractAttention`, `autoOpenEnabled`, `autoOpenDelaySeconds`, `autoOpenGreetingText`, `contactCaptureConfirmationText` | *What does the widget do on its own, and what does it say?* | Launcher (behaviour half) + Contact-capture confirmation |
| **Согласие и запись** (Consent & booking) | `requireContactConsent`, `noticeText`, `noticeUrl`, `acceptUnverifiedPhone`, `allowAttachmentUploadsByDefault` | *What must the visitor agree to, and what are they allowed to do?* | Consent notice + Contact consent + Booking (temporary) + Attachments |

**Why three, not seven, and not one.** Seven phone screens is over-fragmented (four of the console's
panels are a single control each — a tab per checkbox reads as broken). One screen is the giant form the
author rejected. Three is the number of genuinely distinct *questions*: look, behaviour, policy. Each is
a short, comfortable phone scroll.

**Why these specific folds, where the console splits:**

- The console's **Launcher** panel mixes pure appearance (colour/position/language/title) with proactive
  *behaviour* (attract-attention, auto-open). On a phone that seam is worth cutting: appearance is
  "how it looks", behaviour is "what it does". So Launcher splits across Внешний вид and Поведение.
- The console keeps **Channel switcher** its own panel; the app folds it into Внешний вид because
  placement + icon size are pure visual choices with no behavioural side effect — the same "how it looks"
  question as colour and corner.
- **`contactCaptureConfirmationText`** joins Поведение (not Согласие) because it is a *line the widget
  speaks* to the visitor — the same kind of tenant-authored copy as the auto-open greeting — not a
  consent gate. Grouping the two "spoken lines" together reads better than scattering copy across screens.
- **Согласие и запись** unifies the console's four separate policy/permission panels (consent gate, its
  notice, the temporary phone relaxation, the attachments default) because on a phone they are one
  question — *what is the visitor permitted / required to do* — and four one-control screens would be
  absurd. The notice's read-then-edit affordance (§6.3) preserves the console's own `25-24` distinction
  between "what the notice says" and "whether consent is mandatory" *within* the screen.

*Principle (teaching mode): the console's panel split is a desktop information-architecture choice; the
app's screen split is a different IA for a different viewport, driven by "one coherent question per
screen" rather than by mirroring the backend's field order. The alternative — one screen with a `TabRow`
of three tabs and a single Save — was considered and rejected: the author's brief says "each screen that
saves must round-trip the full object", which is a statement about **multiple independently-saving
screens**, and tabs would collapse that back into the single-save form the split exists to avoid.*

---

## 3. The full-DTO round-trip — the central correctness design

**The trap.** Three screens each save independently, and each PUT must carry all 16 fields or the server
resets the absent ones (`requireContactConsent` is `[JsonRequired]` for exactly this reason; every other
`bool` binds to `false` on omission). A naïve "each screen PUTs only its own fields" would silently switch
off consent/attachments/attract-attention whenever any *other* screen was saved. This is the same defect
class the console's own `23-108`/`25-104` remarks describe having lived through.

**The design that makes it structurally impossible:**

1. **One `WidgetConfig` domain type carries all 16 fields, none optional-away.** The nullable strings are
   `String?`; every other field is present. The adapter maps the whole object to the wire DTO on every
   PUT, so an adapter-level omission cannot occur — there is no field the mapping can skip.
2. **One `WidgetConfigViewModel`, hoisted once at the "Виджет на сайте" row**, holds the *committed*
   full config (loaded once by `GET`, re-seeded from every PUT's echo). It is the single source of truth
   for what is actually in effect.
3. **The three group editors share that one VM** (obtained via `hiltViewModel()` in the feature's route
   composable and passed down — not a fresh VM per editor). Each editor seeds a **local draft** of *only
   its own slice* from the committed config on entry.
4. **A group editor's Save builds `committed.copy(<its slice from the draft>)`** — the complete object,
   its own fields from the draft and every other field from the committed truth — and PUTs that. On
   success the VM re-seeds committed from the echo.

Because a save always starts from the committed full config and overwrites only the saving screen's
fields, **no boolean is ever absent from a PUT, and an unsaved draft on another screen never leaks into a
save** (only the saving screen's slice is merged; other editors' local drafts are discarded on back).

*Principle: the committed config is the console's `current` state variable; each editor's local draft is
the console's per-field `useState`. The console gets full-DTO safety for free because it has one form and
one Save over all state vars; the app must reconstruct that safety across three screens, and it does so by
keeping the committed whole in one shared VM and merging one slice at a time. Alternative considered —
three independent MoreScreen rows, each its own VM that GETs and PUTs the full config: rejected because
`navigation.md` lists a single «Виджет на сайте» row, three VMs triple the GETs, and two editors open in
sequence could each hold a stale committed copy and clobber the other's just-saved change. One shared VM,
re-seeded on every save, removes that race.*

### 3.1 Why a hub, and why the nesting is legal

`navigation.md` §Ещё lists exactly one Каналы row for this area — `WidgetCfg["Виджет на сайте"]`, between
«Установка виджета» and «MAX». So the single row opens a **hub** listing the three groups; each group row
opens its editor. That is a second navigation level *inside the widget feature*, reached from Ещё — not a
second level of the Ещё list itself, which is what `MoreScreen`'s "Ещё never nests further" clause
governs (a conversation thread reached from Диалоги likewise has its own internal nav). The hub also owns
the one place to show load-failed / retry and the adr/0029 "changes apply on the visitor's next page
load" note, once, rather than on each editor.

---

## 4. Domain port + adapter

### 4.1 Domain (`:core:domain`)

`core/domain/src/main/kotlin/ago/chat/android/core/domain/widgetconfig/WidgetConfigApi.kt`

```
interface WidgetConfigApi {
    suspend fun fetch(): WidgetConfigResult                         // Loaded(config) | Failed(NetworkFailure)
    suspend fun update(config: WidgetConfig): WidgetConfigWriteResult   // Saved(config) | Refused(detail) | Failed(NetworkFailure)
}
```

Domain types (same package):

| Type | Shape | Notes |
|---|---|---|
| `WidgetConfig` | data class of all 16 fields (§1.1), enums as Kotlin enums, nullable strings as `String?` | The whole object. `update` cannot omit a field. |
| `WidgetPosition` | enum `BottomRight`, `BottomLeft`; `.wire` = member name | |
| `WidgetLocale` | enum `En`, `Ru`; `.wire` = member name; label is the endonym (`English`/`Русский`), **not** translated | |
| `WidgetAutoOpenDelay` | enum `Seconds15(15)…Seconds120(120)` with `val seconds: Int` | wire = `seconds`; unknown int on read → `Seconds30` (server default). |
| `ChannelSwitcherPlacement` | enum `AboveComposer`, `BelowLauncher` | |
| `ChannelSwitcherIconSize` | enum `Large`, `Medium`, `Small` | always present, even while `AboveComposer`. |
| `WidgetConfigResult` | `Loaded(config)` \| `Failed(NetworkFailure)` | reuses `core.domain.net.NetworkFailure` (`26-59`); the two-arm read shape `ContactDetailsResult` establishes. |
| `WidgetConfigWriteResult` | `Saved(config)` \| `Refused(detail)` \| `Failed(NetworkFailure)` | the identical three-arm write shape `ContactDetailWriteResult` (`26-167`) establishes; `Refused.detail` is the server's RFC-7807 sentence verbatim. |

*Principle: the port lives in `:core:domain` because the dependency rule forbids a view model holding an
`HttpClient`; the enum-parsing, `{siteId}` resolution and status-to-meaning decisions belong on the far
side of it, in `:core:network` — the identical split `InstallationApi`/`ContactDetailsApi` already draw.*

### 4.2 Adapter (`:core:network`)

`core/network/src/main/kotlin/ago/chat/android/core/network/widgetconfig/KtorWidgetConfigApi.kt`

Constructor `(client: HttpClient, apiBaseUrl: String, activeSite: ActiveSiteSelection)` — the exact shape
`KtorInstallationApi`/`KtorConversationTagsApi` use, because `{siteId}` is in the URL and read via
`activeSite.currentSiteId()`; bearer token + `X-Ago-Active-Site` come from `installAgoRestDefaults`.

Base path `"$apiBaseUrl/api/v1/sites/$siteId/widget-config"`.

| Verb | Path | 2xx | Non-2xx → | Exception → |
|---|---|---|---|---|
| `GET` | `…/widget-config` | 200 → `Loaded(config)` (parse `WidgetConfigWireDto`, map enums) | `Failed(ServerError(status))` — reachable only for a `site:configure` holder, so "couldn't load, retry" is honest (same reasoning `KtorInstallationApi` records) | `IOException → Failed(NoConnection)`, else `Failed(Unexpected)` via `NetworkFailure.from` |
| `PUT` | `…/widget-config` body = full `WidgetConfigWireDto` | 200 → `Saved(config)` (re-parse the echo) | read problem-details `detail` → `Refused(detail)`; if no parseable body → `Failed(ServerError(status))` | as above |

Private `@Serializable` wire DTO (never crosses the port), mirroring
`UpdateWidgetConfigRequest`/`WidgetConfigResponse` exactly:

```
@Serializable private data class WidgetConfigWireDto(
    val primaryColorHex: String? = null,
    val position: String = "BottomRight",
    val locale: String = "En",
    val noticeText: String? = null,
    val noticeUrl: String? = null,
    val requireContactConsent: Boolean = false,
    val attractAttention: Boolean = false,
    val autoOpenEnabled: Boolean = false,
    val autoOpenDelaySeconds: Int = 30,
    val autoOpenGreetingText: String? = null,
    val acceptUnverifiedPhone: Boolean = false,
    val allowAttachmentUploadsByDefault: Boolean = false,
    val contactCaptureConfirmationText: String? = null,
    val channelSwitcherPlacement: String = "AboveComposer",
    val channelSwitcherIconSize: String = "Medium",
    val panelTitle: String? = null)
@Serializable private data class ProblemDetailsWireDto(val detail: String? = null)
```

The `update` mapping writes **all 16** fields from the `WidgetConfig` — the structural guarantee that the
adapter can never omit a `bool`. Enum → wire is the member name / `seconds`; unknown wire enum on read
maps to the field's default (mirroring the server's own "old client keeps working" tolerance), never a
decode failure. A `200`/echo whose body is not the promised shape is `Failed`, not an empty config (the
`shapeGuard` lesson). Never a raw exception class name or hostname on screen — `NetworkFailure.from`
enforces this.

### 4.3 DI (`AppModule.kt`)

```
@Provides
public fun provideWidgetConfigApi(
    client: HttpClient, config: OidcConfig, activeSite: ActiveSiteSelection,
): WidgetConfigApi = KtorWidgetConfigApi(client, config.apiBaseUrl, activeSite)
```

Threads `ActiveSiteSelection` like `provideConversationTagsApi` (the `{siteId}` is in the URL).

---

## 5. Feature shell: VM, hub, sub-navigation

`app/src/main/kotlin/ago/chat/android/channels/` (the package `InstallWidget*` already lives in).

### 5.1 UI state

`WidgetConfigUiState.kt`
```
sealed interface WidgetConfigUiState {
    data object Loading
    data class Failed(reason: NetworkFailure)                 // retry
    data class Loaded(
        committed: WidgetConfig,        // the source of truth; editors seed drafts from this
        saving: Boolean,
        saveError: String?,             // a Refused(detail) sentence or a rendered NetworkFailure
        savedTick: Int)                 // bumped on each successful save → drives a "Сохранено" Snackbar
}
```

### 5.2 View model

`WidgetConfigViewModel.kt` (`@HiltViewModel`), `init { refresh() }`.
- `refresh()` → `Loading` → `fetch()` → `Loaded(committed)` / `Failed`.
- `save(updated: WidgetConfig)` → `Loaded(saving=true)` → `update(updated)`:
  `Saved(echo)` → `Loaded(committed=echo, savedTick++)`; `Refused(detail)`/`Failed` → `Loaded(saveError=…)`,
  committed unchanged. One reload-after-write source of truth, never an optimistic flip (the console's own
  `load()`-after-mutation discipline).

### 5.3 Route + hub + editors

- `WidgetConfigRoute(onBack)` — obtains the one `hiltViewModel<WidgetConfigViewModel>()`, holds
  `openGroup: WidgetConfigGroup?` in `rememberSaveable` (the `MoreScreen.openRowId` shape, one level deep
  inside the feature). A `BackHandler(enabled = openGroup != null)` returns to the hub; when `null`, back
  falls through to `onBack` (→ Ещё list, back-contract clause 2). Route/Screen split, back arrow, no
  `AccountAvatarAction` (a drill-in).
- `WidgetConfigHubScreen` — `Loading → LoadingBody()`; `Failed → RefusalBody(onRetry=refresh, …)`;
  `Loaded →` a short intro line (adr/0029: «Изменения появятся у посетителя при следующей загрузке
  страницы», mirroring `widgetDescription`) then three tappable group rows (`SectionLabel` + rows, the
  `MoreScreen` row idiom).
- Three editors: `WidgetAppearanceEditor`, `WidgetBehaviourEditor`, `WidgetConsentEditor` — each takes
  `committed: WidgetConfig`, `saving`, `saveError`, `onSave: (WidgetConfig) -> Unit`, `onBack`. Each holds
  its slice as local `rememberSaveable` draft seeded from `committed`. Its Save builds
  `committed.copy(<slice>)` and calls `onSave`. A shared `SnackbarHost` (driven by `savedTick`) shows
  «Сохранено»; `saveError` renders via the app's `ActionErrorBanner` (the `CalendarSetupBody` precedent).

*Since `committed` is passed fresh from the VM's `StateFlow`, re-seeding on every save means an editor
re-entered after a save shows the saved values, and the "seed local draft from committed on entry" is a
`remember(committed) { … }` keyed on committed so a post-save re-entry re-seeds.*

---

## 6. Per-screen field specs

Controls use Material3 primitives already in the app (`OutlinedTextField`, `Switch`,
`ExposedDropdownMenuBox`, `SegmentedButton` — all present in `SettingsScreen`/`NotificationSettingsScreen`/
`CalendarSetupBody`). All validation below is **UX-only courtesy**; `UpdateWidgetConfigHandler` is the
authoritative gate and a `Refused(detail)` is shown verbatim.

### 6.1 Внешний вид (Appearance)

| Field | Control | Validation / behaviour |
|---|---|---|
| `primaryColorHex` | hex `OutlinedTextField` (monospace, placeholder `#2F6FED`, not translated) **+ a live colour swatch** (§7) | client `^#[0-9A-Fa-f]{6}$`, empty → `null`. Invalid → field error, blocks save (mirror `isValidHexColor`). |
| `position` | `SegmentedButton` two options (or dropdown) | labels translated «Справа внизу»/«Слева внизу». |
| `locale` | `ExposedDropdownMenuBox` | options `English`/`Русский` — **endonyms, never translated** (matches console `LOCALE_LABELS`). |
| `panelTitle` | `OutlinedTextField` (placeholder = default-greeting hint) | max-300 counter in the supporting text (UX only), empty → `null` (= built-in default, not blank). |
| `channelSwitcherPlacement` | `SegmentedButton`/dropdown | «Над полем ввода»/«Под кнопкой». |
| `channelSwitcherIconSize` | dropdown, **shown only when placement == `BelowLauncher`** (mirror console conditional render) | «Крупные»/«Средние»/«Мелкие». Always *sent* regardless (never nullable), so a hidden value round-trips its current setting. |

### 6.2 Поведение и приветствие (Behaviour & greeting)

| Field | Control | Validation / behaviour |
|---|---|---|
| `attractAttention` | `Switch` + label + one-line caption (prefers-reduced-motion note) | none. |
| `autoOpenEnabled` | `Switch` + label + caption | none. |
| `autoOpenDelaySeconds` | dropdown of the six values | labels «15 секунд»…«2 минуты» (mirror console `autoOpenDelayLabels`). Always visible (console does not hide it), no branching. |
| `autoOpenGreetingText` | multi-line `OutlinedTextField` | **required (non-blank) when `autoOpenEnabled`** → client check blocks save (mirror console); empty → `null` when disabled. |
| `contactCaptureConfirmationText` | multi-line `OutlinedTextField` | empty → `null`; supporting text notes the literal `{name}` placeholder is substituted by the widget (never expanded client-side). |

### 6.3 Согласие и запись (Consent & booking)

Preserves the console's own read-then-edit shape for the notice (`25-24`) so the screen states *what is
in effect* before offering an editor.

| Field | Control | Validation / behaviour |
|---|---|---|
| `noticeText` | read view of `committed.noticeText` (truncated to ~10 lines with a «показать полностью» toggle), then an «Изменить» that reveals a multi-line `OutlinedTextField` | empty → `null`. Editor is the only view when nothing is set yet (mirror `noticeFormVisible`). |
| `noticeUrl` | read view (link) + editor `OutlinedTextField` (`type=url`, placeholder `https://example.com/privacy`, not translated) | client `https://`-only (mirror `isValidNoticeUrl`), empty → `null`; independent of `noticeText`. |
| `requireContactConsent` | `Switch` + label + caption naming the consent document (`/account/documents`) | none — but this is the `[JsonRequired]` gate; §3 guarantees it is always sent. |
| `acceptUnverifiedPhone` | `Switch` + label + caption stating it is a **temporary** relaxation (`14-15`/`25-39`), phrased as such, not an ordinary feature toggle | none. |
| `allowAttachmentUploadsByDefault` | `Switch` + label + caption (new conversations start with the upload grant on) | none. |

### 6.4 Edge cases

| Case | Handling |
|---|---|
| `site:configure` holder | Row drawn; GET/PUT both succeed (same permission gates both — no rail-vs-server gap). |
| Non-holder reaches the route | Row not drawn; a direct reach → GET `403` → `Failed`/retry (honest, mirror `KtorInstallationApi`). |
| Partial PUT resetting a boolean | Structurally impossible: §3 — a save always PUTs `committed.copy(slice)`, all 16 fields. |
| Unsaved draft on another editor | Discarded on back; never merged into a different screen's save (only the saving screen's slice is copied over `committed`). |
| `autoOpenEnabled` with blank greeting | Client check blocks the save; server also refuses (`WidgetConfig.InvalidAutoOpenGreetingText`) if it slips through. |
| Server validation refusal (`InvalidColor`/`InvalidNoticeText`/`InvalidPanelTitle`/`InvalidNoticeUrl`) | `Refused(detail)` shown verbatim in `ActionErrorBanner`; draft kept; committed unchanged. |
| `channelSwitcherIconSize` hidden (placement `AboveComposer`) | Still sent with its current value (never nullable); round-trips unchanged. |
| Change not visible in an open visitor tab | adr/0029: config is read once at bootstrap. The hub intro line states «появятся при следующей загрузке страницы»; no live push, no polling. |
| Back inside an editor / hub | Editor back → hub; hub back → Ещё list (`onBack`). A field draft is transient VM/`rememberSaveable` state, not persisted beyond the process — acceptable for short config inputs. |

---

## 7. Preview and colour-picker considerations (decided)

**The console has no live widget preview.** Verified in `WidgetConfigPage.tsx`: the only preview
affordances are (a) a small **colour swatch** adornment next to the hex field (`.ago-widget-swatch`,
showing the parsed colour or the `#2f6fed` default when the input is invalid) and (b) a read-only,
truncated preview of the *saved notice text*. There is no rendered/simulated widget anywhere in the
console. `scope-inventory.md` §7's phrase "a live preview … the preview becomes its own pinned region"
overstates what exists; the accurate parity target is the swatch.

**Decisions:**

1. **Port the colour swatch** — a small filled chip beside the `primaryColorHex` field on Внешний вид,
   showing the parsed colour (or the default when the hex is invalid), exactly as the console does. This
   is real parity and cheap. **In this bundle.**
2. **A small static, illustrative launcher mock is the recommended lightweight "preview region"** — a
   pure-Compose drawing of a launcher circle in the chosen colour, at the chosen corner of a phone-frame
   rectangle, on Внешний вид. It honours the scope-inventory's "preview" intent without pretending to be
   live: it renders colour + position only (the two fields it can honestly reflect), clearly labelled as
   illustrative. No widget engine, no network. **Recommended; degrades to the swatch alone if declined.**
3. **A full live/simulated widget preview is OMITTED.** It does not exist in the console (so it is not a
   parity gap), re-implementing the widget's rendering on Android is large net-new work, and adr/0029
   means "live" would be misleading about immediacy. Not built.
4. **Colour picker.** `scope-inventory.md` says "a Material colour input rather than a desktop swatch
   grid", but the console's *actual* control is a plain hex text field + swatch — no picker. Baseline
   parity = **hex `OutlinedTextField` + live swatch + `^#[0-9A-Fa-f]{6}$` courtesy check**. Typing a hex
   on a soft keyboard is genuinely poor, so a **small row of preset colour swatches** (tap to fill the
   hex — a few hardcoded values, no dependency) is a recommended phone-ergonomic add on Внешний вид;
   optional, the author can decline it without affecting parity.

*No `Coil`/image-loader or any package is needed here — the swatch and mock are pure Compose. (Contrast
the channels branding screen, which does add Coil for a remote logo.)*

---

## 8. Nav placement, gating, shared files

### 8.1 Nav

One Каналы row **«Виджет на сайте»** in `MoreScreen`, positioned per `navigation.md` §Ещё order:
«Установка виджета» · **«Виджет на сайте»** · «MAX» · «Telegram» · «VK» · «Почта». This fills the gap the
channels doc §5.2 deliberately left. New `CHANNELS_WIDGET_ROW_ID` const + a `buildMoreRows` entry (under
`canConfigureSite`) + a `when`-branch composing `WidgetConfigRoute`.

### 8.2 Gating

`canConfigureSite` (`Permission.SITE_CONFIGURE`, already computed in `AppShellContent` and passed to
`MoreScreen`) — the identical hide-not-disable gate «Установка виджета» uses. Server enforces the same
`site:configure` on GET and PUT, so no rail-vs-server gap.

### 8.3 Files

Feature files (created in W1, edited by W2/W3):

| File | W1 | W2 | W3 |
|---|---|---|---|
| `core/domain/…/widgetconfig/WidgetConfigApi.kt` (+ types) | create | — | — |
| `core/network/…/widgetconfig/KtorWidgetConfigApi.kt` | create | — | — |
| `app/…/channels/WidgetConfig{UiState,ViewModel}.kt` | create | — | — |
| `app/…/channels/WidgetConfigRoute.kt` (route + hub + sub-nav) | create (hub lists Внешний вид only wired; Поведение/Согласие rows disabled or hidden) | add Поведение row + `when`-branch | add Согласие row + `when`-branch |
| `app/…/channels/WidgetAppearanceEditor.kt` | create | — | — |
| `app/…/channels/WidgetBehaviourEditor.kt` | — | create | — |
| `app/…/channels/WidgetConsentEditor.kt` | — | — | create |

**Shared files every slice touches — sequenced (rule 13, non-interference judged on files):**

| Shared file | W1 | W2 | W3 |
|---|---|---|---|
| `app/…/shell/MoreScreen.kt` | add `CHANNELS_WIDGET_ROW_ID` const + row (under `canConfigureSite`) + `when`-branch → `WidgetConfigRoute` | — | — |
| `app/…/channels/WidgetConfigRoute.kt` (hub group list + sub-nav `when`) | create | add group row + branch | add group row + branch |
| `app/src/main/res/values{,-ru}/strings.xml` | `widget_config_*` shell + Внешний вид keys, both locales | Поведение keys | Согласие keys |
| `app/…/di/AppModule.kt` | `provideWidgetConfigApi` | — | — |

W2/W3 edit W1's `WidgetConfigRoute.kt` and both `strings.xml`, so **W1→W2→W3 are strictly ordered** and
open PRs one at a time. **These slices also collide with the channels bundle (C1–C5) on the same three
cross-cutting files** (`MoreScreen.kt`, `strings.xml`, `AppModule.kt`); the one-PR-at-a-time Android rule
covers both bundles together. Keep each slice's additions append-only and clearly delimited.

---

## 9. Implementation-ready slice specs

Each is one promise that lands green (rule 15). Sizes: S ≈ ½ day, M ≈ 1 day, L ≈ 1½–2 days.

| # | Title | Promise (one thing, lands green) | Size | Depends on |
|---|---|---|---|---|
| **W1** | Android: Виджет на сайте — port/adapter/VM/hub + Внешний вид editor | A `site:configure` operator opens Ещё → Каналы → Виджет на сайте, sees the hub, opens Внешний вид, edits colour (with a live swatch)/position/language/panel-title/channel-switcher, saves, and the change round-trips the **full** config (no other field reset). | **L** | — |
| **W2** | Android: Виджет — Поведение и приветствие editor | From the hub, opens Поведение и приветствие, edits attract-attention/auto-open/delay/greeting/contact-capture-confirmation, saves; the full-DTO round-trip via the W1 shared VM leaves appearance and consent untouched. | **M** | W1 |
| **W3** | Android: Виджет — Согласие и запись editor | From the hub, opens Согласие и запись, edits require-consent/notice(read+edit)/notice-url/unverified-phone/attachments-default, saves; `requireContactConsent` (and every other boolean) is always sent, never silently reset. | **M** | W1 |

**Files per slice: §8.3.** Sequencing: **W1→W2→W3 strictly ordered** (W2/W3 reuse the W1 VM/hub and edit
`WidgetConfigRoute.kt` + both `strings.xml`); all three open PRs one at a time and rebase onto each other's
shared-file edits, and onto the channels bundle's edits to `MoreScreen.kt`/`strings.xml`/`AppModule.kt`.

**Each slice's Done-when:** builds; `dotnet`-side unchanged; the app's four commands
(typecheck / lint / test / `ux-gate` — no Playwright fixture is touched here) pass; a
`KtorWidgetConfigApiTest` covers GET→`Loaded`, the enum/`autoOpenDelaySeconds` mapping both directions,
a `Refused(detail)` on a save rejection, and — the load-bearing one — that `update` serialises **all 16
fields** (a regression test for the absent-boolean trap); the «Виджет на сайте» row appears only under
`canConfigureSite` (W1). W2/W3 additionally: a VM/editor test that a slice save PUTs a config whose
non-slice fields equal the committed values (the round-trip guarantee).

---

## 10. Design decisions MADE

1. **Three group screens** — Внешний вид / Поведение и приветствие / Согласие и запись — behind one
   «Виджет на сайте» hub row. Not seven (over-fragmented), not one form (rejected), not tabs (the brief's
   "each screen that saves" implies independent saves).
2. **One shared `WidgetConfigViewModel` holding the committed full config**, three editors seeding local
   slice-drafts, each Save PUTting `committed.copy(slice)`. This is the structural defence against the
   absent-boolean trap and the cross-screen staleness race.
3. **`WidgetConfig` domain type carries all 16 fields, none optional-away**; the adapter maps them all on
   every PUT — the adapter cannot omit a boolean.
4. **`WidgetAutoOpenDelay` as a Kotlin enum with `seconds: Int`** (wire = the int); unknown int → the
   `Seconds30` server default. The other four enums cross as PascalCase member names.
5. **Colour swatch ported (parity), a small static illustrative launcher mock recommended, a full live
   preview omitted** (does not exist in the console; large net-new; adr/0029 makes "live" misleading).
6. **Colour control = hex field + swatch + courtesy regex** (exact console parity); a preset-swatch
   quick-pick row recommended for phone ergonomics, optional.
7. **Notice keeps the console's read-then-edit shape** (`25-24`) inside Согласие; the other four
   policy/permission panels fold into the same screen.
8. **Gate `site:configure`, no rail-vs-server gap** — same permission on row, GET and PUT.
9. **Nav: single «Виджет на сайте» row** between Установка and MAX, filling the gap the channels doc left;
   internal hub→editor nesting is the feature's own, not Ещё's.
10. **No new package** — swatch and mock are pure Compose (contrast the channels branding screen's Coil).

## 11. Blocking contract questions

**None.** The DTO (16 fields, exact wire types, verbs, gate) is fully determined by
`WidgetConfigEndpoints.cs`, `widgetConfigApi.ts` and `WidgetConfigPage.tsx`; the enum spellings,
`autoOpenDelaySeconds` value set, `[JsonRequired]` behaviour and the `site:configure` placement are all
read from source, not assumed. Two things recorded rather than asked (not scope cuts):

1. **`scope-inventory.md` §7's "live preview" is inaccurate** — the console has only a colour swatch and a
   notice-text read preview. This doc ports the swatch and reasons the live preview out (§7); the
   scope-inventory line should be treated as intent, not a built affordance to match. Flagged so the
   author can correct that row if desired.
2. **The «Виджет на сайте» single row now opens a three-editor hub, not the "one scrolling form with a
   pinned preview" `scope-inventory.md` §7 imagined** — a deliberate supersession by the author's split
   decision, recorded here so the two docs do not silently disagree.
