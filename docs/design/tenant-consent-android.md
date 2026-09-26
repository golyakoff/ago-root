# Документы согласий (consent documents) — Android tenant-admin design

Implementation-ready design for the **Документы согласий** area of the Android tenant-admin app — the
Администрирование screen that lets a tenant read their two published consent documents, see who
accepted which version and when, and **publish a new version from the phone**. It is the next focused
chunk of the console→app parity initiative described in `docs/design/briefs/tenant.md`,
`docs/design/tenant-management-android.md` (slices **I** and **I2**), and
`ago-android/docs/{scope-inventory.md,navigation.md}` (§9 Администрирование). It is written so a sonnet
worker can build each slice with no design decisions left.

**Full parity is decided, not re-questioned.** The author has decided the app does everything the
console's `DocumentsPage` does — reading the current published version, the per-version acceptances
table, **and** publishing a new version from a full-screen editor (`tenant-management-android.md` §5
open decision 2, resolved **(b) — full**). Nothing here is cut, and the "read-only, publishing stays in
the console" option is closed. Where a phone reads better split into separate screens, the split is
stated with its motivation.

## Scope

| # | Screen | Console origin | Gate (rail / server) |
|---|---|---|---|
| 1 | **Документы согласий** — overview: two purposes, version list per purpose, binding-status badge, per-version acceptances | `DocumentsPage` `/account/documents` | `site:configure` / `site:configure` |
| 2 | **Просмотр документа** — read one published version's full text ("as a visitor would") | `DocumentsPage`'s `Читать как посетитель` link → `/policies/{key}` | none (public read) / none |
| 3 | **Публикация версии** — full-screen editor: title + body, publish a new version | `DocumentsPage`'s publish form (`ConsentDocumentPanel`) | `site:configure` / `site:configure` |

**The whole area is drawn only for a `site:configure` holder** — `MoreScreen` already receives
`canConfigureSite: Boolean` and draws Администрирование rows under it. This mirrors the console:
`DocumentsPage` renders `AccessRefusal` unless `hasPermission("site:configure")`, and every route behind
it (`SiteConsentDocumentEndpoints`, ago-chat) is server-enforced on `site:configure` inside the handler
(`Permission.SiteConfigure`, checked against the route's own `siteId`). Unlike the token channels
(Telegram/MAX/VK, which split `site:configure` rail from `channel:manage` server), consent has **no
rail-vs-server gap** — the same permission gates the row and every write, so a `site:configure` operator
who sees the row can perform every action on it.

*Principle (teaching mode): the client gate is UX only — hide-not-disable, ported from `consoleNav.ts`'s
"a section with no rows is not drawn". `IPermissionChecker` on the server is the real refusal. Because
consent's client gate and server gate are the identical permission, a drawn row never leads to a
silent-no-op form — the gap that had to be designed around for the token channels does not exist here.*

---

## 1. The contract — exactly what the wire carries

Three tenant-scoped routes (authenticated, `site:configure`) plus the **public document-body surface**
the overview links into. The single most important contract fact: **the tenant-scoped overview carries
version *metadata* only — never a body.** Reading the actual text of a version is a separate call to the
anonymous published-document surface (`GetSiteConsentDocumentsOverview`'s own remark:
"no document body here, this is a list screen's own row, not the read-a-specific-version surface").

### 1.1 Tenant-scoped surface — `SiteConsentDocumentEndpoints` (ago-chat)

All three are `RequireOperatorIdentity` at the route and `site:configure` inside the handler, `{siteId}`
in the URL.

| Verb | Path | Body | Response |
|---|---|---|---|
| `GET` | `/api/v1/sites/{siteId}/consent-documents` | — | `SiteConsentDocumentsResponse` |
| `POST` | `/api/v1/sites/{siteId}/consent-documents/{purpose}` | `{"title": string, "body": string}` | `PublishedSiteConsentDocumentResponse` (200) |
| `GET` | `/api/v1/sites/{siteId}/consent-documents/{purpose}/acceptances` | — | `SiteConsentAcceptanceResponse[]` |

`{purpose}` is the enum name verbatim — **`Contact` or `Marketing`** (`VisitorConsentPurpose`), exactly
as the console passes it. A string that does not parse is `Document.InvalidPurpose` (400).

```
SiteConsentDocumentsResponse {
    contact: SiteConsentDocumentResponse,
    contactConsentRequired: bool,          // sits BESIDE contact, not inside it — a fact about the
                                           // site's WidgetConfig.RequireContactConsent, not the document
    marketing: SiteConsentDocumentResponse
}
SiteConsentDocumentResponse {
    purpose: string,                       // "Contact" | "Marketing"
    documentKey: string,                   // the derived storage key — the app never composes it, only
                                           // reads it back and feeds it to the public read surface (§1.2)
    versions: PublishedVersionResponse[]   // newest-first; empty when nothing published yet
}
PublishedVersionResponse { version: string, sequence: int, title: string, publishedAt: DateTimeOffset }
                                           // NO body

PublishedSiteConsentDocumentResponse {     // the publish echo — uniquely DOES carry the body
    documentKey: string, version: string, sequence: int, title: string, body: string, publishedAt: DateTimeOffset
}

SiteConsentAcceptanceResponse {
    subjectKind: string,                   // e.g. "Visitor"
    subjectId: guid,                       // serialised as a GUID string
    documentVersion: string,               // which version this subject accepted
    acceptedAt: DateTimeOffset
}                                          // NO clientIp / userAgent — narrower than the domain record
                                           // by deliberate design (adr/0146; personal-data.md)
```

The acceptances route returns **every acceptance for the whole document kind**, across all versions —
the client filters by `documentVersion` to scope a list to one version (the console's own
`AcceptancesList` does exactly this: `acceptances.filter(a => a.documentVersion === version)`; a
backend version-scoped endpoint was checked and found unnecessary, `23-37`/`25-21`).

### 1.2 Public document-body surface — `DocumentEndpoints` (ago-chat)

Anonymous (`AllowAnonymous`), IP-rate-limited, under `/api/v1/documents`. This is where the *text* of a
version is read — the same surface the console's `Читать как посетитель` link opens, and the same one
the planned `…/policies/{key}` deep-link reader (`navigation.md`) will use.

| Verb | Path | Response | Cache |
|---|---|---|---|
| `GET` | `/api/v1/documents/{documentKey}` | `DocumentVersionResponse` (**current** version) | `public, max-age=300` |
| `GET` | `/api/v1/documents/{documentKey}/versions/{version}` | `DocumentVersionResponse` (a **specific** version) | `public, max-age=86400, immutable` |

```
DocumentVersionResponse { documentKey: string, version: string, sequence: int, title: string, body: string, publishedAt: DateTimeOffset }
```

**Two routes, not one with `?version=`** — a specific version is immutable and cacheable far more
aggressively than the moving "current" pointer, a difference the backend deliberately surfaces at the
URL level (`DocumentEndpoints`' own remark). The app honours it: "read the current version" → the first
route; "read version v3" → the second. `404` is `Document.NotFound`; `429` carries `Retry-After`.

### 1.3 Validation bounds (mirror server; server is authoritative)

From `PublishedDocumentVersion` (ago-chat domain), the constants the courtesy check mirrors:

| Field | Rule |
|---|---|
| `title` | non-blank after trim; `≤ 200` chars (`MaxTitleLength`) |
| `body` | non-blank after trim; `≤ 100_000` chars (`MaxBodyLength`) |

The console checks only non-blank; the app mirrors the length bounds too because a phone editor is where
a paste can exceed them silently. A slip-through is still refused server-side as `Document.Invalid`.

### 1.4 Error vocabulary (problem-details `type` / `detail`)

`Document.Invalid` (400, empty/over-long), `Document.InvalidPurpose` (400), `Document.NotFound` (404),
`Document.ConsentDocumentUnavailable` (widget requires consent but nothing published), `Site.NotFound`,
`Conversation.Forbidden` (403 — the `site:configure` refusal), and the one worth special-casing:
**`Document.PublishConflict` (409)** — two publishes for the same key raced; the correct remedy is to
retry the identical request (`PublishedDocumentErrors.PublishConflict`). Every code's human `detail` is
surfaced verbatim; only `PublishConflict` gets a client affordance (a retry that re-submits), the rest
render their `detail` in an error `Alert`.

---

## 2. Ports & adapters — the layering

Two ports, because the surface is genuinely two: a **tenant-scoped, authenticated, `{siteId}`-in-URL**
surface (overview / acceptances / publish), and an **anonymous, no-site, no-bearer** document-body read.

*Principle (teaching mode): the two ports live in `:core:domain` because the dependency rule forbids a
view model holding an `HttpClient`; every HTTP-shaped decision (which status means what, which base URL,
which `{siteId}`, current-vs-version route) belongs on the far side of the interface, in `:core:network`
— the identical split `InstallationApi`/`ContactDetailsApi` already establish. **They are two ports, not
one,** because `KtorSiteConsentDocumentsApi` reads `activeSite.currentSiteId()` and rides the
`X-Ago-Active-Site` + bearer defaults, while the body read is an anonymous endpoint that needs none of
that — folding them into one adapter would mix two call shapes and one would carry credentials an
anonymous route neither needs nor should see. The alternative — one `SiteConsentDocumentsApi` with a
`fetchBody` method — was rejected for that reason, and because the body port is exactly what the future
`…/policies/{key}` reader reuses (`navigation.md`), so it earns its own home now.*

### 2.1 `SiteConsentDocumentsApi` (`:core:domain`)

`core/domain/src/main/kotlin/ago/chat/android/core/domain/consent/SiteConsentDocumentsApi.kt`

```
enum class ConsentPurpose { Contact, Marketing }   // .slug = "Contact" | "Marketing" (enum name verbatim)

interface SiteConsentDocumentsApi {
    suspend fun fetchOverview(): SiteConsentDocumentsResult
    suspend fun fetchAcceptances(purpose: ConsentPurpose): ConsentAcceptancesResult
    suspend fun publish(purpose: ConsentPurpose, title: String, body: String): ConsentPublishResult   // slice I2
}
```

Domain types (same package):

| Type | Fields | Meaning |
|---|---|---|
| `ConsentDocumentSummary` | `purpose: ConsentPurpose`, `documentKey: String`, `versions: List<ConsentVersion>` | One purpose's document; `versions` newest-first, empty when nothing published. |
| `ConsentVersion` | `version: String`, `sequence: Int`, `title: String`, `publishedAt: Instant` | One published version's row. No body. |
| `ConsentOverview` | `contact: ConsentDocumentSummary`, `contactConsentRequired: Boolean`, `marketing: ConsentDocumentSummary` | The whole overview read. |
| `ConsentAcceptance` | `subjectKind: String`, `subjectId: String`, `documentVersion: String`, `acceptedAt: Instant` | One acceptance. `subjectId` kept a `String` (the GUID text) — the app never treats it as a typed id. |
| `SiteConsentDocumentsResult` | `Loaded(ConsentOverview)` \| `Failed(NetworkFailure)` | Reuses `core.domain.net.NetworkFailure` (`26-59`). |
| `ConsentAcceptancesResult` | `Loaded(List<ConsentAcceptance>)` \| `Failed(NetworkFailure)` | Loaded-but-empty is a real state (nobody accepted yet), never a failure. |
| `ConsentPublishResult` | `Published(ConsentVersion)` \| `Conflict` \| `Refused(detail: String)` \| `Failed(NetworkFailure)` | `Conflict` is `Document.PublishConflict` (retry-able); `Refused` carries the server `detail` verbatim. `Published` carries the echoed new version (metadata; the body echo is discarded — the overview reload is the source of truth). |

### 2.2 `PublishedDocumentApi` (`:core:domain`)

`core/domain/src/main/kotlin/ago/chat/android/core/domain/documents/PublishedDocumentApi.kt`

```
interface PublishedDocumentApi {
    // version == null → current-version route; a value → the specific-version route
    suspend fun fetchDocument(documentKey: String, version: String?): PublishedDocumentResult
}
```

| Type | Fields | Meaning |
|---|---|---|
| `PublishedDocument` | `documentKey: String`, `version: String`, `title: String`, `body: String`, `publishedAt: Instant` | The text of one version. |
| `PublishedDocumentResult` | `Loaded(PublishedDocument)` \| `NotFound` \| `Failed(NetworkFailure)` | `NotFound` = `404`/`Document.NotFound` (a rare race — the version row existed in the overview but was gone by read time); distinct from `Failed` so the reader can say "this version is no longer available" rather than "retry". |

### 2.3 Adapters (`:core:network`)

`core/network/.../consent/KtorSiteConsentDocumentsApi.kt`, constructor
`(client: HttpClient, apiBaseUrl: String, activeSite: ActiveSiteSelection)` — the exact
`KtorInstallationApi`/`KtorConversationTagsApi` shape (`{siteId}` in the URL, so `currentSiteId()` is
read directly; bearer + `X-Ago-Active-Site` come from `installAgoRestDefaults`).

Base path: `"$apiBaseUrl/api/v1/sites/$siteId/consent-documents"`.

| Verb | Path | 2xx | Non-2xx → | Exception → |
|---|---|---|---|---|
| `GET` | `…/consent-documents` | 200 → `Loaded(overview)` | `Failed(ServerError(status))` — reachable only for a `site:configure` holder, so "couldn't load, retry" is honest (same reasoning `KtorInstallationApi` records for its own `Conversation.Forbidden`) | `IOException → Failed(NoConnection)`, else `Failed(Unexpected)` |
| `POST` | `…/consent-documents/{slug}` body `{title, body}` | 200 → `Published(version)` | 409 → `Conflict`; else read problem-details `detail` → `Refused(detail)`; no parseable body → `Failed(ServerError(status))` | as above |
| `GET` | `…/consent-documents/{slug}/acceptances` | 200 → `Loaded(list.filter-later)` | `Failed(ServerError(status))` | as above |

`core/network/.../documents/KtorPublishedDocumentApi.kt`, constructor `(client, apiBaseUrl)` — **no
`activeSite`**, the anonymous surface carries no site. URL:
`"$apiBaseUrl/api/v1/documents/$documentKey"` for current, `"…/$documentKey/versions/$version"` for a
specific version.

| 2xx | Non-2xx → | Exception → |
|---|---|---|
| 200 → `Loaded(document)` | 404 → `NotFound`; else `Failed(ServerError(status))` (429 among them — the endpoint's `Retry-After` is not honoured with a timer here, it is a plain retry-able failure, the same "surface the server said busy" the logo-upload rate limit gets in the channels design) | `IOException → Failed(NoConnection)`, else `Failed(Unexpected)` |

Private `@Serializable` wire DTOs, never crossing a port (`ignoreUnknownKeys` handles the fields the app
does not draw — `sequence` on the acceptance rows, etc.):

```
@Serializable private data class OverviewWireDto(
    val contact: DocumentWireDto, val contactConsentRequired: Boolean = false, val marketing: DocumentWireDto)
@Serializable private data class DocumentWireDto(
    val purpose: String, val documentKey: String, val versions: List<VersionWireDto> = emptyList())
@Serializable private data class VersionWireDto(
    val version: String, val sequence: Int, val title: String, val publishedAt: String)
@Serializable private data class PublishRequestWireDto(val title: String, val body: String)
@Serializable private data class PublishResponseWireDto(
    val documentKey: String, val version: String, val sequence: Int, val title: String,
    val body: String = "", val publishedAt: String)                 // body echoed but discarded
@Serializable private data class AcceptanceWireDto(
    val subjectKind: String, val subjectId: String, val documentVersion: String, val acceptedAt: String)
@Serializable private data class DocumentBodyWireDto(
    val documentKey: String, val version: String, val sequence: Int, val title: String,
    val body: String, val publishedAt: String)
@Serializable private data class ProblemDetailsWireDto(val detail: String? = null)
```

Timestamps parse from ISO-8601 to `Instant`; a parse failure on an otherwise-2xx body is `Failed`, not
an empty read (the `shapeGuard` lesson). `NetworkFailure.from`/`classify` never puts a raw exception
class name or a hostname on screen (`26-59`).

---

## 3. Screens

Three screens, one Ещё destination. The `ConsentDocumentsRoute` (opened from `MoreScreen`) owns internal
navigation between the three via a small held state, exactly the state-driven approach `MoreScreen`'s own
`openRowId` and `WorkerRecutScreen`'s step state already use — **not** a nested `NavHost` (the app's tab
hosts use one, but this is a three-screen linear drill with no need to deep-link into reader/editor from
outside). `BackHandler` sends reader/editor back to the overview, and the overview's back invokes the
`onBack` that returns to the Ещё list (back-contract: `navigation.md` "back from any Ещё screen returns
to the Ещё list").

```
sealed interface ConsentNav {
    data object Overview
    data class Reader(documentKey: String, version: String?, title: String)   // version null = current
    data class Editor(purpose: ConsentPurpose, purposeTitle: String)           // slice I2
}
```

### 3.1 Screen 1 — Документы согласий (overview)

`app/src/main/kotlin/ago/chat/android/documents/ConsentDocumentsScreen.kt` (+ `UiState`, `ViewModel`).
Route/Screen split, back arrow (a drill-in, no `AccountAvatarAction`). Two purpose panels, Contact then
Marketing, each an M3 `Card` (the mockup's `.card`).

`ConsentDocumentsUiState`:

```
sealed interface ConsentDocumentsUiState {
    data object Loading
    data class Failed(reason: NetworkFailure)                    // retry
    data class Loaded(overview: ConsentOverview)                 // draws both panels
}
```

Per purpose panel:

| Element | Content |
|---|---|
| **Binding-status badge** (an `Alert`) | **Contact**, `contactConsentRequired == true` → info «Виджет требует это согласие перед приёмом контактов». `false` → **danger** «Этот документ ничего не требует, пока сбор согласия выключен» + a line pointing at «Виджет на сайте» (the widget-config screen that owns `RequireContactConsent`). **Marketing** → info «Это согласие никогда ничего не требует — оно только фиксирует, кто согласился на маркетинг». (Mirrors the console's Contact/Marketing badge exactly, including the cross-reference to the widget screen.) |
| **Current version row** | When `versions` non-empty: `versions[0]` — title, `version`, `publishedAt` (device-zone **date**), an «Открыть» action → `Reader(documentKey, version=null /*current*/, title)`, and a «Кто принял» expander (§3.2). When empty: «Ни одной версии ещё не опубликовано». |
| **Older versions** | `versions.drop(1)` behind an expandable «Предыдущие версии (N)» (`ExpandableSection`/`details`-equivalent). Each row: `version` + title + date, «Открыть» → `Reader(documentKey, version=v.version, title)`, and its own «Кто принял» expander. |
| **Publish action** (slice I2) | A ghost «Опубликовать новую версию» → `Editor(purpose, purposeTitle)`. Drawn always (there is always something to publish, even the first version — when `versions` is empty this is the only action besides the empty-state caption). |

**Timestamps** render device-zone with a per-screen `DateTimeFormatter` (the app's `PendingBookingsScreen`
pattern): `publishedAt` as a date stamp. UTC `Instant` in, device-zone label out — the date-and-time rule.

### 3.2 Per-version acceptances (inline expander, slice I)

Mirrors the console's `VersionAcceptancesToggle` → `AcceptancesList`, one expander **scoped to exactly one
version**. Tapping «Кто принял» on a version loads the acceptances (all versions), filters to
`documentVersion == thisVersion`, and renders a compact table inside the panel.

- A small per-expander loader (`Loading`/`Failed(retry)`/`Loaded`), fetched lazily on first expand and
  keyed by `(purpose, version)` so two versions have two independent lists — never merged (the `25-21`
  crux: conflating two versions' acceptances misrepresents who agreed to which text).
- **Privacy note** above the table, always: «Показаны только кто и когда — без IP-адреса и браузера»
  (the console's own `documentsAcceptancesPrivacyNote`; the record's IP/user-agent are not on the wire
  at all — adr/0146).
- Table columns, phone-narrowed to **two**: **Кто** (`subjectKind` mapped — `Visitor` → «Посетитель»,
  else the raw kind — plus the `subjectId` as an 8-char mono short code, the `conversationId.slice(0,8)`
  idiom the storage screen already uses; a long-press copies the full id) and **Принято** (`acceptedAt`,
  device-zone **date + time**). The version column the console shows is dropped: the list is already
  scoped to one version, so it is redundant here where width is scarce.
- Empty → «Пока никто не принял эту версию».

*Decision (subject id shortened): the console prints the full 36-char GUID in `<code>`; a phone cannot
spend a column on that. The 8-char mono prefix is enough to correlate two rows, and long-press-to-copy
recovers the full id when a tenant genuinely needs it — no information is destroyed, only deferred behind
a gesture. Stated rather than silently truncated.*

### 3.3 Screen 2 — Просмотр документа (reader, slice I)

`app/src/main/kotlin/ago/chat/android/documents/ConsentDocumentReaderScreen.kt` (+ `UiState`, `ViewModel`).
A stateless read of one version's text via `PublishedDocumentApi.fetchDocument(documentKey, version)`.
Route/Screen split, back arrow → overview. Top bar title = the version title.

| State | Content |
|---|---|
| Loading | `LoadingBody()` |
| Failed | `RefusalBody(reason, onRetry)` |
| NotFound | a terminal «Эта версия больше недоступна» (the `Document.NotFound` race) — no retry, a back affordance |
| Loaded | a header line — version + `publishedAt` (device-zone date) — then the **body** as selectable, scrollable text (`SelectionContainer` around a `Text`). Body is plain text (stored/served as plain text; the widget renders it as such), so no Markdown rendering — a `verticalScroll` column, generous line height. |

*The reader and `PublishedDocumentApi` are deliberately reusable by the planned `…/policies/{key}`
deep-link reader (`navigation.md`), which reads the same anonymous surface with no session — building
that deep link is out of scope for these slices, but nothing here blocks it.*

### 3.4 Screen 3 — Публикация версии (editor, slice I2)

`app/src/main/kotlin/ago/chat/android/documents/ConsentPublishEditorScreen.kt` (+ `UiState`, `ViewModel`).
A full-screen editor, **blank-start** — publishing is always a *new* version, never an edit of an
existing one (the console's form also starts empty; there is no pre-fill and no draft carried from a
prior version). Route/Screen split, back arrow with a discard guard (below).

`ConsentPublishUiState`: `data class Editing(title, body, validationError: String?, submitError: String?, publishing: Boolean, confirming: Boolean)`.

| Element | Content |
|---|---|
| **Description line** | «Опубликованный текст сразу увидят посетители, и новые согласия будут привязаны к этой версии». |
| **Title field** | single-line `OutlinedTextField`, label «Заголовок», max 200, a live counter near the limit. |
| **Body field** | multi-line `OutlinedTextField` filling the screen, label «Текст документа», `KeyboardType.Text`, max 100_000. Native long-press paste is the primary path; an explicit «Вставить из буфера» text button (reads `ClipboardManager` primary clip text into the body when present) is offered because pasting a prepared legal text from the clipboard is the real mobile path (`scope-inventory.md` §9). |
| **Publish** | a primary «Опубликовать» → runs the courtesy check → opens a confirm `AlertDialog`: body «Опубликовать новую версию «{purposeTitle}»? Посетители сразу увидят этот текст.», ghost «Отмена», primary «Опубликовать». |
| **Errors** | `validationError` (courtesy check) and `submitError` (`Refused`/`Failed`/conflict) each an inline danger `Alert`. |

**Publish flow (VM):** confirm → `publishing=true` → `SiteConsentDocumentsApi.publish(purpose, trimmedTitle, trimmedBody)`:
- `Published` → navigate back to the overview and **reload it** (`fetchOverview`) — one source of truth,
  reloaded, never an optimistic insert (the console's `onPublished()` → `load()` discipline). A success
  cue rides the overview («Версия опубликована»).
- `Conflict` → `submitError` = «Публикация конфликтует с одновременной публикацией. Повторите.», and the
  «Опубликовать» button stays enabled so the identical request can be re-submitted (the `409` remedy is
  retry, not a fix).
- `Refused(detail)` → `submitError` = the server's words verbatim.
- `Failed(reason)` → `submitError` = the rendered `NetworkFailure` sentence.

**Courtesy validation before publish** (mirror server, first problem wins): title non-blank; title ≤200;
body non-blank; body ≤100_000. A slip-through is refused server-side as `Document.Invalid`.

---

## 4. Cross-cutting: nav, DI, gating, edge cases

### 4.1 Nav & gating

- **Home:** Администрирование section of Ещё. `navigation.md` lists it as «документы» under
  Администрирование (`продукты, оплата, документы, ИИ, хранилище, выгрузка`).
- **Row:** a new `ADMINISTRATION_DOCUMENTS_ROW_ID = "administration-documents"` in `MoreScreen.kt`, label
  «Документы согласий», added to `buildMoreRows` under `MoreSectionId.Administration`, **only when
  `canConfigureSite`** (like the Каналы rows). Its `when(openRow.id)` branch composes
  `ConsentDocumentsRoute(onBack = { openRowId = null })`.
- **Gate:** `Permission.SITE_CONFIGURE` via `canConfigureSite`. A section with no rows is not drawn
  (`buildMoreSections`), so an operator without `site:configure` sees no Документы row (and, today, the
  Администрирование section's other rows are placeholders — this slice adds the first real one there,
  the same "first real row" move `26-159` made for Каналы).

### 4.2 DI

`app/.../di/AppModule.kt` gains two `@Provides`, built like `provideInstallationApi`/`provideContactDetailsApi`:

```
fun provideSiteConsentDocumentsApi(client, activeSite): SiteConsentDocumentsApi =
    KtorSiteConsentDocumentsApi(client, config.apiBaseUrl, activeSite)
fun providePublishedDocumentApi(client): PublishedDocumentApi =
    KtorPublishedDocumentApi(client, config.apiBaseUrl)            // no activeSite — anonymous surface
```

### 4.3 Edge cases

| Case | Handling |
|---|---|
| No version published yet for a purpose | `versions` empty → «Ни одной версии ещё не опубликовано» + the «Опубликовать новую версию» action; the badge still renders (a Contact doc that binds nobody, or Marketing that never binds). |
| Contact consent required but nothing published | Server would answer `Document.ConsentDocumentUnavailable` to a *visitor*; the overview itself still loads (it lists whatever versions exist, here none). The badge says the widget requires consent; the empty version list makes the gap visible. Publishing the first version closes it. |
| `site:configure` holder, everything server-refused | No rail-vs-server gap for consent (same permission both sides). A `403` on any call → `Failed`/retry (overview/acceptances) or `Refused(detail)` (publish) — a stale permission set, the honest "couldn't, retry". |
| Reader 404 (version vanished between overview and read) | `NotFound` terminal state «Эта версия больше недоступна», not a retry loop. |
| Publish conflict (two publishes race) | `Conflict` → retry-able message, button stays enabled; the `409` remedy is re-submit (`PublishedDocumentErrors.PublishConflict`). |
| Publish body/title over the limit | Courtesy check blocks with the mirrored message; server also refuses `Document.Invalid` if it slips through. |
| Body is long (up to 100k chars) | Reader scrolls; editor body field scrolls. Neither paginates — parity with the console, which renders the whole text. |
| Rate-limited document read (public surface, per-IP) | `429` → `Failed(ServerError(429))` → the reader's retry; no `Retry-After` timer honoured (parity with how the channels design treats the logo rate limit). |
| Back inside the editor with a non-empty draft | A **discard-confirmation** `AlertDialog` («Выйти без публикации? Введённый текст не сохранится.») before leaving — a composed legal text is worth guarding, unlike the channels' transient token field. An empty draft leaves silently. This mirrors `navigation.md`'s re-cut flow ("leaving the flow entirely discards the decisions with an explicit confirmation"). |
| Back inside the reader / from the overview | Reader/editor → overview (`BackHandler`); overview → Ещё list (`onBack`). A dialog dismisses before the screen under it. |
| Acceptances table for a version nobody accepted | «Пока никто не принял эту версию» — a loaded-empty state, never an error. |

---

## 5. Implementation-ready slice specs

Each is one promise that lands green (rule 15). Sizes: S ≈ ½ day, M ≈ 1 day, L ≈ 1½–2 days.

| # | Title | Promise (one thing, lands green) | Size | Depends on |
|---|---|---|---|---|
| **I** | Android: consent documents — read current/older versions + acceptances | A `site:configure` operator opens Ещё → Администрирование → Документы согласий, sees each purpose's binding-status badge and version list, opens a version to read its full text, and expands "кто принял" to see who accepted that version and when. | **M** | — |
| **I2** | Android: consent documents — publish a new version | A `site:configure` operator taps «Опубликовать новую версию» on a purpose, composes a title + body in a full-screen editor (paste-friendly), confirms, and publishes — the overview reloads showing the new current version; a publish conflict is retry-able. | **M** | I |

### 5.1 Files each slice adds/touches

**Slice I — new files (independent, no cross-slice conflict):**

| File | Role |
|---|---|
| `core/domain/.../consent/SiteConsentDocumentsApi.kt` | port + `ConsentPurpose`, `ConsentOverview`, `ConsentDocumentSummary`, `ConsentVersion`, `ConsentAcceptance`, `SiteConsentDocumentsResult`, `ConsentAcceptancesResult` (declare `publish`/`ConsentPublishResult` too, or leave to I2 — see note) |
| `core/domain/.../documents/PublishedDocumentApi.kt` | port + `PublishedDocument`, `PublishedDocumentResult` |
| `core/network/.../consent/KtorSiteConsentDocumentsApi.kt` | overview + acceptances adapter |
| `core/network/.../documents/KtorPublishedDocumentApi.kt` | body-read adapter |
| `app/.../documents/ConsentDocumentsScreen.kt` (+ `ConsentDocumentsUiState.kt`, `ConsentDocumentsViewModel.kt`) | overview + inline acceptances expander + internal `ConsentNav` |
| `app/.../documents/ConsentDocumentReaderScreen.kt` (+ `ConsentDocumentReaderUiState.kt`, `ConsentDocumentReaderViewModel.kt`) | reader |

**Slice I2 — new files + edits to slice I's files:**

| File | Change |
|---|---|
| `core/domain/.../consent/SiteConsentDocumentsApi.kt` | **edit** — add `publish(...)` + `ConsentPublishResult` (if not already declared in I) |
| `core/network/.../consent/KtorSiteConsentDocumentsApi.kt` | **edit** — add the `POST` publish path (200/409/`detail` mapping) |
| `app/.../documents/ConsentPublishEditorScreen.kt` (+ `ConsentPublishUiState.kt`, `ConsentPublishViewModel.kt`) | new — the editor |
| `app/.../documents/ConsentDocumentsScreen.kt` | **edit** — the «Опубликовать новую версию» action + `ConsentNav.Editor` wiring + reload-after-publish + success cue |

*Note on where `publish` is declared:* keeping the port free of a method no slice-I screen calls is the
cleaner "one promise" cut, so **I2 adds `publish` + `ConsentPublishResult` to the port and adapter**.
This is why I2 edits slice I's two `consent/*` files and must land after I.

**Shared files both slices touch — sequence them (rule 13, non-interference judged on files):**

| Shared file | Slice I | Slice I2 |
|---|---|---|
| `app/.../shell/MoreScreen.kt` | new `ADMINISTRATION_DOCUMENTS_ROW_ID` const + `buildMoreRows` entry (under `canConfigureSite`) + `when`-branch composing `ConsentDocumentsRoute` | **no change** — the editor is reached from inside the overview, not from Ещё |
| `app/src/main/res/values/strings.xml` (Russian, default) + `values-en/strings.xml` (English) | all `consent_*` read/overview/reader/acceptances keys, both locales | the `consent_publish_*` editor keys, both locales |
| `app/.../di/AppModule.kt` | two `@Provides` (both ports) | **no change** — `publish` rides the already-provided `SiteConsentDocumentsApi` |

**Sequencing:** **I → I2**, strictly. I2 edits I's port + adapter + overview screen, so it rebases onto
I. Only I touches `MoreScreen.kt` and `AppModule.kt`; both touch `strings.xml` (append-only, clearly
delimited). Because the wider tenant-admin bundle (channels, widget, etc.) also serialises on
`MoreScreen.kt`/`strings.xml`/`AppModule.kt`, **these PRs open one at a time** with the rest of that
initiative (rule 13).

*Note the locale layout:* the app's default `res/values/strings.xml` is **Russian**; `res/values-en/`
is the English override — the opposite of the `values{,-ru}` a reader might assume. Both slices add to
both files.

### 5.2 Done-when (each slice)

Builds; `dotnet`-side untouched; the app's four commands (typecheck / lint / test + `ux-gate` if a
fixture is touched — none here) pass; each adapter has a `Ktor…ApiTest` covering the mappings it owns —
**I:** overview parse, acceptance list parse + client-side version filter, body current-vs-version route
selection, `404 → NotFound`; **I2:** publish `200 → Published`, `409 → Conflict`,
problem-details `detail → Refused`; a `MoreScreen` row (I only) that appears only under `canConfigureSite`.

---

## 6. Decisions made (not re-asked)

1. **Publishing from the phone is in scope** — `tenant-management-android.md` §5 decision 2 resolved
   **(b) full**. This doc designs it (slice I2); the read-only alternative is closed.
2. **Two ports, not one** — the tenant-scoped surface and the anonymous body-read surface are separate
   ports (§2), because one carries site + credentials and the other must not, and the body port is what
   the future `…/policies/{key}` reader reuses.
3. **Body is read from the public surface**, not the overview — the overview is metadata-only by backend
   design; the reader calls `/api/v1/documents/{key}` (current) or `/versions/{version}` (specific).
4. **Acceptances stay per-version and client-filtered** — mirrors the console; no new backend endpoint.
5. **Subject id shown as an 8-char mono short code + long-press copy** — the phone-width adaptation of the
   console's full-GUID `<code>`; no information destroyed (§3.2).
6. **Editor is blank-start, publish is always a new version** — parity with the console; no edit-in-place,
   no draft pre-fill. A non-empty draft is guarded by a discard confirmation on back (§4.3).
7. **Body rendered as plain text** — the stored/served body is plain text; no Markdown rendering, matching
   how the widget presents it.

## 7. Blocking questions

**None.** The contract is unambiguous in the read sources (`SiteConsentDocumentEndpoints`,
`DocumentEndpoints`, `PublishedDocumentVersion`, `siteConsentDocumentsApi.ts`, `DocumentsPage.tsx`) and
every product call the console left implicit is settled above or already decided in
`tenant-management-android.md`. One thing recorded rather than asked: the `…/policies/{key}` deep-link
reader (`navigation.md`) is **not** built here, but `PublishedDocumentApi` + the reader composable are
shaped so it is a thin follow-up — flagged for its own item, deliberately not designed or cut in this
bundle.
