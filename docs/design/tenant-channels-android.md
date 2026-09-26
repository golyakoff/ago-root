# Каналы (channels) — Android tenant-admin design

Implementation-ready design for the **Каналы** area of the Android tenant-admin app, plus the one
Автоматизация screen that belongs with it by shape (Автоответ вне смены). This is the first focused
chunk of the console→app parity initiative described in `docs/design/briefs/tenant.md` and
`ago-android/docs/{scope-inventory.md,navigation.md}` (§7 Каналы, §8 Автоматизация). It is written so
a sonnet worker can build each slice with no design decisions left.

**Parity is decided, not re-questioned.** Everything the console does on these screens the app does.
Where a phone reads better split by logical group, the split is stated with its motivation. Nothing is
cut.

## Scope

| # | Screen | Console origin | Gate (rail / server) |
|---|---|---|---|
| 1 | **Telegram** — connect / status / disconnect | `TelegramChannelPage` `/channels/telegram` | `site:configure` / `channel:manage` |
| 2 | **MAX** — same scaffold | `MaxChannelPage` `/channels/max` | `site:configure` / `channel:manage` |
| 3 | **VK** — same scaffold + shown-once callbackUrl/webhookSecret | `VkChannelPage` `/channels/vk` | `site:configure` / `channel:manage` |
| 4 | **Почта / branding** — company name + logo upload | `EmailChannelPage` `/channels/email` | `site:configure` / `site:configure` |
| 5 | **Автоответ вне смены** — offline auto-reply | `OfflineAutoReplyPage` `/automation/auto-reply` | `site:configure` / `site:configure` |

**All five rows are drawn only for a `site:configure` holder** — `MoreScreen` already receives
`canConfigureSite: Boolean` (`26-159`) and draws Каналы rows under it. This mirrors `consoleNav.ts`'s
own `buildChannelsItems`, which gates the whole Каналы section on `site:configure` (the `isAdmin`
proxy), not on `channel:manage`. The connect/disconnect/status calls are additionally
server-enforced on `channel:manage` (§Edge cases), exactly the rail-vs-server gap the console's own
page comments document and do not treat as a defect this work introduces.

*Principle (teaching mode): the client gate is UX only — hide-not-disable. `IPermissionChecker` on the
server is the real refusal, so a `site:configure`-only operator who lacks `channel:manage` still sees
the row and gets an honest server refusal on connect, never a form that silently does nothing.*

---

## 1. Shared ChannelConnectScreen scaffold

Telegram, MAX and VK are, on the wire, **one contract** read three times. The status response is
byte-identical across all three (`TelegramChannelStatusResponse` = `MaxChannelStatusResponse` =
`VkChannelStatusResponse`, same seven fields); the connect response differs only in that VK's carries
two extra plaintext fields (`callbackUrl`, `webhookSecret`). The three endpoints differ only by one
URL segment (`telegram` / `max` / `vk`).

So the app builds **one parameterised port and one adapter**, not three near-identical copies.

*Principle: the backend keeps three separate response records "rather than extracted into a shared
shape" (its own `25-09`/`25-175` comments) because each provider's handler is genuinely different
provider-shaped work. The **client** consumes a uniform shape, and three copy-pasted adapters would be
exactly the triplication `KtorInstallationApi`'s own doc comment warns against. The one real
divergence — VK's shown-once reveal — is modelled as nullable fields on the connect result, not a
second port. Alternative considered: a port per channel (mirroring the console's three api modules);
rejected because the console's split is a backend-convention echo, and the app has no identical-code
tolerance the console's per-screen files grew under.*

### 1.1 Domain port (`:core:domain`)

`core/domain/src/main/kotlin/ago/chat/android/core/domain/channels/ChannelConnectionApi.kt`

```
enum class ChannelKind { Telegram, Max, Vk }   // .slug = "telegram" | "max" | "vk"

interface ChannelConnectionApi {
    suspend fun fetchStatus(kind: ChannelKind): ChannelStatusResult
    suspend fun connect(kind: ChannelKind, token: String): ChannelConnectResult
    suspend fun disconnect(kind: ChannelKind, channelCredentialId: String): ChannelDisconnectResult
}
```

Domain types (all in the same package):

| Type | Fields | Meaning |
|---|---|---|
| `ChannelStatus` | `connected: Boolean`, `channelCredentialId: String?`, `createdAt: Instant?`, `verified: Boolean?`, `unreachable: Boolean`, `refusalReason: String?`, `checkedAt: Instant` | The live status read. `verified` is `null` when `!connected` or `unreachable`. `refusalReason` present only when `verified==false && !unreachable`. |
| `ChannelStatusResult` | `Loaded(status)` \| `Failed(NetworkFailure)` | Reuses `core.domain.net.NetworkFailure` (`26-59`). No `NotConnected` arm — `connected:false` is a *loaded* status, not a load failure. |
| `VkReveal` | `callbackUrl: String`, `webhookSecret: String` | Shown-once VK connect payload. Never carried by any status read. |
| `ChannelConnectResult` | `Connected(reveal: VkReveal?)` \| `Refused(detail: String)` \| `Failed(NetworkFailure)` | `reveal` non-null only for a VK connect. `Refused` carries the server's own problem-details `detail` verbatim (provider refusal text / already-connected / 403 / VK-not-available). |
| `ChannelDisconnectResult` | `Disconnected` \| `Refused(detail: String)` \| `Failed(NetworkFailure)` | |

*Principle: the port lives in `:core:domain` because the dependency rule forbids a view model holding
an `HttpClient`; every HTTP-shaped decision (status→meaning, which base URL, which `{siteId}`) belongs
on the far side of it, in `:core:network` — the identical split `InstallationApi`/`ContactDetailsApi`
already establish.*

### 1.2 Adapter (`:core:network`)

`core/network/src/main/kotlin/ago/chat/android/core/network/channels/KtorChannelConnectionApi.kt`

Constructor `(client: HttpClient, apiBaseUrl: String, activeSite: ActiveSiteSelection)` — the exact
shape `KtorInstallationApi` uses. The `{siteId}` is in the URL, so `activeSite.currentSiteId()` is read
directly (the same reason `KtorInstallationApi`/`KtorConversationTagsApi` read it); the bearer token and
`X-Ago-Active-Site` header come from `installAgoRestDefaults`.

Base path: `"$apiBaseUrl/api/v1/sites/$siteId/channels/${kind.slug}"`.

| Verb | Path | 2xx | Non-2xx → | Exception → |
|---|---|---|---|---|
| `GET` | `…/channels/{slug}` | 200 → `Loaded(status)` (parse `ChannelStatusWireDto`) | `Failed(ServerError(status))` — screen reachable only for a `site:configure` holder, so "couldn't load, retry" is honest (same reasoning `KtorInstallationApi` records) | `IOException → Failed(NoConnection)`, else `Failed(Unexpected)` |
| `POST` | `…/channels/{slug}`  body `{"token": <token>}` | 201 → `Connected(reveal)` — `reveal` parsed only for VK (adapter reads `callbackUrl`/`webhookSecret` when `kind==Vk`; ignored keys otherwise via `ignoreUnknownKeys`) | read problem-details `detail` → `Refused(detail)`; if no parseable body → `Failed(ServerError(status))` | as above |
| `DELETE` | `…/channels/{slug}/{credentialId}` | 204 → `Disconnected` | `Refused(detail)` / `Failed(ServerError)` | as above |

Private `@Serializable` wire DTOs, never crossing the port:

```
@Serializable private data class ChannelStatusWireDto(
    val connected: Boolean, val channelCredentialId: String? = null, val createdAt: String? = null,
    val verified: Boolean? = null, val unreachable: Boolean = false,
    val refusalReason: String? = null, val checkedAt: String)
@Serializable private data class ConnectRequestWireDto(val token: String)
@Serializable private data class ConnectResponseWireDto(
    val channelCredentialId: String, val createdAt: String,
    val callbackUrl: String? = null, val webhookSecret: String? = null)  // last two: VK only
@Serializable private data class ProblemDetailsWireDto(val detail: String? = null)
```

Timestamps parse from ISO-8601 to `Instant`; a parse failure on an otherwise-2xx body is `Failed`, not
an empty status (the `shapeGuard` lesson). Never a raw exception class name or hostname on screen —
`NetworkFailure.from` already enforces this.

*Note on `token` never round-tripping (adr/0069): `ConnectRequestWireDto` is the only place the token
appears; no response DTO the app parses has a field it could come back through. Consequence for UX
(§1.4): there is no "edit token" — reconnecting means disconnect, then connect with a **fresh** token.*

### 1.3 UI state (`:app`)

`app/src/main/kotlin/ago/chat/android/channels/ChannelConnectUiState.kt`

```
sealed interface ChannelConnectUiState {
    data object Loading
    data class Failed(reason: NetworkFailure)                        // retry
    data class Disconnected(connecting: Boolean, connectError: String?)
    data class Connected(
        verified: Boolean?, unreachable: Boolean, refusalReason: String?,
        createdAt: Instant?, checkedAt: Instant, channelCredentialId: String,
        reveal: VkReveal?,           // VK, this session only; null on reload / non-VK
        disconnecting: Boolean, disconnectError: String?)
}
```

`Disconnected.connectError` and `Connected.disconnectError` hold a `Refused(detail)`'s text (the
server's own words) or a rendered `NetworkFailure` sentence.

### 1.4 Screen states (the reusable `ChannelConnectScreen`)

`app/src/main/kotlin/ago/chat/android/channels/ChannelConnectScreen.kt` — a stateless composable
taking `state`, a `ChannelConnectConfig` (§1.6), and callbacks (`onConnect(token)`, `onDisconnect`,
`onRetry`, `onDismissDisconnect`). Route/Screen split exactly like `InstallWidgetRoute`/`Screen`:
back arrow in the top bar (a drill-in, not a top-level destination), no `AccountAvatarAction`.

| State | Trigger | What is shown |
|---|---|---|
| **Loading** | initial / retry | `LoadingBody()` |
| **Failed** | status read failed | `RefusalBody(reason, onRetry, …)` — the app's shared four-arm read-failure body |
| **Disconnected** | `connected==false` | not-connected caption; a **token field** (`OutlinedTextField`, `PasswordVisualTransformation`, `KeyboardType.Password`, `autoCorrect=false`); an inline error `Alert` when `connectError!=null`; a primary **Подключить** button (disabled while `token.isBlank()` or `connecting`; label → «Подключение…» while `connecting`) |
| **Connected · verified** | `connected && !unreachable && verified==true` | success badge «Подключено»; «Подключено с {createdAt·date}»; «Проверено {checkedAt·date-time}»; a ghost **Отключить** |
| **Connected · unreachable** | `connected && unreachable` | neutral badge «Не удалось проверить»; connected-since; an **info** `Alert` («Не удалось связаться с провайдером сейчас — подождите и обновите», never the red get-a-new-token text); checkedAt; Отключить |
| **Connected · refused** | `connected && !unreachable && verified==false` | danger badge «Не подтверждено»; connected-since; a **danger** `Alert` with `refusalReason` («… — получите новый токен»); checkedAt; Отключить |
| **Disconnect confirm** | Отключить tapped | Material `AlertDialog` (mirrors console `Dialog`): body «Отключить канал? …»; ghost «Отмена»; **danger** «Отключить»; an inline error `Alert` on `disconnectError`; dismissed by system back (back-contract: dialogs dismiss before the screen). |

The three connected sub-states are one `Connected` UI state discriminated by `verified`/`unreachable` —
the identical badge/alert three-way the console renders, and the reason unreachable and refused are two
different `Alert`s is that a tenant acts on them oppositely (wait-and-retry vs get-a-new-token,
adr/0143).

After a successful connect or disconnect the VM reloads status (`fetchStatus`) — one source of truth,
reloaded, never an optimistic flip (the console's own `load()`-after-mutation discipline).

**Timestamps** render in the device's zone with a per-screen `DateTimeFormatter` (the app's existing
per-screen pattern, e.g. `PendingBookingsScreen`'s `ROW_DATE_FORMAT`): `createdAt` as a date stamp,
`checkedAt` as date + time. UTC `Instant` in, device-zone label out — the project's date-and-time rule.

### 1.5 View models

One abstract base holds all logic; three trivial `@HiltViewModel` subclasses fix the `ChannelKind` so
each opens via `hiltViewModel<…>()` with no runtime argument (the app's established pattern — `MoreScreen`
composes routes by row id, not a NavHost with arguments).

```
abstract class ChannelConnectViewModel(api, ioDispatcher, kind) : ViewModel {
    // state: StateFlow<ChannelConnectUiState>; init { refresh() }
    // refresh()  -> fetchStatus(kind) -> Loading→Loaded/Failed
    // connect(token) -> Disconnected(connecting=true) -> on Connected: keep reveal, refresh();
    //                   on Refused: Disconnected(connectError=detail); on Failed: render sentence
    // disconnect()   -> Connected(disconnecting=true) -> on Disconnected: refresh() (clears reveal);
    //                   on Refused/Failed: surface in disconnectError
}
@HiltViewModel class TelegramChannelViewModel @Inject constructor(api, @IoDispatcher d)
    : ChannelConnectViewModel(api, d, ChannelKind.Telegram)
// …Max, …Vk identically
```

VK's subclass additionally holds the shown-once `reveal` from the last successful `connect` in this
session and threads it into the `Connected` state; on reload `fetchStatus` cannot carry it, so it stays
null and the screen shows the "shown once, now gone" hint (§2.3).

### 1.6 `ChannelConnectConfig` — how a channel parameterises the scaffold

A plain data class of string-resource ids (all in `strings.xml`, both locales), so the scaffold is a
pure renderer and each channel is a thin binding:

```
data class ChannelConnectConfig(
    @StringRes titleRes, @StringRes notConnectedBodyRes,
    @StringRes tokenLabelRes, @StringRes tokenHintRes,
    @StringRes disconnectDialogBodyRes,
    showVkReveal: Boolean)          // true only for VK
```

`titleRes` also names the `MoreScreen` row label (one string per channel).

---

## 2. Per-channel specifics

Each channel is a thin parameterisation of §1. Only what differs is listed.

### 2.1 Telegram
- `ChannelKind.Telegram`, `showVkReveal=false`.
- Files added: `TelegramChannelViewModel.kt`; a `TelegramChannelRoute` (in `ChannelConnectScreen.kt`
  or a small `TelegramChannelRoute.kt`) that builds the Telegram `ChannelConnectConfig` and calls
  `hiltViewModel<TelegramChannelViewModel>()`.
- Строки: `channels_telegram_title` (row + screen), `_not_connected_body`, `_token_label`,
  `_token_hint`, `_disconnect_dialog_body`. Shared строки (badges, connect/disconnect verbs, alerts,
  connected-since, checked-at, retry) live under a `channel_*` prefix, defined once with slice 1.
- Nav: Каналы section row in `MoreScreen`, after «Установка виджета».

### 2.2 MAX
- `ChannelKind.Max`, `showVkReveal=false`. Identical scaffold; labels swapped (the console's own
  "`MaxChannelPage` is `TelegramChannelPage` with the labels swapped").
- Files: `MaxChannelViewModel.kt` + `MaxChannelRoute`. Строки: `channels_max_*` (same five keys).
- Nav: Каналы row.
- Edge case worth a word (not a code path): MAX connect on a deployment without
  `MaxBotApiOptions.PublicWebhookBaseUrl` still succeeds (there is a fallback inbound mechanism),
  unlike VK. Nothing to render differently — the scaffold already handles the normal connect.

### 2.3 VK — the shown-once callbackUrl + webhookSecret
- `ChannelKind.Vk`, `showVkReveal=true`.
- VK's connect response uniquely carries `callbackUrl` + `webhookSecret` (adr/0069's one named
  exception: a secret **AGO generated for the shop**, needed by a *human* pasting it into VK's own
  community Callback API settings — not the shop's own token). It exists in exactly one response, once.
- **The reveal panel** is drawn inside the `Connected` state, below the badge/since/checked block, and
  only when `showVkReveal && state.reveal != null`:
  - an info `Alert` «Настройка VK Callback API» with the setup body;
  - a row for `callbackUrl`: a read-only monospace field + a **Копировать** button (+ a **Поделиться**
    secondary — the operator may hand it to whoever configures VK). A «Скопировано» confirmation.
  - a row for `webhookSecret`: same treatment.
- When `showVkReveal && state.reveal == null` (a reload, or a second operator/device opening an
  already-connected screen): show `channels_vk_secrets_shown_once_hint` instead — stating plainly the
  two values are gone for this session, never silently omitting the panel.
- `reveal` is cleared on disconnect (the VM sets it null before/around `refresh()`), so connecting a new
  token reveals a fresh pair.
- VK-only connect refusals surface verbatim via `Refused(detail)`: a bad token
  (`Channel.InvalidToken`, VK's own refusal text), already-connected
  (`ChannelCredential.AlreadyConnected`), or VK-not-available-on-this-deployment
  (`Channel.NotAvailable`, when no public webhook base URL). The app shows the server `detail` directly
  rather than matching the `type` code — within the app's established "show what the server said"
  discipline; the console only matches the already-connected code to soften the wording, which is not
  worth a client-side `type` branch here.
- Files: `VkChannelViewModel.kt` (holds `reveal`), `VkChannelRoute`, and the reveal region in
  `ChannelConnectScreen.kt` (gated on `config.showVkReveal`). Строки: `channels_vk_*` (five scaffold
  keys + `_setup_title`, `_setup_body`, `_copy_callback_url`, `_copy_webhook_secret`,
  `_callback_url_copied`, `_webhook_secret_copied`, `_secrets_shown_once_hint`, `_share`).
- Nav: Каналы row.

---

## 3. Почта / branding screen

`EmailChannelPage`'s port: this channel has **no per-tenant credential** — it is a settings form, not a
connect flow. Two independent writes with two independent states (a name is accepted synchronously; a
logo's real outcome exists only after `Ago.Chat.Worker`'s validating consumer finishes).

### 3.1 Contract

Endpoints, all `RequireOperatorIdentity` + Application-level `site:configure`
(`SiteBrandingEndpoints`, ago-chat):

| Verb | Path | Body | Response |
|---|---|---|---|
| `GET` | `/api/v1/sites/{siteId}/branding` | — | `SiteBrandingResponse` |
| `PUT` | `/api/v1/sites/{siteId}/branding` | `{"brandCompanyName": string?}` | `{"brandCompanyName": string?}` |
| `POST` | `/api/v1/sites/{siteId}/branding/logo` | **raw image bytes**, `Content-Type` = the image type (not multipart) | `{"logoStatus": string}` |

`SiteBranding` domain fields:

| Field | Type | Meaning |
|---|---|---|
| `brandCompanyName` | `String?` | The brand company name; `null` when unset. |
| `logoUrl` | `String?` | Plain non-expiring public URL, pointed at directly by an image tag; `null` unless `logoStatus` has reached `Ready`. |
| `logoStatus` | `LogoStatus` = `None`\|`Pending`\|`Ready`\|`Rejected` | Upload lifecycle. |
| `logoRejectionReason` | `String?` | Non-null exactly when `Rejected`. |

### 3.2 Port + adapter

Port `core/domain/…/branding/SiteBrandingApi.kt`:
```
interface SiteBrandingApi {
    suspend fun fetch(): SiteBrandingResult                              // Loaded(branding) | Failed(NetworkFailure)
    suspend fun updateCompanyName(name: String?): BrandingWriteResult    // Saved | Refused(detail) | Failed
    suspend fun uploadLogo(bytes: ByteArray, contentType: String): LogoUploadResult  // Accepted(status) | Refused(detail) | Failed
}
```
Adapter `core/network/…/branding/KtorSiteBrandingApi.kt`, constructor
`(client, apiBaseUrl, activeSite)` — `{siteId}` in the URL. `PUT` sends JSON; `POST /logo` sends
`setBody(bytes)` with `contentType(ContentType.parse(contentType))`. A `*.RateLimited` refusal (logo
upload is 5/day, no Retry-After) is just another `Refused(detail)` — surface the server's words.

*Principle: reading the picked image's **bytes and MIME type from a `content://` `Uri` is Android
framework work (`ContentResolver`), so it stays in `:app`** (the VM / a small helper); `:core:network`
is a plain Ktor module with no Android `ContentResolver` dependency and must not gain one. The adapter
receives a `ByteArray` + `contentType` and only POSTs — the dependency rule keeps the framework call
out of the adapter.*

### 3.3 Screen

`app/src/main/kotlin/ago/chat/android/channels/BrandingScreen.kt` (+ `BrandingUiState.kt`,
`BrandingViewModel.kt`). Route/Screen split, back arrow, top-bar **refresh** action (there is no page
reload on a phone; the console relies on reopen/reload to see a `Pending`→`Ready`/`Rejected`
transition — the app gives an explicit re-fetch, and reopening the screen also reloads).

| State | Content |
|---|---|
| Loading | `LoadingBody()` |
| Failed | `RefusalBody(onRetry=refresh)` |
| Loaded | Company-name section, then a divider, then the logo section |

- **Company name**: an `OutlinedTextField` seeded from `brandCompanyName`; a primary **Сохранить**
  (→ «Сохранение…») that PUTs `trimmed.ifBlank { null }`; a success `Alert` «Сохранено»; an error
  `Alert` on `Refused`/`Failed`. Independent `savingName`/`nameSaved`/`nameError` state.
- **Logo**: a **Выбрать изображение** button opening the Android photo picker
  (`rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia())`,
  `PickVisualMediaRequest(ImageOnly)` — no runtime permission needed). On a `Uri`: read `contentType`
  via `contentResolver.getType(uri)` and bytes via `openInputStream`, both on `ioDispatcher`; run the
  **client-side courtesy check** (§3.4); if it passes, `uploadLogo`. Independent
  `uploading`/`uploadError` state; a spinner while uploading.
- **Logo status render**: badge — `Ready`→success «Готов», `Pending`→neutral «Проверяется»,
  `Rejected`→danger «Отклонён», `None`→nothing. When `Rejected && logoRejectionReason`, a danger
  `Alert` with the reason. When `logoUrl != null`, a preview image (§3.5).

### 3.4 Client-side courtesy validation (never the authority)

Mirror `emailChannelLogoValidation.ts`: accept `image/png,image/jpeg,image/gif`; reject `size<=0` or
`size > 200*1024`; decode dimensions with `BitmapFactory.Options(inJustDecodeBounds=true)` and reject
`> 100×100`; an undecodable file → invalid-format message. Reasons →
`invalid-format | too-large | invalid-dimensions | undecodable`, each its own string. The real,
authoritative validation (format, real dimensions, not-animated) is `Ago.Chat.Worker.SiteLogoValidator`
(adr/0177) — an accepted-here file can still come back `Rejected` (an animated GIF, most likely), so a
courtesy pass never claims success; only `logoStatus` does.

### 3.5 Logo preview — the one package decision

Rendering `logoUrl` needs a remote-image loader; the app has **none** today (avatars are emoji, no
`AsyncImage` anywhere). **Add Coil** (`io.coil-kt.coil3:coil-compose` + `coil-network-okhttp`) in this
slice and use `AsyncImage(model = logoUrl, …)`, sized ~100×100dp.

*Justification (required by the no-package rule): the alternative is hand-rolling a bytes-fetch +
`BitmapFactory` + a `remember`ed painter with its own lifecycle, cancellation and caching — reinventing
exactly what Coil is, worse. Coil is the standard Compose image loader; nothing else in the app renders
a remote image, so this is its one call site. If the author would rather not add a dependency for one
100px preview, the honest fallback is to omit the preview and rely on the status badge + reason — but
that drops a parity affordance, so the default is: add Coil.*

### 3.6 Nav & gating
- Nav: Каналы section row «Почта» in `MoreScreen`, drawn under `canConfigureSite`.
- Gate: `site:configure` (server-enforced identically) — so, unlike the three token channels, there is
  no rail-vs-server gap here.

---

## 4. Автоответ вне смены (offline auto-reply)

`OfflineAutoReplyPage`'s offline-auto-reply half. **Order is behaviour** (the server matches
first-rule-wins), so the list is reorderable and the rule is stated on screen. Full-DTO save.

### 4.1 Contract

`OfflineAutoReplyEndpoints` (ago-chat), `RequireOperatorIdentity` + `site:configure`:

| Verb | Path | Body / response |
|---|---|---|
| `GET` | `/api/v1/sites/{siteId}/offline-auto-reply` | `{enabled, fallbackReply, rules:[{keyword,reply}]}` |
| `PUT` | same | request `{enabled, fallbackReply, rules:[{keyword,reply}]}` → echoes the saved shape |

Domain: `OfflineAutoReply(enabled: Boolean, fallbackReply: String, rules: List<AutoReplyRule>)`,
`AutoReplyRule(keyword: String, reply: String)`. `rules` is **ordered** — the array order is the
behaviour. Bounds (mirror `offlineAutoReplyValidation.ts` = domain constants): `MAX_RULES=20`,
`MAX_KEYWORD_LENGTH=64`, `MAX_REPLY_LENGTH=1000` (also bounds the fallback).

### 4.2 Port + adapter
Port `core/domain/…/autoreply/OfflineAutoReplyApi.kt`:
```
interface OfflineAutoReplyApi {
    suspend fun fetch(): OfflineAutoReplyResult                       // Loaded | Failed(NetworkFailure)
    suspend fun update(settings: OfflineAutoReply): OfflineAutoReplyWriteResult  // Saved(settings) | Refused(detail) | Failed
}
```
Adapter `core/network/…/autoreply/KtorOfflineAutoReplyApi.kt`, `{siteId}` in the URL. `Refused(detail)`
carries the server's problem-details `detail` (e.g. `OfflineAutoReply.Invalid`) verbatim — the server is
the authoritative validator; the client's checks are courtesy.

### 4.3 Screen

`app/src/main/kotlin/ago/chat/android/automation/OfflineAutoReplyScreen.kt` (+ UiState, ViewModel).
Route/Screen split, back arrow, a description line stating first-match-wins («Правила проверяются
сверху вниз — срабатывает первое совпавшее»). This screen sits under **Автоматизация**, not Каналы.

- **Enabled** toggle (`Switch` + label).
- **Fallback reply** — a multi-line `OutlinedTextField` (the default reply when enabled and nothing
  matched). Required when `enabled` (client check mirrors `validateDraft`).
- **Rules** — a reorderable list. Each rule is a card: a drag handle (leading), a keyword field, a reply
  field, and a delete (trailing). **Order is visible and is the behaviour** — a small "1, 2, 3…" index
  or the top-to-bottom position, plus the stated first-match-wins line.
  - **Add**: a button/FAB appends a blank rule (not the console's trailing-auto-blank-row idiom, which
    the scope inventory explicitly replaces on a soft keyboard — `scope-inventory.md` §8).
  - **Reorder**: drag by the handle. Use the small `sh.calvin.reorderable` Compose library
    (`ReorderableColumn`/`rememberReorderableLazyListState`).
- **Save** — one primary button; PUTs the full DTO (`enabled`, trimmed `fallbackReply`, `rules` with
  blank rows dropped, **order preserved**). Success `Alert` «Сохранено»; error `Alert` on
  `Refused`/`Failed`. On success, re-seed state from the echoed response.
- **Client-side courtesy validation** before PUT (mirror `validateDraft`, first problem wins): enabled
  needs a non-blank fallback; fallback ≤1000; ≤20 meaningful rules; each rule needs both keyword and
  reply; keyword ≤64; reply ≤1000. A wholly-blank rule is dropped, not flagged.

*Reorder-library decision (no-package rule): the brief and `scope-inventory.md` §8 both call for **drag
handles**, not up/down buttons. Hand-rolling drag-reorder in a `LazyColumn` (pointer math, autoscroll,
item-key animation) is fiddly and a common source of bugs; `sh.calvin.reorderable` is a tiny,
purpose-built, actively-maintained Compose library that does exactly this. Alternative: move-up/down
`IconButton`s (no dependency, fully accessible) — acceptable if the author declines the dep, but it is a
weaker match to the stated design, so the default is the library. Whichever is chosen, keyboard/TalkBack
users get a semantic "move up/down" action.*

### 4.4 Nav & gating
- Nav: **Автоматизация** section — the `AUTOMATION_AFTER_HOURS_ROW_ID` row already exists in
  `MoreScreen` as a placeholder (`26-77`); this slice replaces its `PlaceholderDestinationScreen` branch
  with the real route. **No new row constant** — reuse the existing one; only its `when`-branch and the
  label string change to point at the real screen.
- Gate: `site:configure` (server-enforced identically). The row is already drawn unconditionally today;
  since the whole Автоматизация section is a `site:configure` concern in the console rail, and
  `MoreScreen` currently draws Автоматизация rows always, this slice should also move the after-hours row
  under `canConfigureSite` to match the console rail (a one-line change; state it in the slice).

---

## 5. Cross-cutting: files, nav, DI, gating

### 5.1 Files each slice adds/touches

Independent (no cross-slice conflict):

| Slice | New files |
|---|---|
| 1 Telegram+scaffold | `core/domain/…/channels/ChannelConnectionApi.kt` (+ types); `core/network/…/channels/KtorChannelConnectionApi.kt`; `app/…/channels/ChannelConnect{Screen,UiState,ViewModel}.kt`; `app/…/channels/TelegramChannelViewModel.kt` |
| 2 MAX | `app/…/channels/MaxChannelViewModel.kt` (+ MAX route) |
| 3 VK | `app/…/channels/VkChannelViewModel.kt` (+ VK route + reveal region in `ChannelConnectScreen.kt`*) |
| 4 Branding | `core/domain/…/branding/SiteBrandingApi.kt`; `core/network/…/branding/KtorSiteBrandingApi.kt`; `app/…/channels/Branding{Screen,UiState,ViewModel}.kt`; + Coil |
| 5 Auto-reply | `core/domain/…/autoreply/OfflineAutoReplyApi.kt`; `core/network/…/autoreply/KtorOfflineAutoReplyApi.kt`; `app/…/automation/OfflineAutoReply{Screen,UiState,ViewModel}.kt`; + reorderable lib |

\* Slice 3 edits `ChannelConnectScreen.kt` (built in slice 1) to add the `config.showVkReveal` region —
so slice 3 depends on slice 1's file, sequence after it.

**Shared files every slice touches — must be sequenced (rule 13, non-interference judged on files):**

| Shared file | What each slice adds |
|---|---|
| `app/…/shell/MoreScreen.kt` | slices 1–4: a new `CHANNELS_*_ROW_ID` const + a `buildMoreRows` entry (under `canConfigureSite`) + a `when`-branch composing the route. Slice 5: no new row — repoint the existing `AUTOMATION_AFTER_HOURS_ROW_ID` branch + move it under `canConfigureSite`. |
| `app/src/main/res/values{,-ru}/strings.xml` | each slice adds its own `channels_*` / `automation_*` keys, both locales. Slice 1 also adds the shared `channel_*` scaffold keys. |
| `app/…/di/AppModule.kt` | each slice adds a `@Provides` for its port(s) (`ChannelConnectionApi`, `SiteBrandingApi`, `OfflineAutoReplyApi`), constructed like `provideContactDetailsApi`/`provideInstallationApi`. |

`MoreScreen.kt`, `strings.xml` and `AppModule.kt` collisions are the whole reason these slices open PRs
**one at a time** and cannot be three parallel lanes on the same files. Keep each slice's additions to
those three files append-only and clearly delimited to minimise rebase pain.

### 5.2 Каналы section row order (per `navigation.md` §Ещё)
`Установка виджета` (done) · [`Виджет на сайте` — separate future slice, not this bundle] · `MAX` ·
`Telegram` · `VK` · `Почта`. Add the four new rows in this order; leave the widget-appearance gap.

### 5.3 Gating summary
All Каналы rows and the Автоответ row gate on `Permission.SITE_CONFIGURE` via `MoreScreen`'s existing
`canConfigureSite` boolean (computed once in `AppShellContent` from `OperatorPermissions.Known`). A
section with no rows is not drawn (`buildMoreSections`) — an operator without `site:configure` sees no
Каналы header and (after slice 5's gating change) no after-hours row, exactly as the console rail
hides them.

### 5.4 Edge cases

| Case | Handling |
|---|---|
| `site:configure` holder lacking `channel:manage` | Row is drawn (rail parity). `GET`/`POST`/`DELETE` are server-refused (403) → status load shows `Failed`/retry; connect/disconnect show `Refused(detail)`. Same rail-vs-server gap the console documents; not introduced here. |
| Token pasted with whitespace | Connect button disabled while blank; the server trims/validates. Token field never echoes anything back. |
| Reconnect after a bad/expired token | No edit path (adr/0069). Disconnect, then connect with a fresh token. State this in the disconnect dialog copy is unnecessary; the flow makes it evident. |
| VK reveal lost (reload / 2nd device) | Show `secrets_shown_once_hint`, never a blank panel. Disconnect+reconnect mints a fresh pair. |
| VK not available on deployment (no public webhook base URL) | Connect returns `Channel.NotAvailable` → `Refused(detail)` shown verbatim. |
| Logo accepted client-side but `Rejected` server-side | Expected (animated GIF etc.); the badge+reason is the truth, the courtesy check never claimed success. |
| Logo `Pending` never re-polls | The screen does not poll (parity: neither does the console). The top-bar refresh (and reopening) re-fetches. |
| Rate-limited logo upload (5/day) | `Refused(detail)` with the server's message; no Retry-After to honour. |
| Auto-reply enabled with blank fallback | Client courtesy check blocks the PUT with the mirrored message; the server also refuses (`OfflineAutoReply.Invalid`) if it slips through. |
| Empty rule list / all-blank rows | Blank rows dropped on save; an empty `rules` is a valid save (auto-reply with only a fallback). |
| Back inside a screen | Back returns to the Ещё list (`MoreScreen`'s `openRowId=null`, back-contract clause 2); a dialog/confirm dismisses first. A non-empty token/field draft is transient VM state and is not persisted — acceptable, these are short one-shot inputs, unlike a composer draft. |

---

## 6. Implementation-ready slice specs

Each is one promise that lands green (rule 15). Sizes: S ≈ ½ day, M ≈ 1 day, L ≈ 1½–2 days.

| # | Title | Promise (one thing, lands green) | Size | Depends on |
|---|---|---|---|---|
| **C1** | Android: Telegram channel connect/status/disconnect + shared scaffold | A `site:configure` operator opens Ещё → Каналы → Telegram, connects a bot token, sees the live verified/unreachable/refused status, and disconnects. | **L** | — |
| **C2** | Android: MAX channel on the shared scaffold | Same, for MAX, reusing the C1 scaffold — a MAX row that connects/shows-status/disconnects. | **S** | C1 |
| **C3** | Android: VK channel + shown-once callbackUrl/webhookSecret | Same for VK, plus the connect response's callbackUrl+webhookSecret shown once (copy/share), with the "shown once" hint on reload. | **M** | C1 |
| **C4** | Android: Почта / branding — company name + logo upload | A `site:configure` operator opens Ещё → Каналы → Почта, edits the brand company name, uploads a logo via the photo picker, and sees its Pending/Ready/Rejected(+reason) status and preview. | **M** | — (serialises on shared files) |
| **C5** | Android: Автоответ вне смены — offline auto-reply editor | A `site:configure` operator opens Ещё → Автоматизация → Автоответ вне смены, toggles it, edits the fallback and an ordered, reorderable keyword→reply list, and saves; order is first-match-wins and stated on screen. | **M** | — (serialises on shared files) |

Files per slice: see §5.1. Shared-file sequencing note (§5.1): **C1→C2→C3 are strictly ordered** (C2/C3
reuse C1's scaffold; C3 edits C1's `ChannelConnectScreen.kt`). **C4 and C5 are independent of the
scaffold** but every slice edits `MoreScreen.kt`, both `strings.xml`, and `AppModule.kt`, so **all five
open PRs one at a time** and rebase onto each other's shared-file edits. Recommended order:
**C1, C2, C3, C4, C5** (channels grouped, then branding, then auto-reply) — but C4/C5 may slot anywhere
after C1 lands the shared `channel_*` strings, provided the one-PR-at-a-time rule holds.

Each slice's Done-when: builds; `dotnet`-side unchanged; the app's four commands
(typecheck/lint/test + `ux-gate` if a fixture is touched — none here) pass; adapter has a
`Ktor…ApiTest` (status→state mapping, the connect refusal→`Refused(detail)`, VK reveal parse); a
`MoreScreen` row appears only under `canConfigureSite`.

---

## 7. Notes and one adjacent-parity flag (no blocking questions)

Everything needed to build is settled above; contract detail is unambiguous in the read sources. Two
things to record rather than ask:

1. **Assignment penalty is not in this bundle, and is not being cut.** The console co-locates the
   *assignment penalty* control (`AssignmentPenaltySection`, `AssignmentPenaltyEndpoints`) on the same
   `/settings/auto-reply` route as the offline auto-reply. It is a **different backend resource** and an
   assignment/automation concern, and `navigation.md` draws it **nowhere** — the Android nav maps
   «Автоответ вне смены» to the offline-auto-reply only. Parity for it belongs to a separate
   assignment-settings item, not this Каналы bundle (rule 15: different promise). Flagged so the author
   can file it in its own area; deliberately not designed or cut here.

2. **Two small package additions**, each justified inline: **Coil** (C4, logo preview — the app has no
   image loader) and **`sh.calvin.reorderable`** (C5, drag-to-reorder). Both have a stated no-dependency
   fallback (omit preview / use up-down buttons) if the author prefers; the defaults are to add them,
   because both match the parity design better than the fallback. Not blocking — the author can veto a
   dep at review and the slice degrades gracefully.
