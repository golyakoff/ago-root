# Готовые ответы (canned responses) + Метки (tags) — Android tenant-admin design

Implementation-ready design for two small **Автоматизация** settings screens on the Android
tenant-admin app: the canned-response library and the tag vocabulary. Part of the console→app parity
initiative (`docs/design/briefs/tenant.md`, `ago-android/docs/scope-inventory.md` §8,
`docs/navigation.md` §Ещё). Same structure and quality bar as `docs/design/tenant-channels-android.md`;
written so a sonnet worker builds each slice with no design decisions left.

**Parity is decided, not re-questioned.** Everything the console does on these screens the app does.
Both are `site:configure`-gated management surfaces; whole-list PUT (canned) and per-row CRUD (tags)
round-trip the full server shape. Nothing is cut.

## Scope

| # | Screen | Console origin | Gate (rail / server) | Ещё section |
|---|---|---|---|---|
| 1 | **Готовые ответы** — canned-response library | `CannedResponsesPage` `/automation/canned` | `site:configure` / `site:configure` | Автоматизация |
| 2 | **Метки** — tag vocabulary CRUD | `TagsPage` `/automation/tags` | `site:configure` / see §2 | Автоматизация |

Both rows are drawn only for a `site:configure` holder — `MoreScreen` already receives
`canConfigureSite: Boolean` (`26-159`) and draws Автоматизация rows. This mirrors `consoleNav.ts`'s own
`buildAutomationItems`, which gates both entries on `site:configure` (the `isAdmin` proxy).

*Principle (teaching mode): the client gate is UX only — hide-not-disable. `IPermissionChecker` on the
server is the real refusal, so an operator who reaches the route another way still gets an honest server
`403`, surfaced as text, never a form that silently does nothing — the exact posture
`CannedResponsesPage`/`TagsPage` document for themselves.*

---

## 1. Готовые ответы (canned responses)

A per-site library of prepared answers an operator inserts into the composer (the composer's `/` picker
reads it). A short **title** to browse by and a **body** inserted verbatim; nothing here is matched
against a visitor's message (unlike an auto-reply keyword) — `CannedResponse`'s own doc comment
(`ago-chat`).

### 1.1 Contract

`CannedResponseEndpoints` (ago-chat), route policy `RequireOperatorIdentity`, Application-level
`site:configure` on both verbs:

| Verb | Path | Body | Response |
|---|---|---|---|
| `GET` | `/api/v1/sites/{siteId}/canned-responses` | — | `{"responses":[{title,body}]}` |
| `PUT` | `/api/v1/sites/{siteId}/canned-responses` | `{"responses":[{title,body}]}` | echoes `{"responses":[…]}` |

**Whole-list PUT.** `UpdateCannedResponsesHandler` replaces the *entire* per-site set in one call — the
list is a JSON blob column on `Site`, read and written as a whole, never a row per entry
(`CannedResponse`'s own doc comment contrasts this with `Tag`, which is a real table). There is **no id**
on a response: a canned response is identified only by its position in the list.

Domain bounds (mirror `Ago.Chat.Domain.CannedResponse` = `cannedResponsesValidation.ts`):
`MaxCount = 50`, `MaxTitleLength = 100`, `MaxBodyLength = 8000` (`MessageBody.MaxLength`). Title is
trimmed (client and server); body is stored as typed (not trimmed — it becomes a message body).

Error code: `CannedResponse.Invalid` (empty/oversized title or body), plus `Conversation.Forbidden`
(the shared 403 code) — RFC 7807 `detail` carried verbatim.

### 1.2 Domain port (`:core:domain`)

`core/domain/src/main/kotlin/ago/chat/android/core/domain/cannedresponses/CannedResponsesApi.kt`

```
interface CannedResponsesApi {
    suspend fun fetch(): CannedResponsesResult                                  // Loaded | Failed
    suspend fun save(responses: List<CannedResponse>): CannedResponsesWriteResult  // Saved | Refused | Failed
}

data class CannedResponse(val title: String, val body: String)   // no id — position is identity
```

Result types (same package, reusing `core.domain.net.NetworkFailure`, `26-59`):

| Type | Arms | Notes |
|---|---|---|
| `CannedResponsesResult` | `Loaded(responses: List<CannedResponse>)` \| `Failed(NetworkFailure)` | An empty list is a *loaded* empty library, not a failure. |
| `CannedResponsesWriteResult` | `Saved(responses: List<CannedResponse>)` \| `Refused(detail: String)` \| `Failed(NetworkFailure)` | `Saved` carries the **echoed** server list — the VM re-seeds from it, never from the request. `Refused` carries the server's problem-details `detail` (`CannedResponse.Invalid` text) verbatim. |

*Principle: the port lives in `:core:domain` because the dependency rule forbids a view model holding an
`HttpClient`; every HTTP-shaped decision (status→meaning, the `{siteId}` URL, request/echo mapping)
belongs on the far side of it, in `:core:network` — the split `InstallationApi`/`ConversationTagsApi`
already establish. `CannedResponse` is a plain domain data class, not the wire DTO: the adapter maps
between them so a `200` whose body is the wrong shape becomes `Failed`, never a half-parsed library
(`shapeGuard` lesson).*

### 1.3 Adapter (`:core:network`)

`core/network/src/main/kotlin/ago/chat/android/core/network/cannedresponses/KtorCannedResponsesApi.kt`

Constructor `(client: HttpClient, apiBaseUrl: String, activeSite: ActiveSiteSelection)` — the exact shape
`KtorConversationTagsApi` uses for its own `{siteId}`-in-URL read. `activeSite.currentSiteId()` is read
directly (the id is in the path, not only the `X-Ago-Active-Site` header); a `null` site id is `Failed`.

Base path: `"$apiBaseUrl/api/v1/sites/$siteId/canned-responses"`.

| Verb | 2xx | Non-2xx → | Exception → |
|---|---|---|---|
| `GET` | 200 → `Loaded` (parse `CannedResponsesWireDto`, map each item to `CannedResponse`) | `Failed(ServerError(status))` — screen reachable only for a `site:configure` holder, so "couldn't load, retry" is honest | `IOException → Failed(NoConnection)`, else `Failed(Unexpected)` |
| `PUT` body `{"responses":[…]}` | 200 → `Saved(echoed list)` | read problem-details `detail` → `Refused(detail)`; no parseable body → `Failed(ServerError(status))` | as above |

Private `@Serializable` wire DTOs, never crossing the port:

```
@Serializable private data class CannedResponseItemWireDto(val title: String, val body: String)
@Serializable private data class CannedResponsesWireDto(val responses: List<CannedResponseItemWireDto>)
@Serializable private data class ProblemDetailsWireDto(val detail: String? = null)
```

The `PUT` request body is `CannedResponsesWireDto(responses.map { it.toWire() })` — the **whole list**,
always, every save. A parse failure on an otherwise-2xx echo is `Failed`, not a silent empty library.

### 1.4 UI state (`:app`)

`app/src/main/kotlin/ago/chat/android/automation/CannedResponsesUiState.kt`

```
sealed interface CannedResponsesUiState {
    data object Loading
    data class Failed(reason: NetworkFailure)                                  // retry
    data class Loaded(
        responses: List<CannedResponse>,     // the whole in-memory library (the PUT payload)
        saving: Boolean,                      // a whole-list PUT is in flight
        saved: Boolean,                       // transient «Сохранено» confirmation
        error: String?)                       // Refused(detail) text or a rendered NetworkFailure
}
```

The editor is **not** a UiState arm — which entry is open (a new one, or an index) is transient
composition state held in the screen with `remember`, the identical discipline `WorkingHoursScreen`
(`26-97`) uses for its own edit dialog: "a property of this composition, not a fact the view model or a
process-death restore has any business carrying."

### 1.5 Screen (list + FAB + editor)

`app/src/main/kotlin/ago/chat/android/automation/CannedResponsesScreen.kt`
(+ `CannedResponsesRoute`, `CannedResponsesViewModel.kt`). Route/Screen split exactly like
`InstallWidgetRoute`/`Screen`: back arrow in the top bar (a drill-in from Ещё, not a top-level
destination), no `AccountAvatarAction`. Shared read-state bodies come from the `bookings` package
(`LoadingBody`, `RefusalBody`, `EmptyBody`, `ActionErrorBanner`) — imported the way `WorkingHoursScreen`
already imports them, not re-inlined.

**The desktop "one blank trailing row to type into" idiom is dropped** — it fails on a soft keyboard
(`scope-inventory.md` §8). Instead: a list of saved responses, a **FAB** to add, and each response
**edited on its own editor screen**. This is the app's *first* `FloatingActionButton` (none exists
today); use M3 `Scaffold`'s `floatingActionButton` slot directly — two call sites (here and Метки) do
not yet justify a shared `AgoFab` wrapper (premature-generalisation rule).

| State | Trigger | What is shown |
|---|---|---|
| **Loading** | initial / retry | `LoadingBody()` |
| **Failed** | load failed | `RefusalBody(reason, onRetry, …)` |
| **Loaded · empty** | `responses.isEmpty()` | `EmptyBody` («Пока нет готовых ответов. Добавьте первый.»); FAB present |
| **Loaded · list** | `responses` non-empty | one card/row per response: title (bold, ellipsised) + a one-line body preview; tapping a row opens the editor for that index; a trailing overflow or a swipe/`Удалить` affordance opens the delete confirm; a FAB («＋», `i-plus`) opens the editor for a new entry; `ActionErrorBanner` on `error`; a transient «Сохранено» on `saved` |
| **Editor** | FAB or row tap | full-screen sub-composable: a **title** `OutlinedTextField` (single line, `MaxTitleLength` counter) and a **body** `OutlinedTextField` (multi-line, `MaxBodyLength` counter); a primary **Сохранить** (disabled while title/body blank or `saving`; → «Сохранение…»); back arrow / system back returns to the list without saving. |
| **Delete confirm** | Удалить tapped | Material `AlertDialog`: body «Удалить готовый ответ «{title}»?»; ghost «Отмена»; **danger** «Удалить». |

**The whole-list PUT trap (the load-bearing behaviour).** There is no per-item endpoint. Every
mutation — add, edit, delete — is a **client-side edit of the in-memory list followed by one PUT of the
entire list**:

- **Add**: editor returns a new `CannedResponse`; VM appends it and PUTs the whole list.
- **Edit**: editor returns the edited `CannedResponse`; VM replaces the item *at that index* and PUTs the
  whole list.
- **Delete**: VM removes the item at that index and PUTs the whole list.
- **On any success** the VM re-seeds `responses` from the **echoed** `Saved` list — one source of truth,
  reloaded, never an optimistic in-place flip (the console's own `setResponses([...dtos])`-after-mutation
  discipline). On `Refused`/`Failed` the in-memory list is left unchanged and the error surfaces; the
  editor stays open so the operator can retry or back out.

Order is preserved because the operator arranged it (append-to-end for a new entry), **not** because it
is behaviour — nothing matches against this list (`toRequestResponses`'s own remark). No reorder handle
is offered (unlike Автоответ вне смены, where order *is* first-match-wins).

**Client-side courtesy validation** before the PUT (mirror `validateDraft`, first problem wins):
title non-blank and ≤100; body non-blank and ≤8000; ≤50 responses total. The server
(`UpdateCannedResponsesHandler`) is the authoritative gate — a miss comes back `CannedResponse.Invalid`
and its `detail` is shown verbatim.

### 1.6 View model

`app/src/main/kotlin/ago/chat/android/automation/CannedResponsesViewModel.kt`, `@HiltViewModel`,
`(api: CannedResponsesApi, @IoDispatcher d)`, `init { refresh() }`. `refresh()` → `fetch()` →
`Loading`→`Loaded`/`Failed`. `save(nextList)` sets `saving=true`, PUTs, and on `Saved` re-seeds from the
echo with `saved=true`; on `Refused`/`Failed` sets `error`. `addOrReplace(index?, response)` and
`delete(index)` compute the next list and call `save`. All IO on `ioDispatcher`, every call takes the
scope's job — the `InstallWidgetViewModel` shape.

---

## 2. Метки (tags)

The site's own tag vocabulary — labels an operator attaches to conversations to find or count them
later. **Labels only**: nothing here carries meaning to automation (routing, SLAs) — `Tag`'s own doc
comment. Managing the vocabulary is this screen; *applying* a tag to a conversation happens in the
visitor sheet's tag sheet, which **already exists** (`ConversationTagsApi`, `26-115`) — see §2.5.

### 2.1 Contract

`TagEndpoints` (ago-chat), route policy `RequireOperatorIdentity`. **The permission split is the one
subtlety here** and it is deliberate (`Permission.ConversationTag`'s own remarks):

| Verb | Path | Body | Response | Server gate |
|---|---|---|---|---|
| `GET` | `/api/v1/sites/{siteId}/tags` | — | `{"tags":[{id,name,createdAt}]}` | `conversation:read` (`ListTagsHandler`) |
| `POST` | `/api/v1/sites/{siteId}/tags` | `{"name"}` | `{id,name,createdAt}` | `site:configure` (`CreateTagHandler`) |
| `PUT` | `/api/v1/sites/{siteId}/tags/{tagId}` | `{"name"}` | `{id,name,createdAt}` | `site:configure` (`RenameTagHandler`) |
| `DELETE` | `/api/v1/sites/{siteId}/tags/{tagId}` | — | `204` | `site:configure` (`DeleteTagHandler`) |

So **reading** the vocabulary is open to any operator who can see conversations, while **managing** it
is `site:configure`. The management screen's Ещё row is drawn only under `canConfigureSite` (§2.4), so a
read-only operator never reaches it — they use tags through the conversation sheet instead. This matches
the console: `TagsPage` is `site:configure`-gated, while the conversation panel's own tag picker reads
the same `GET` under `conversation:read`.

Domain bound: `Tag.MaxNameLength = 60` (trimmed). Error codes (RFC 7807 `type`, `detail` shown verbatim):
`Tag.Invalid` (empty/oversized), `Tag.AlreadyExists` (case-insensitive duplicate for this site),
`Tag.NotFound`, `Conversation.Forbidden`.

**Delete cascades.** `DeleteTagHandler` + the schema's own `conversation_tags` FK cascade
(`ReferentialAction.Cascade`, Stage-1 migration) means deleting a tag removes it from **every
conversation that carried it** — the join is by `TagId`, so re-creating a tag of the same name does *not*
restore the old associations. The delete confirm copy must say this (§2.3).

### 2.2 Domain port (`:core:domain`)

`core/domain/src/main/kotlin/ago/chat/android/core/domain/tags/SiteTagsApi.kt`

```
interface SiteTagsApi {
    suspend fun fetch(): TagVocabularyResult                       // Loaded(List<Tag>) | Failed   (reused)
    suspend fun create(name: String): TagMutationResult            // Saved(tag) | Refused | Failed
    suspend fun rename(tagId: String, name: String): TagMutationResult
    suspend fun delete(tagId: String): TagDeleteResult             // Deleted | Refused | Failed
}
```

- **Reuse** the existing `Tag` domain type and `TagVocabularyResult` (`Loaded`/`Failed`) from
  `core.domain.tags` (`26-115`) — the `GET` shape is identical, so re-declaring them would be
  duplication.
- New: `TagMutationResult` = `Saved(tag: Tag)` \| `Refused(detail: String)` \| `Failed(NetworkFailure)`;
  `TagDeleteResult` = `Deleted` \| `Refused(detail: String)` \| `Failed(NetworkFailure)`.

*Principle: a **new** port rather than fattening `ConversationTagsApi`. That port is the conversation
panel's (`26-115`): it reads the vocabulary and applies/removes a tag on one conversation, and its own
doc comment states outright that "creating, renaming or deleting a vocabulary entry is site
configuration, not this panel's job — out of scope here." Adding `create`/`rename`/`delete` to it would
give the conversation panel's port three methods it never calls, and blur its narrower `conversation:tag`
mental model with a `site:configure` one. The alternative — one fat `TagsApi` for both consumers — was
rejected for that reason; two thin ports over the same `GET` is the same "port per consumer" shape the
channels doc chose, and both reuse the one `Tag` domain type so nothing is duplicated but the read
method's signature.*

### 2.3 Adapter (`:core:network`)

`core/network/src/main/kotlin/ago/chat/android/core/network/tags/KtorSiteTagsApi.kt`

Constructor `(client, apiBaseUrl, activeSite)` — the exact `KtorConversationTagsApi` shape;
`activeSite.currentSiteId()` supplies the `{siteId}` for all four calls; a `null` id is `Failed`.

| Verb | Path | 2xx | Non-2xx → | Exception → |
|---|---|---|---|---|
| `GET` | `…/tags` | 200 → `Loaded` (parse `TagsResponseWireDto`) | `Failed(ServerError)` | `Failed(NetworkFailure.from)` |
| `POST` | `…/tags` body `{"name"}` | 200 → `Saved(tag)` | `Refused(detail)` / `Failed(ServerError)` | as above |
| `PUT` | `…/tags/{tagId}` body `{"name"}` | 200 → `Saved(tag)` | `Refused(detail)` / `Failed(ServerError)` | as above |
| `DELETE` | `…/tags/{tagId}` | 204 → `Deleted` | `Refused(detail)` / `Failed(ServerError)` | as above |

Private `@Serializable` DTOs: reuse the field-for-field `TagWireDto`/`TagsResponseWireDto`/
`ProblemDetailsWireDto` shapes `KtorConversationTagsApi` already declares (each adapter keeps its own
`private` copy — this codebase's deliberate "un-shared wire DTO" convention, so a second private copy in
this file is correct, not duplication to eliminate). Request body: `@Serializable data class
TagNameRequestWireDto(val name: String)`.

### 2.4 UI state, screen, view model (`:app`)

`app/src/main/kotlin/ago/chat/android/automation/Tags{Screen,UiState,ViewModel}.kt`. Route/Screen split,
back arrow, no avatar action — the drill-in shape again.

```
sealed interface TagsUiState {
    data object Loading
    data class Failed(reason: NetworkFailure)                    // retry
    data class Loaded(
        tags: List<Tag>,
        busy: Boolean,                 // a create/rename/delete round-trip is in flight
        error: String?)                // Refused(detail) or rendered NetworkFailure
}
```

List + FAB + **dialog** editor (not a full editor screen — a tag is a single short name, so a create/
rename dialog is the right weight, matching `TagsPage`'s own in-place rename and `WorkingHoursScreen`'s
dialog precedent):

| State | What is shown |
|---|---|
| **Loading / Failed** | `LoadingBody()` / `RefusalBody(onRetry=refresh)` |
| **Loaded · empty** | `EmptyBody` («Пока нет меток. Добавьте первую.»); FAB present |
| **Loaded · list** | one row per tag: name + (optional) created-date; a per-row **Изменить** / **Удалить** pair (the console's own row actions) or an overflow; a FAB («＋») opens the create dialog; `ActionErrorBanner` on `error` |
| **Create / Rename dialog** | Material `AlertDialog` with one name `OutlinedTextField` (seeded with the tag name when renaming, empty when creating; `MaxNameLength` counter); primary **Сохранить** (disabled while blank or `busy`); ghost «Отмена». A `Tag.AlreadyExists` refusal renders inside the dialog and keeps it open. |
| **Delete confirm** | `AlertDialog`: body «Удалить метку «{name}»? Она исчезнет со всех диалогов, где была проставлена, — это не отменить.» (states the cascade, §2.1); ghost «Отмена»; **danger** «Удалить». |

Which dialog is open (create / rename-of-id / confirm-delete-of-id) is transient composition state via
`remember`, not a UiState arm — the `WorkingHoursScreen` discipline again.

**Per-row CRUD, each followed by a re-fetch** (unlike canned's whole-list PUT): `create(name)`,
`rename(id, name)`, `delete(id)` each mutate one server row, then the VM `refresh()`es the list — the
console's own `load()`-after-mutation rule. No optimistic list edit; the server is the source of truth,
and a rename that the server refuses (`Tag.AlreadyExists`) must not appear applied. Client courtesy check
before a write: name non-blank and ≤60; `Tag.Invalid`/`Tag.AlreadyExists` are the authoritative server
answers, shown verbatim.

`TagsViewModel` `@HiltViewModel (api: SiteTagsApi, @IoDispatcher d)`, `init { refresh() }`; each mutation
sets `busy=true`, awaits the result, and on success `refresh()`es; on `Refused`/`Failed` sets `error`.

### 2.5 Relationship to the existing conversation tag sheet

The thread's **Шторка меток** (apply/remove a tag on one conversation) already exists —
`ConversationTagsApi` + `KtorConversationTagsApi` (`26-115`), reached from the visitor sheet
(`navigation.md` §Диалоги: `Sheet -- "+ метка" --> TagSheet`). That surface reads the same
`GET /sites/{siteId}/tags` vocabulary and writes per-conversation associations under `conversation:tag`.
This Метки screen is the **other half**: it manages the vocabulary itself under `site:configure`. The
two are deliberately separate ports and separate screens, exactly as the console splits `TagsPage` (the
vocabulary) from `ConversationTagsPanel` (applying it). A tag created here appears in the sheet's picker;
a tag deleted here vanishes from every conversation and from the picker.

---

## 3. Cross-cutting: files, nav, DI, gating

### 3.1 Files each slice adds

Independent (no cross-slice conflict):

| Slice | New files |
|---|---|
| **T1 Canned** | `core/domain/…/cannedresponses/CannedResponsesApi.kt` (+ types); `core/network/…/cannedresponses/KtorCannedResponsesApi.kt`; `app/…/automation/CannedResponses{Screen,UiState,ViewModel}.kt` |
| **T2 Tags** | `core/domain/…/tags/SiteTagsApi.kt` (+ `TagMutationResult`/`TagDeleteResult`); `core/network/…/tags/KtorSiteTagsApi.kt`; `app/…/automation/Tags{Screen,UiState,ViewModel}.kt` |

**Shared files both slices touch — must be sequenced (rule 13, non-interference judged on files):**

| Shared file | T1 Canned | T2 Tags |
|---|---|---|
| `app/…/shell/MoreScreen.kt` | **repoint** the existing `AUTOMATION_QUICK_REPLIES_ROW_ID` placeholder branch to `CannedResponsesRoute(onBack = { openRowId = null })` **and move that row under `canConfigureSite`** (it is drawn unconditionally today; the console gates it on `site:configure`) | **add** a new `AUTOMATION_TAGS_ROW_ID` const + a `buildMoreRows` entry (under `canConfigureSite`, Автоматизация section) + a `when`-branch composing `TagsRoute` |
| `app/src/main/res/values{,-ru}/strings.xml` | `canned_responses_*` keys, both locales | `tags_*` keys, both locales |
| `app/…/di/AppModule.kt` | `@Provides provideCannedResponsesApi` `(client, config, activeSite)` — the `provideConversationTagsApi` shape | `@Provides provideSiteTagsApi` `(client, config, activeSite)` |

`MoreScreen.kt`, both `strings.xml` and `AppModule.kt` collisions are why these two slices open PRs **one
at a time** and cannot be two parallel lanes on the same files. Keep each slice's additions append-only
and clearly delimited to minimise rebase pain.

**Note on `AUTOMATION_QUICK_REPLIES_ROW_ID`.** It already exists in `MoreScreen.kt` (`26-77`) as a
placeholder opening `PlaceholderDestinationScreen` with label `more_automation_quick_replies_row`. T1
**reuses the constant**, repoints its branch, and can rename the label string to
`canned_responses_title` (or keep the existing key). **No new row constant for canned.** Метки has no
existing row → T2 adds one.

### 3.2 Автоматизация section row order (per `navigation.md` §Ещё)
`Готовые ответы` · `ИИ-подсказки` · `Автоответ вне смены` · `База знаний` · `Метки`. T1 repoints the
first; T2 adds Метки last. (ИИ-подсказки, База знаний, and Автоответ вне смены are other items — the
after-hours row already exists; this bundle adds only the two named screens.)

### 3.3 Gating summary
Both rows gate on `Permission.SITE_CONFIGURE` via `MoreScreen`'s existing `canConfigureSite` boolean
(computed once in `AppShellContent` from `OperatorPermissions.Known`). A section with no visible rows is
not drawn (`buildMoreSections`). Canned is `site:configure` on both verbs — no rail-vs-server gap. Tags'
`GET` is `conversation:read` server-side, but the management screen is only *reached* under
`site:configure`, and its writes are `site:configure` — so a reader never sees the row, exactly as the
console hides the nav entry.

### 3.4 Edge cases

| Case | Handling |
|---|---|
| Canned: two operators edit concurrently | Whole-list PUT is last-write-wins — the second save clobbers the first, the console's own property (no ETag/version on this blob). Not introduced here; re-seeding from the echo means the surviving operator at least sees the true saved state. |
| Canned: soft-keyboard trailing-blank-row idiom | Dropped — replaced by list + FAB + editor screen (`scope-inventory.md` §8). |
| Canned: edit one, save whole | Always PUT the full in-memory list; re-seed from the echo. No per-item endpoint exists. |
| Canned: `CannedResponse.Invalid` from server | `Refused(detail)` shown verbatim; the editor stays open. |
| Canned/Tags: empty library / empty vocabulary | A *loaded* empty state with `EmptyBody` + FAB — a valid, expected state, not a failure. |
| Tags: duplicate name | `Tag.AlreadyExists` → `Refused(detail)` rendered **inside the create/rename dialog**, dialog stays open (case-insensitive, server-authoritative). |
| Tags: rename keeps associations | Server renames in place, every `conversation_tags` row by `TagId` survives — no client action needed; re-fetch shows the new name. |
| Tags: delete cascades | Confirm copy states the label vanishes from every conversation that carried it and is not restorable by re-creating the name. |
| Tags: `Tag.NotFound` on rename/delete | Another operator deleted it first → `Refused(detail)`; the next `refresh()` drops the stale row. |
| Back inside a screen/editor/dialog | A dialog/confirm dismisses first (back-contract); the editor's back returns to the list; the list's back returns to the Ещё list (`openRowId=null`). A non-empty editor draft is transient and not persisted — acceptable for a short one-shot input (unlike a composer draft). |

---

## 4. Implementation-ready slice specs

Each is one promise that lands green (rule 15). Sizes: S ≈ ½ day, M ≈ 1 day, L ≈ 1½–2 days.

| # | Title | Promise (one thing, lands green) | Size | Depends on |
|---|---|---|---|---|
| **T1** | Android: Готовые ответы — canned-response library (list + FAB + editor, whole-list PUT) | A `site:configure` operator opens Ещё → Автоматизация → Готовые ответы, sees the library, adds/edits/deletes a response through an editor screen, and each change round-trips the full list to the server and re-seeds from the echo. | **M** | — (serialises on shared files) |
| **T2** | Android: Метки — tag-vocabulary CRUD (list + FAB + dialog) | A `site:configure` operator opens Ещё → Автоматизация → Метки, creates a tag, renames one in place, and deletes one (with the cascade stated) — each a per-row call followed by a re-fetch. | **M** | — (serialises on shared files) |

Files per slice: see §3.1. **Shared-file sequencing (§3.1):** T1 and T2 are independent in logic but
both edit `MoreScreen.kt`, both `strings.xml`, and `AppModule.kt`, so they **open PRs one at a time** and
the second rebases onto the first's shared-file edits. Either order works; **T1 then T2** is the
recommended order (T1 repoints an existing placeholder, T2 adds a fresh row — smaller diff on top).

Each slice's Done-when: builds; `dotnet`-side unchanged; the app's four commands
(typecheck/lint/test + `ux-gate` if a fixture is touched — none here) pass; the adapter has a
`Ktor…ApiTest` (load→`Loaded`, the whole-list PUT echo→`Saved` re-seed for T1 / each verb's
`Refused(detail)` mapping for T2, the `Tag.AlreadyExists` refusal, delete `204`→`Deleted`); the
`MoreScreen` row appears only under `canConfigureSite`.

---

## 5. Notes (no blocking questions)

Everything needed to build is settled above; the contract is unambiguous in the read sources
(`CannedResponseEndpoints`, `TagEndpoints`, both domain types, the console pages). Three things recorded
rather than asked:

1. **The app's first FAB.** No `FloatingActionButton` exists in the app today. Both screens introduce
   one via `Scaffold`'s slot; a shared `AgoFab` wrapper is deliberately *not* added yet — two call sites
   do not earn the abstraction (the premature-generalisation rule the platform layer itself is governed
   by). If a third FAB screen lands, revisit.

2. **A new `SiteTagsApi` port, not an extension of `ConversationTagsApi`.** Justified in §2.2 — the
   existing port's own doc comment scopes vocabulary *management* out. Both reuse the one `Tag` domain
   type and `TagVocabularyResult`, so the only re-declared signature is the shared `GET`.

3. **Canned's whole-list PUT is last-write-wins**, matching the console. If the author later wants
   optimistic-concurrency protection on the canned-response blob, that is a backend change (an ETag or a
   version column) and its own item — deliberately not designed here, and not a defect this work
   introduces.
