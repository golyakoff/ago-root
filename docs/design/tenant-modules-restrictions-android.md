# Модули / FAQ и Ограниченные посетители — Android tenant-admin design

Implementation-ready design for two related settings areas of the Android tenant-admin app:
**«Ограниченные посетители»** (visitor-restriction oversight) and **«Модули / FAQ»** (module status
and FAQ knowledge-base editing). These are slices **H** and **J** of
`docs/design/tenant-management-android.md`, brought to the per-screen depth of
`docs/design/tenant-channels-android.md`, whose structure and quality this doc matches. It is written
so a sonnet worker can build each slice with no design decisions left.

**Parity is decided, not re-questioned.** Everything the console does on these screens the app does.
The author confirmed full FAQ parity — the module panel *and* the knowledge base, not one or the
other. Nothing is cut. Where the backend or the console behaves differently than the parent doc's
one-line sketch assumed, this doc states the real contract (read from source) and designs to it.

## Four facts that change the parent doc's sketch (read from source, not assumed)

These were verified against `ago-chat`, `ago-faq`'s console client, and the live Android code. Each
changes what slice H or J must build, so each is stated up front rather than buried.

| # | Finding | Source | Consequence |
|---|---|---|---|
| 1 | **`GET/PUT /sites/{id}/modules` is GET-only for a tenant.** `adr/0151`/`23-83` removed *all* tenant writes (register, rotate, revoke, verify); only the read stays. Module registration is a platform-owner act, not tenant self-service. | `ago-chat` `ModuleEndpoints.cs` (maps `MapGet` only); `ago-console` `FaqModulePage.tsx` renders the module panel **read-only**. | The «Модули» panel is a **read**, not a form. The parent doc's slice-J phrase "register/update a module's trigger words and entry point" predates `adr/0151` — designing a tenant write here would contradict that ADR and would not be parity. |
| 2 | **The FAQ knowledge base is a *different backend* (`ago-faq` / `Ago.Faq.Api`), not `ago-chat`.** Its base URL is nullable — `ago-faq` has no production deployment yet, so the console tolerates `faqApiBaseUrl === null` and renders "not configured". | `ago-console` `faqKnowledgeBaseApi.ts` + `config.faqApiBaseUrl`. | The KB slice needs a **new nullable base URL** in the app (`AGO_FAQ_API_BASE_URL` → `OidcConfig.faqApiBaseUrl: String?`), and a "not configured" screen state — mirroring how `KtorBookingsApi`/`calendarApiBaseUrl` already handle an absent backend. |
| 3 | **«Ограниченные посетители» lives in the Диалоги app-bar overflow (⋮), gated `site:configure` — not in Ещё.** The overflow menu **does not exist in the app today**: `26-90` removed the old dot+kebab pair, leaving the conversation-list top bar with only the account avatar. | `ago-android/docs/navigation.md` (`ConvList -- "⋮ · site:configure" --> Restricted`); `scope-inventory.md` §68; `ConversationListScreen.kt` top-bar `actions` = avatar only. | The restrictions slice **introduces the overflow menu** on the conversation list, then hangs the one gated item in it. It is *not* a Ещё row. |
| 4 | **A `VisitorRestrictionApi` port already exists** (`26-145`, contact-detail panel: `block` / `lift` / `isRestricted`). Its `lift(visitorId)` is exactly what this screen needs. | `core/domain/.../restrictions/VisitorRestrictionApi.kt`; `AppModule.provideVisitorRestrictionApi`. | The restrictions slice **reuses `lift`** and only **adds a keyset `list()`** to the same port/adapter — no new DI binding, no second port for the same server resource. |

## Scope

| # | Screen | Console origin | Home in app | Gate (client / server) |
|---|---|---|---|---|
| 1 | **Ограниченные посетители** — keyset list + per-row lift | `RestrictedVisitorsPage` `/conversations/restricted` | Диалоги **app-bar overflow (⋮)** | `site:configure` list / `site:configure` read; lift `conversation:mark_spam`\|`conversation:block` |
| 2 | **Модули** — read-only enabled-module list | `FaqModulePage` module panel `/automation/faq` | Ещё → **Автоматизация** → «База знаний» | `site:configure` / `site:configure` |
| 3 | **База знаний (FAQ)** — read + edit knowledge-base text | `FaqModulePage` KB panel `/automation/faq` (`ago-faq` backend) | same screen as #2 (second panel) | `site:configure` / `site:configure` (on `ago-faq`) |

Screens 2 and 3 are two panels of **one** Android screen, exactly as the console renders two `<form>`s
on one page — each with its own load/save/error state, because they call two different backends and
saving one does not save the other.

*Principle (teaching mode): the client gate is UX only — hide-not-disable. The server's
`IPermissionChecker` is the real refusal. A row/menu-item an operator's permission does not cover is
not drawn at all (`buildMoreSections` / the overflow's own emptiness rule), never drawn-then-disabled.*

---

## 1. Ограниченные посетители

`RestrictedVisitorsPage`'s exact behaviour: a keyset-paged list of visitor restrictions (spam mutes and
indefinite blocks), each row showing who/when/until/status, with a per-row **lift** on the active ones.
A compliance/oversight screen an admin opens to check or to act — not a live queue, so **no auto-refresh
poll** (the console's own decision), only a manual refresh after a lift.

### 1.1 Contract

`VisitorRestrictionsEndpoints` (ago-chat), both `RequireOperatorIdentity`:

| Verb | Path | Query | Success | Server gate |
|---|---|---|---|---|
| `GET` | `/api/v1/visitor-restrictions` | `before: Guid?`, `limit: int?` | `200` → `VisitorRestrictionListResponse` | `site:configure` (`GetVisitorRestrictionsForSiteHandler`) — whole-site oversight read |
| `POST` | `/api/v1/visitor-restrictions/{visitorId}/lift` | — | `204` | `conversation:block` server-side (`LiftVisitorRestrictionHandler`); the console draws the button for `conversation:mark_spam`\|`conversation:block` |

`SiteId` is taken from the operator's own token claims (no `{siteId}` in the URL) — so the adapter
needs **no `ActiveSiteSelection`** for either call (matching the existing `provideVisitorRestrictionApi`
binding, which threads none).

`VisitorRestrictionListItemDto` (one `visitor_restrictions` row):

| Field | Wire type | Kotlin | Meaning |
|---|---|---|---|
| `id` | `Guid` | `String` | Row id — the keyset cursor and the list key. |
| `visitorId` | `Guid` | `String` | Which visitor. Rendered as the first 8 chars, mono (console `visitorId.slice(0,8)`). |
| `kind` | `string` | `String` (`"Spam"`\|`"Block"`) | `Spam` = time-windowed mute (accent tone); `Block` = indefinite block (danger tone). |
| `restrictedAt` | `DateTimeOffset` | `Instant` | When applied. |
| `restrictedBy` | `Guid` | `String` | Operator id who applied it — first 8 chars, mono. |
| `expiresAt` | `DateTimeOffset?` | `Instant?` | `null` = indefinite («Бессрочно»). |
| `sourceConversationId` | `Guid` | `String` | The conversation it was applied from. |
| `liftedAt` | `DateTimeOffset?` | `Instant?` | Non-null once lifted. |
| `liftedBy` | `Guid?` | `String?` | Who lifted it. |

`VisitorRestrictionListResponse` = `{ items: [...], nextBeforeId: Guid? }`. `nextBeforeId != null` means
another page exists; pass it back as `before` (keyset pagination, `docs/architecture/data-model.md`).

### 1.2 Port + adapter — extend the existing `VisitorRestrictionApi`

The `26-145` port already carries `lift(visitorId)` returning `VisitorRestrictionActionResult`
(`Succeeded` / `Refused(detail)` / `Failed(NetworkFailure)`). This slice **adds one read method** and
its result/row types to the *same* port and adapter — one port per server resource, the shape the
DI comment already asserts.

`core/domain/.../restrictions/VisitorRestrictionApi.kt` (append):

```
suspend fun list(before: String?, limit: Int?): VisitorRestrictionPageResult

sealed interface VisitorRestrictionPageResult {
    data class Loaded(val items: List<VisitorRestriction>, val nextBeforeId: String?) : …
    data class Failed(val reason: NetworkFailure) : …
}

data class VisitorRestriction(
    val id: String, val visitorId: String, val kind: RestrictionKind,
    val restrictedAt: Instant, val restrictedBy: String, val expiresAt: Instant?,
    val sourceConversationId: String, val liftedAt: Instant?, val liftedBy: String?)

enum class RestrictionKind { Spam, Block }   // parsed from the wire string; an unknown value → Block (fail safe: never under-report a restriction)
```

`core/network/.../restrictions/KtorVisitorRestrictionApi.kt` (append `list`): `GET` with
`before`/`limit` query params when non-null; parse a private `@Serializable` wire DTO (ISO-8601 →
`Instant`; a parse failure on a 2xx body is `Failed`, not an empty page — the `shapeGuard` lesson);
map non-2xx → `Failed(ServerError(status))`, `IOException` → `Failed(NoConnection)`, else
`Failed(Unexpected)` — the shared `NetworkFailure.from` discipline every other adapter uses.

*Principle: the read lives behind the same port as `lift` because both are the one `visitor-restrictions`
resource; a second port would split one server noun across two adapters for no gain. It stays in
`:core:domain`/`:core:network` because the dependency rule forbids a view model holding an `HttpClient`
— every wire decision (keyset cursor, kind parse, status→meaning) belongs on the far side of the port.*

### 1.3 UI state (`:app`)

`app/.../restrictions/RestrictedVisitorsUiState.kt`

```
sealed interface RestrictedVisitorsUiState {
    data object Loading
    data class Failed(reason: NetworkFailure)                        // retry
    data class Loaded(
        rows: List<RestrictionRow>,     // already display-shaped (status computed, see §1.6)
        nextBeforeId: String?,          // non-null → a "Загрузить ещё" affordance
        loadingMore: Boolean,
        liftingId: String?,             // the row whose lift is in flight (its button shows a spinner)
        liftError: String?)             // a Refused(detail) / rendered NetworkFailure, shown as a banner
}
data class RestrictionRow(domain: VisitorRestriction, status: RestrictionStatus)   // Active | Expired | Lifted
```

Empty is `Loaded(rows = emptyList())` → an empty-state body, never a spinner.

### 1.4 Screen states

`app/.../restrictions/RestrictedVisitorsScreen.kt` — a stateless composable + a `RestrictedVisitorsRoute`
that wires `hiltViewModel<RestrictedVisitorsViewModel>()`. Route/Screen split and **back arrow** in the
top bar (a drill-in reached from the conversation-list overflow — back returns to the list), the same
`InstallWidgetRoute`/`Screen` shape.

| State | What is shown |
|---|---|
| **Loading** | `LoadingBody()` |
| **Failed** | `RefusalBody(reason, onRetry)` — the shared read-failure body |
| **Empty** | empty-state body («Ограничений нет») |
| **Loaded** | a card/row per restriction (§1.5 layout); a top-bar **refresh** action; a «Загрузить ещё» row when `nextBeforeId != null` (or auto-load on scroll-end, dev's choice — the console uses an explicit button, so default to that); a `liftError` banner |
| **Lift confirm** | Material `AlertDialog` on the tapped row: body names the visitor short-code + kind; ghost «Отмена»; **danger** «Снять ограничение»; dismissed by system back (dialogs dismiss before the screen) |

Row layout (mirrors the console table columns, stacked for a phone): visitor short-code (mono) + a
**kind badge** (`Spam` = accent/brand tint, `Block` = danger tint); a status pill
(«Активно»/«Истекло»/«Снято»); `restrictedAt` (device-zone date-time); «Кем: {restrictedBy·8}»;
«До: {expiresAt·date}» or «Бессрочно»; and — **only on an active row, and only when the operator holds
`conversation:mark_spam`\|`conversation:block`** — a ghost **«Снять»** button. A lifted/expired row
shows no button, exactly as the console hides it.

After a successful lift the VM **reloads the list from the top** (`list(before=null)`) — one source of
truth reloaded, never an optimistic flip (the console's `load()`-after-mutation discipline).

Timestamps: UTC `Instant` in, **device-zone** label out, via a per-screen `DateTimeFormatter` (the app's
established per-screen pattern) — the project's date-and-time rule.

### 1.5 Entry point — the Диалоги overflow (new)

navigation.md places this screen behind the conversation list's **⋮** menu, gated `site:configure`. That
menu does not exist yet (finding #3), so the slice builds it:

- **`ConversationListScreen.kt`** — add, in the `TopAppBar` `actions` **before** `AccountAvatarAction`,
  an overflow: an `IconButton` (`Icons…MoreVert`) opening a `DropdownMenu` with one
  `DropdownMenuItem` «Ограниченные посетители». Draw the overflow **only when `canConfigureSite`** —
  an operator without it has no ⋮ at all (hide-not-disable, matching the console's shorter overflow).
  Mirror the existing `AnalyticsReportsOverflowMenu.kt` pattern.
- **`ConversationListRoute` / `ConversationListScreen`** — add `canConfigureSite: Boolean = false` and
  `onOpenRestricted: () -> Unit = {}` params, defaulted so every existing caller/test compiles
  unchanged (the same defaulting discipline `canSeeAllConversations` already uses).
- **`ConversationsTabHost.kt`** — add a **third state** beside list/thread: `openRestricted: Boolean`
  (`rememberSaveable`). When true, render `RestrictedVisitorsRoute(onBack = { openRestricted = false })`
  instead of the list; the list's `onOpenRestricted` sets it true. Thread `canConfigureSite` and
  `canLiftRestriction` (see below) in from `AppShellScreen`.
- **`AppShellScreen.kt`** — in the `conversationsTab` default, pass
  `canConfigureSite = permissions.holds(Permission.SITE_CONFIGURE)` (already computed there as
  `canSeeAllConversations`) and `canLiftRestriction = permissions.holds(Permission.CONVERSATION_BLOCK)
  || permissions.holds(Permission.CONVERSATION_MARK_SPAM)`.

*Principle: a new state in `ConversationsTabHost`, not a new NavHost destination, because that host is
already a hand-rolled list/thread swap (`26-16`) and adding a NavHost for one drill-in would be a second
navigation mechanism beside the one that exists. Back returns to the list for free (the host renders the
list when `openRestricted` is false), matching back-contract clause 2.*

### 1.6 Status computation and the clock note

Status is **display-only**, computed the way the console computes it: `liftedAt != null` → Lifted;
else `expiresAt != null && expiresAt <= now` → Expired; else Active. The `now` comes from the app's
injected `LocalClock`/`IClock`, **never** `System.now()` inline (the project's time rule; `DateTime`/
wall-clock reads are banned outside a clock port). This is a rendering decision, not an ordering one —
ordering is the server's keyset (`id`), never a clock.

---

## 2. Модули / FAQ

One screen, two independent panels — «Модули» (read-only, `ago-chat`) and «База знаний» (read/write,
`ago-faq`) — exactly as `FaqModulePage` renders two forms. Reached from Ещё → **Автоматизация** →
«База знаний» (navigation.md's own label for this row).

### 2.1 Модули panel — read-only enabled modules (`ago-chat`)

**Contract.** `ModuleEndpoints` (ago-chat), `RequireOperatorIdentity` + `site:configure`:

| Verb | Path | Response |
|---|---|---|
| `GET` | `/api/v1/sites/{siteId}/modules` | `EnabledModulesResponse { modules: [EnableModuleResponse] }` |

`EnableModuleResponse`:

| Field | Wire type | Kotlin | Meaning |
|---|---|---|---|
| `moduleKey` | `string` | `String` | e.g. `"faq"`. |
| `triggerWords` | `string[]` | `List<String>` | What a visitor types to start it. |
| `entryPoint` | `string` | `String` | The module's own service URL AGO Chat calls. |
| `grantedByOwner` | `bool` (default false) | `Boolean` | `true` when the platform owner enabled it, not the tenant. |
| `expiresAt` | `DateTimeOffset?` (default null) | `Instant?` | `null` = a grant that does not expire. |

There is **no write.** The console shows the `"faq"` module's status ("Enabled" + key + trigger words,
or "Not enabled — ask us"). The app renders the **full enabled-module list read-only** (a superset of
what the console surfaces, honest to the GET response), each module a card: key, trigger words, entry
point, a «Включено владельцем» badge when `grantedByOwner`, and «До {expiresAt·date}» when it expires.
An empty list → «Ни один модуль не подключён. AGO подключает их — напишите нам.» (the console's own copy).

**Port + adapter.** `core/domain/.../modules/ModulesApi.kt`:
```
interface ModulesApi { suspend fun fetch(): ModulesResult }     // Loaded(List<EnabledModule>) | Failed(NetworkFailure)
data class EnabledModule(moduleKey, triggerWords, entryPoint, grantedByOwner, expiresAt)
```
`core/network/.../modules/KtorModulesApi.kt`, constructor `(client, apiBaseUrl, activeSite)` — `{siteId}`
is in the URL, so `activeSite.currentSiteId()` is read directly (the `KtorInstallationApi` shape).
`GET …/sites/{siteId}/modules` → parse; non-2xx → `Failed(ServerError)`.

### 2.2 База знаний panel — read/write (`ago-faq`, separate backend)

**Contract.** `Ago.Faq.Api` (a *different* origin than `apiBaseUrl` — `ago-faq`, no `ago-chat`
knowledge of it), operator bearer token (same Keycloak token), `site:configure` on that server:

| Verb | Path | Body / response |
|---|---|---|
| `GET` | `{faqBaseUrl}/api/v1/sites/{siteId}/knowledge-base` | `{ text: string, updatedAt: string? }` |
| `PUT` | same | request `{ text }` → echoes `{ text, updatedAt }` |

**The new config.** `faqBaseUrl` is nullable — `ago-faq` may not be deployed. Add, mirroring
`calendarApiBaseUrl` exactly:

| File | Change |
|---|---|
| `app/build.gradle.kts` | `buildConfigField("String", "AGO_FAQ_API_BASE_URL", agoOptionalProperty("agoFaqApiBaseUrl"))` — nullable, **no default hostname** (never a guessed URL), the identical shape `AGO_CALENDAR_API_BASE_URL` uses |
| `OidcConfig.kt` | add `val faqApiBaseUrl: String?` — the `string \| null` shape the console's `config.faqApiBaseUrl` already carries |
| `AppModule.provideOidcConfig` | pass `faqApiBaseUrl = BuildConfig.AGO_FAQ_API_BASE_URL` |

**Port + adapter.** `core/domain/.../faq/FaqKnowledgeBaseApi.kt`:
```
interface FaqKnowledgeBaseApi {
    suspend fun fetch(): KnowledgeBaseResult          // Loaded(text, updatedAt) | NotConfigured | Failed(NetworkFailure)
    suspend fun update(text: String): KnowledgeBaseWriteResult   // Saved(text, updatedAt) | NotConfigured | Refused(detail) | Failed
}
```
`core/network/.../faq/KtorFaqKnowledgeBaseApi.kt`, constructor
`(client, faqApiBaseUrl: String?, activeSite)`. The adapter **always constructs** even when
`faqApiBaseUrl == null`; its first line checks the null and returns `NotConfigured` — the
`KtorBookingsApi`/`requireBaseUrl()` pattern (finding #2), never a nullable `FaqKnowledgeBaseApi` Hilt
must inject. `{siteId}` in the URL → read `activeSite.currentSiteId()`. `Refused(detail)` carries the
server's problem-details `detail` verbatim.

*The shared HttpClient's `X-Ago-Active-Site` header (added by `installAgoRestDefaults`) rides along to
`ago-faq` too. On the web the console deliberately omits it — a custom header triggers a CORS preflight
against `ago-faq`'s different CORS policy. **Android is not a browser: there is no CORS preflight**, so
the extra request header is harmless (an unknown header `ago-faq` ignores), and reusing the one shared
authenticated client is correct here. Stated because a reader who knows the console's reason would
otherwise expect a second client.*

### 2.3 Screen

`app/.../faq/ModulesFaqScreen.kt` (+ `ModulesFaqUiState.kt`, `ModulesFaqViewModel.kt`). One VM holding
**two independent sub-states** (`modules: …`, `kb: …`), one screen, back arrow, top-bar **refresh**
(re-fetch both — there is no page reload on a phone). Drill-in from `MoreScreen` via the existing
`openRowId` pattern (`onBack = { openRowId = null }`), like `InstallWidgetRoute`.

| Panel | States |
|---|---|
| **Модули** | Loading → `LoadingBody`; Failed → inline error + retry; Loaded → the read-only module cards (or the empty "ask us" note) |
| **База знаний** | If `faqApiBaseUrl == null` (or the port returns `NotConfigured`): an **info** `Alert` «Бэкенд AI-FAQ ещё не настроен для этого развёртывания», no editor. Else: Loading → `LoadingBody`; Loaded → a multi-line text field (rows≈10) seeded from `text`; a «Последнее сохранение {updatedAt·date-time}» / «Ещё не сохранялось» line; a primary **Сохранить** (→ «Сохранение…»); success `Alert` «Сохранено»; error `Alert` on `Refused`/`Failed`. On success, re-seed from the echoed response. |

The two panels never share a save button — saving one does not save the other (the console's own reason
for two `<form>`s). No client-side content validation on the KB text (the server is the authority; the
console does none either).

### 2.4 Nav & gating

- **`MoreScreen.kt`** — add `AUTOMATION_FAQ_ROW_ID` in the **Автоматизация** section, drawn **only under
  `canConfigureSite`** (the whole `/automation/faq` route is `site:configure` in the console rail); add
  a `when`-branch composing `ModulesFaqRoute(onBack = { openRowId = null })`. Row label «База знаний»
  (navigation.md's label; the screen header can be «Модули и база знаний»). A section with no rows is
  not drawn (`buildMoreSections`), so an operator without `site:configure` sees no Автоматизация header.
- Gate: `site:configure` on both backends — no rail-vs-server gap.

---

## 3. Cross-cutting: files, nav, DI, gating

### 3.1 Files each slice adds/touches

| Slice | New / independent files | Shared files (must be sequenced) |
|---|---|---|
| **R1 Restrictions** | `app/.../restrictions/RestrictedVisitors{Screen,UiState,ViewModel}.kt` (+ Route) | `core/domain/.../restrictions/VisitorRestrictionApi.kt` (append `list`+types); `core/network/.../restrictions/KtorVisitorRestrictionApi.kt` (append `list`); `app/.../conversations/ConversationListScreen.kt` (overflow); `app/.../shell/ConversationsTabHost.kt` (`openRestricted`); `app/.../shell/AppShellScreen.kt` (thread perms); `strings.xml` ×2 |
| **M1 Модули (read-only)** | `core/domain/.../modules/ModulesApi.kt`; `core/network/.../modules/KtorModulesApi.kt`; `app/.../faq/ModulesFaq{Screen,UiState,ViewModel}.kt` (+ Route) | `app/.../shell/MoreScreen.kt` (row + when-branch); `app/.../di/AppModule.kt` (`provideModulesApi`); `strings.xml` ×2 |
| **M2 База знаний (FAQ KB)** | `core/domain/.../faq/FaqKnowledgeBaseApi.kt`; `core/network/.../faq/KtorFaqKnowledgeBaseApi.kt` | `app/build.gradle.kts` + `OidcConfig.kt` + `AppModule.kt` (`AGO_FAQ_API_BASE_URL` + `provideFaqKnowledgeBaseApi`); `app/.../faq/ModulesFaqScreen.kt` + `…ViewModel.kt` + `…UiState.kt` (add the KB panel — **M1's files**); `strings.xml` ×2 |

**M2 depends on M1** (it adds the KB panel to M1's `ModulesFaq*` files). R1 is independent of M1/M2 but
shares `strings.xml`/`AppShellScreen.kt` conventions — so **all three open PRs one at a time** (rule 13,
non-interference judged on files). Keep each slice's additions to shared files append-only and delimited.

### 3.2 DI

| Port | Binding | Notes |
|---|---|---|
| `ModulesApi` | `provideModulesApi(client, config, activeSite)` → `KtorModulesApi(client, config.apiBaseUrl, activeSite)` | `{siteId}` in URL → needs `activeSite`, like `provideInstallationApi` |
| `FaqKnowledgeBaseApi` | `provideFaqKnowledgeBaseApi(client, config, activeSite)` → `KtorFaqKnowledgeBaseApi(client, config.faqApiBaseUrl, activeSite)` | always constructs; nullable base URL answered inside the adapter, like `provideBookingsApi` |
| `VisitorRestrictionApi` | **no change** — `provideVisitorRestrictionApi` already binds it; the added `list` rides the existing binding | site-scoped by token, no `activeSite` |

### 3.3 Gating summary

| Surface | Gate |
|---|---|
| Диалоги overflow ⋮ item «Ограниченные посетители» | drawn only when `canConfigureSite` |
| Restrictions list load | `site:configure` (server) |
| Per-row «Снять» button | drawn only when `conversation:mark_spam`\|`conversation:block`, and only on active rows |
| Ещё → Автоматизация → «База знаний» row | drawn only when `canConfigureSite` |
| Both panels' loads/saves | `site:configure` (server, on `ago-chat` and `ago-faq` respectively) |

### 3.4 Edge cases

| Case | Handling |
|---|---|
| `site:configure` holder lacking `conversation:block`/`mark_spam` | Sees the list (site:configure) but no «Снять» buttons — hide-not-disable, console parity. |
| Lift refused (`Conversation.Forbidden` / `Visitor.NotRestricted`) | `Refused(detail)` shown verbatim in a banner; list reloaded so an already-lifted/expired row drops its button. |
| Restriction expired but never lifted (Spam window closed) | Status renders «Истекло» from the client clock; no lift button (not active). The server's own `IsActiveAsync` excludes it too. |
| Keyset list — restriction pushed off page one | «Загрузить ещё» follows `nextBeforeId`; a `Block` (indefinite) row is never lost because paging continues to the end. |
| `ago-faq` not deployed (`faqApiBaseUrl == null`) | KB panel shows the "not configured" info alert; the Модули panel is unaffected (different backend). |
| Module list empty | «Ни один модуль не подключён — напишите нам» (console copy); never an error. |
| KB text accepted client-side but refused server-side | `Refused(detail)` shown verbatim; no client content validation claims success. |
| Back inside a screen | Restrictions → back returns to the conversation list (`openRestricted=false`); Модули/FAQ → back returns to the Ещё list (`openRowId=null`); a dialog dismisses first. |

---

## 4. Implementation-ready slice specs

Each is one promise that lands green (rule 15). Sizes: S ≈ ½ day, M ≈ 1 day. Backend-needed = **No**,
migration-lane = **No** for all three (Android client only, against existing endpoints; the FAQ base
URL is a build config, not a schema change).

| # | Title | Promise (one thing, lands green) | Size | Depends on |
|---|---|---|---|---|
| **R1** | Android: Ограниченные посетители — keyset list + lift, from the Диалоги overflow | A `site:configure` operator opens Диалоги → ⋮ → «Ограниченные посетители», sees the keyset-paged restriction list (kind/who/when/status), loads more, and — holding `conversation:block`\|`mark_spam` — lifts an active restriction, which reloads the list. | **M** | — |
| **M1** | Android: Модули — read-only enabled-module list | A `site:configure` operator opens Ещё → Автоматизация → «База знаний» and sees the site's enabled modules read-only (key, trigger words, entry point, owner/expiry), or the "ask us" empty note. | **S** | — (serialises on shared files) |
| **M2** | Android: База знаний (FAQ) — read/edit the knowledge base | On the same screen, when `ago-faq` is configured, the operator reads and edits the knowledge-base text and saves it (echo re-seeds state); when it is not configured, a "not configured" notice shows instead. | **M** | M1 |

Each slice's Done-when: builds; `dotnet`-side unchanged; the app's four commands
(typecheck/lint/test + `ux-gate` if a fixture is touched — none here) pass; the adapter has a
`Ktor…ApiTest` (R1: list keyset parse + lift refusal→`Refused`; M1: module list parse; M2: KB
round-trip + the `NotConfigured` branch when the base URL is null); the gated row/menu-item appears
only under its permission.

---

## 5. Notes and flags (no blocking questions)

Everything needed to build is settled above; the contracts are unambiguous in the read sources. Three
things to record rather than ask:

1. **Module "registration" is inherently read-only (finding #1), and this is parity, not a cut.**
   `adr/0151` removed every tenant module write; the console's module panel is a status read. The app
   mirrors that. If the author ever wants tenant-side module registration, that is a new `ago-chat`
   endpoint + an `adr/0151` reversal — a separate initiative, not this slice, and not a thing to invent
   client-side against an endpoint that returns 405.

2. **`ago-faq` has no production deployment (finding #2).** M2 ships behind the "not configured" state
   by default; the KB editor only comes alive once `agoFaqApiBaseUrl` is set for a build. This is the
   honest current state, identical to how the calendar API was handled before it was deployed.

3. **The restrictions slice grows the conversation-list top bar (finding #3).** It adds the ⋮ overflow
   that `26-90` removed. If a future slice adds conversation **search** (navigation.md's «лупа», also
   not built yet) it will add a second top-bar action beside this overflow — noted so the two are not
   designed to collide, but search is out of this bundle's scope.
