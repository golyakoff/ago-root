# Tenant self-management on Android — screen inventory and slice breakdown

**Status:** scoping. This doc inventories the tenant self-management surface (widget, channels, and
the other per-site settings) and slices it into vertical tickets. It does **not** design any screen
in detail — the per-screen designs already live in `ago-android/docs/scope-inventory.md` (the 54-route
port table) and `ago-android/docs/navigation.md` (the Ещё nav model). This doc's job is to say *what
is left to build, in what order, and what each ticket promises*.

## 1. Context & goal

The AGO Chat operator app is where a tenant answers customers from a phone. Today it can answer, book,
read analytics, and see one channel screen — **«Установка виджета»** (`channels/InstallWidgetScreen`,
`26-159`) — and nothing else in the tenant self-management space. Every other per-site setting
(widget appearance, the messenger channels, canned responses, tags, auto-reply, consent documents,
modules) is reachable only from the web console (`ago-console`). The goal is to bring the tenant's own
configuration onto the phone so an operator or owner "on the go" can connect a Telegram bot, tweak the
widget greeting, or publish a canned response without opening a laptop — the same "the app exists so
you don't have to be at a desk" reason push and the pending-booking queue exist. Scope here is
**tenant self-management**; platform-owner screens stay web-only (`scope-inventory.md` §2) and are out
of scope.

**The design thinking is largely already done.** `scope-inventory.md` and `navigation.md` already
dispositioned every one of these screens (as-is / redesign / excluded) and placed each in the Ещё
list-of-lists. This doc treats those two as authoritative for *how* each screen looks and *where* it
hangs, and adds only what they do not: the build-order slicing and the backend-availability check.

## 2. Backend availability — the one-line answer

**No slice below needs backend work.** Every endpoint these screens call is already live in `ago-chat`
— the proof is that `ago-console` already calls each one (the API modules surveyed:
`widgetConfigApi`, `telegramChannelApi`, `maxChannelApi`, `vkChannelApi`, `emailChannelApi`/branding,
`offlineAutoReplyApi`, `cannedResponsesApi`, `tagsApi`, `siteConsentDocumentsApi`,
`visitorRestrictionsApi`, `modulesApi`). So every slice is a **client-only** port: a Ktor adapter in
`core/network`, a domain port in `core/domain`, a ViewModel + Compose screen in `app`, a row wired into
`MoreScreen`, string resources in both locales, and tests. **No `ago-chat` change, no DB migration, no
migration lane** for any slice.

Two backend facts worth stating because they *bound* the scope rather than expand it:

- **Allowed-origins is read-only on the phone, by construction.** `Ago.Chat.Api` exposes no
  `site:configure`-gated write for a chat site's allowed origins — only the platform-owner route
  `PUT /api/v1/owner/sites/{siteId}/allowed-origins`. The install screen already renders origins
  read-only for this reason (`InstallWidgetViewModel`'s own doc comment). No slice here changes that.
- **Channel tokens never round-trip.** `adr/0069`: the connect endpoints accept a bot token once and
  no response field can carry it back. The Android connect screens inherit that — a reconnect asks for
  a fresh token, never shows the old one. VK is the one exception that returns anything
  shown-once: a `callbackUrl` + `webhookSecret` at connect time only (`ConnectVkChannelResponseDto`).

### Established Android architecture these slices follow

The app already has a clean split every slice reuses verbatim (`InstallWidget*` is the worked example):

| Layer | Location | Role |
|---|---|---|
| Domain port | `core/domain/.../<area>/<Area>Api.kt` | interface + result types, no framework deps |
| Adapter | `core/network/.../<area>/Ktor<Area>Api.kt` | Ktor client, `X-Ago-Active-Site` header, problem-details mapping |
| Screen | `app/.../<feature>/<Feature>Screen.kt` + `UiState` + `ViewModel` | route-wires/screen-renders split, Hilt VM |
| Nav | `app/.../shell/MoreScreen.kt` (`buildMoreRows`) | the row that opens it, drawn only under its gate |

**Every gate is hide-not-disable**: a row an operator's permission does not cover is not drawn at all
(`buildMoreSections`' own "a section with no rows is not returned" rule, ported from
`consoleNav.ts`). The gate for almost every screen below is `site:configure`; exceptions are noted.

## 3. Screen inventory

Grouped into the three areas the author named. For each: what the console does, the backend endpoints
(all existing — see §2), the proposed Android screen and its home in the Ещё nav, its gate, and the
work kind (all **UI-only**).

### 3a. Виджет — widget management

| Screen | Console today | Endpoints (exist) | Android screen | Ещё home | Gate | Kind |
|---|---|---|---|---|---|---|
| **Установка виджета** | `InstallSnippetPage`: embed snippet, allowed origins, 4-state install health | `GET /sites/{id}/installation` | **BUILT** (`InstallWidgetScreen`, `26-159`) | Каналы | `site:configure` | done |
| **Виджет на сайте** | `WidgetConfigPage`: appearance + behaviour form, colour picker, live preview | `GET`/`PUT /sites/{id}/widget-config` | Pinned preview region above a scrolling form; Material colour input (`scope-inventory` §7) | Каналы | `site:configure` | UI-only |

`WidgetConfigDto` carries ~15 fields across three groups: **appearance** (`primaryColorHex`,
`position`, `panelTitle`, `locale`, `channelSwitcherPlacement`/`IconSize`), **greeting/behaviour**
(`attractAttention`, `autoOpenEnabled`/`Delay`/`GreetingText`, `contactCaptureConfirmationText`), and
**consent/booking flags** (`requireContactConsent`, `noticeText`/`noticeUrl`, `acceptUnverifiedPhone`,
`allowAttachmentUploadsByDefault`). The whole DTO is the PUT body, so a partial save silently resets
absent booleans (`widgetConfigApi`'s own `23-108`/`25-104` remarks) — the Android VM must round-trip
the full object, never a patch. Its size is the reason "one screen or split?" is an open decision (§5).

### 3b. Каналы — per-channel setup

| Screen | Console today | Endpoints (exist) | Android screen | Gate (console / server) | Kind |
|---|---|---|---|---|---|
| **Telegram** | `TelegramChannelPage`: connect (paste token) / live status / disconnect | `GET`/`POST`/`DELETE /sites/{id}/channels/telegram` | Connect form + live status card (verified / unreachable / refusal) + disconnect | `site:configure` / `channel:manage` | UI-only |
| **MAX** | `MaxChannelPage`: identical shape | `.../channels/max` | same reusable connect screen | `site:configure` / `channel:manage` | UI-only |
| **VK** | `VkChannelPage`: connect returns `callbackUrl`+`webhookSecret` shown once | `.../channels/vk` | same screen + a shown-once callback/secret panel | `site:configure` / `channel:manage` | UI-only |
| **Почта (branding)** | `EmailChannelPage`: brand company name + logo upload; not a connect flow | `GET`/`PUT /sites/{id}/branding`, `POST /branding/logo` | Settings form; logo via Android photo picker, validation server-side (`adr/0177`) | `site:configure` | UI-only |
| **Автоответ вне смены** | `OfflineAutoReplyPage`: enabled toggle, fallback reply, ordered keyword→reply rules (first match wins) | `GET`/`PUT /sites/{id}/offline-auto-reply` | Reorderable rule list with drag handles; "order is behaviour" stated on screen | `site:configure` | UI-only |

**Telegram/MAX/VK are structurally one screen.** All three are `connected`/`channelCredentialId`/
`createdAt` + the four live-check fields (`verified`, `unreachable`, `refusalReason`, `checkedAt`) and a
connect-by-token / disconnect-by-id pair. They should share one `ChannelConnectScreen` parameterised by
channel, not three copies — which is why the slicing builds the scaffold once (Telegram) and adds MAX/VK
onto it. VK's connect response is the only shape difference (the shown-once callback/secret panel).

Pasting a bot token on a phone is *easier* than on desktop — the token often arrives in a message on the
same device (`scope-inventory` §7). Note this is entering a **channel** token, not a credential into a
third-party login, so it is ordinary tenant configuration.

### 3c. Прочие настройки — other settings, each with a mobile-or-console call

For each, a reasoned call on whether it belongs on the phone. A mobile app need not mirror everything;
the test is "would a tenant plausibly do this from a phone, and does shrinking it lose nothing that
matters."

| Screen | Console today | Endpoints (exist) | Mobile? | Reasoning |
|---|---|---|---|---|
| **Готовые ответы** (canned) | `CannedResponsesPage`: list, PUT-whole-list | `GET`/`PUT /sites/{id}/canned-responses` | **Yes** | Operators insert these while chatting; editing one on the go is a natural companion to the thread. List + FAB, one editor screen (the desktop "blank trailing row" idiom fails on a soft keyboard — `scope-inventory` §8). |
| **Метки** (tags) | `TagsPage`: CRUD site vocabulary | `GET`/`POST`/`PUT`/`DELETE /sites/{id}/tags` | **Yes** | Small vocabulary, low friction; the thread's tag sheet already exists, so managing the vocabulary belongs nearby. Same list + FAB shape as canned. |
| **Автоответ вне смены** | (see §3b) | offline-auto-reply | **Yes** | The archetypal away-from-desk setting — you configure the offline reply *because* you are offline. Listed under Каналы in nav, но it is a "Прочие"-style config screen. |
| **Ограниченные посетители** (visitor restrictions) | `RestrictedVisitorsPage`: list + lift | `GET /visitor-restrictions`, `POST /{visitorId}/lift` | **Yes** | Oversight + a quick reversible action (lift a block). `navigation.md` places it in the **Диалоги overflow**, not Ещё — it is conversation oversight, not site config. Keyset-paged list. |
| **Документы согласий** (consent) | `DocumentsPage`: read published version, publish new, "who accepted what" table | `GET`/`POST /sites/{id}/consent-documents[/{purpose}]`, `.../acceptances` | **Partial** | Reading the current version and the acceptance table is fine on a phone. **Publishing** means pasting a long legal text — real but awkward; `scope-inventory` §9 keeps it as its own full-screen editor. Open decision §5: publish on mobile, or read-only. |
| **Модули / FAQ** | `FaqModulePage`: register module, manage knowledge base | `GET`/`PUT /sites/{id}/modules` (+ `faqKnowledgeBaseApi`) | **Partial** | Module *registration* (trigger words, entry point) is a small form — fine. FAQ *knowledge-base* management is content-heavy desk work — open decision §5. |
| **Продукты** (entitlements) | `ProductsPage`: what the tenant could buy / what is enabled | reads `enabledModules` from permissions/tenancy (no dedicated call) | **Yes (read-only)** | A short read; no write. Cheap to port as-is. Belongs in Администрирование. |
| **ИИ-подсказки / ИИ и данные** | `AiAddOnPage`/`AiReplyDraftPage`: toggles + separately-timestamped consent controls | `aiAddOnApi`, `replyDraftApi` | **Deferred** | Toggles, low mobile urgency; `25-04` forbids collapsing the three AI consent controls into one — a phone is where that temptation arises, so port carefully or defer. Out of this wave's core. |
| **Оплата / Хранилище / Выгрузка** | billing (reads only, checkout → Custom Tab), storage quota+list, export | `billingApi`, storage, `siteExportsApi` | **Deferred** | Already dispositioned in `scope-inventory` §9. Billing cannot take money on Android (Play policy → checkout opens the console). These are Администрирование financial screens, lower priority than the widget/channel/config core the task targets — kept out of the first slices, flagged §5. |

## 4. Ticket breakdown (vertical slices)

Every slice: `ago-android` only, **backend-needed = No**, **migration-lane = No** (Android is a client;
these are read/write against existing endpoints). Ordered by dependency then value. Sizes are rough
(S ≈ one screen, thin DTO; M ≈ screen + non-trivial form/list state; L ≈ large form or multi-screen).

| Slice | Promise that lands green | Depends on | Size |
|---|---|---|---|
| **A — Widget config** | An operator with `site:configure` can open «Виджет на сайте», see the live widget config, edit appearance + behaviour + flags, and save (full-DTO round-trip). | — | L |
| **B — Channel connect scaffold + Telegram** | An operator can connect a Telegram bot by pasting a token, see live status (verified/unreachable/refusal), and disconnect — on a reusable `ChannelConnectScreen`. | — | M |
| **C — MAX + VK on the scaffold** | An operator can connect/disconnect MAX and VK on the same screen, with VK's shown-once callback URL + webhook secret displayed at connect. | B | M |
| **D — Email / branding** | An operator can set the brand company name and upload a tenant logo (Android photo picker), seeing logo status (Pending/Ready/Rejected + reason). | — | M |
| **E — Offline auto-reply** | An operator can toggle offline auto-reply, edit the fallback, and add/reorder/remove keyword→reply rules with order-as-behaviour stated on screen. | — | M |
| **F — Canned responses** | An operator can list, add, edit, reorder and delete canned responses (list + FAB + per-item editor). | — | M |
| **G — Tags vocabulary** | An operator can list, create, rename and delete the site's tag vocabulary. | — | S–M |
| **H — Visitor restrictions** | An operator with `site:configure` can open the restricted-visitors list (keyset-paged) from the Диалоги overflow and lift a restriction. | — | M |
| **I — Consent documents (read + acceptances)** | An operator can read the current published Contact/Marketing document and the "who accepted what, when" table. | — | M |
| **I2 — Consent publish** *(only if §5 decides mobile-yes)* | An operator can publish a new version of a consent document from a full-screen editor. | I | M |
| **J — Modules / FAQ registration** | An operator can view enabled modules and register/update a module's trigger words and entry point. | — | S–M |
| **K — Products (entitlements read)** | An operator can see what products the tenant has enabled and what is available. | — | S |

**Slices A–K are otherwise independent, with one shared-file caveat:** each adds a row to
`MoreScreen.kt`'s `buildMoreRows` and strings to `strings.xml` (both locales). Under the file-based
non-interference rule (CLAUDE.md rule 13), two slices editing `MoreScreen.kt`/`strings.xml`
concurrently will collide. Sequence the row-wiring edits, or land the nav rows for a batch in one small
follow-up, so parallel lanes touch only their own `core/network` + `app/<feature>` files. Slices B→C
and I→I2 are the only hard ordering dependencies.

**Suggested order by value for the first tenants** (commercial intent — multi-channel is a selling
point, away-from-desk config is the app's reason to exist): B, C (channels) → E (offline auto-reply) →
A (widget) → F, G (canned, tags) → D (email) → H (restrictions) → I (consent) → J, K. Administration
financial screens (billing/storage/export/AI) are a later wave (§5).

## 5. Open decisions for the author

Each of these decides something — a product scope call or a screen shape — so per CLAUDE.md rule 14
they are stated as questions with options, not silently answered in the slicing above.

1. **Widget config: one screen or split (affects Slice A's size)?**
   `WidgetConfigDto` has ~15 fields across appearance / behaviour / consent-and-booking flags.
   - **(a) One screen, one slice (L).** Matches the console's single page; one promise. Cost: a large
     review and a long scrolling form on a phone.
   - **(b) Split into "Виджет: внешний вид" and "Виджет: поведение/согласие" (two M slices).** Smaller
     reviews, cleaner phone screens. Cost: two rows in Каналы, and both must PUT the *whole* DTO
     (partial saves reset absent booleans), so the split is presentational only — a subtle correctness
     trap to test for.
   *Recommendation to weigh:* (b) reads better on a phone and matches the review-capacity constraint,
   but only if both halves are tested to send the full object.

2. **Consent-document publishing on mobile — build it, or read-only (decides whether Slice I2 exists)?**
   - **(a) Read-only (Slice I only).** Read the current version + acceptances; publishing stays in the
     console. Honest about a phone being a poor place to compose legal text.
   - **(b) Full (I + I2).** A full-screen editor for pasting a prepared legal text. `scope-inventory`
     §9 leans this way ("pasting from a phone's clipboard is a real path").
   *This is a genuine product call:* does a tenant ever publish a policy from a phone, or only read who
   accepted it?

3. **FAQ knowledge-base management on mobile — in Slice J, or console-only?**
   - **(a) Module registration only (Slice J as scoped).** Trigger words + entry point form; the
     knowledge-base content stays console-only.
   - **(b) Full FAQ management.** Also port knowledge-base entry editing — content-heavy, and arguably
     desk work.
   *Recommendation to weigh:* (a) — a knowledge base is authored at a desk; the phone needs only to
   turn the module on/off and adjust triggers.

4. **Do channel screens gate on an entitlement, or only `site:configure`?**
   Multi-channel (Telegram/MAX/VK) may be an Inbox/paid entitlement rather than something every tenant
   has. The console gates only on `site:configure`. Options: **(a)** mirror the console (permission
   only); **(b)** additionally hide a channel row when the tenant lacks the channel/Inbox entitlement.
   Needs the author to confirm whether channels are entitlement-gated at all today.

5. **How much of Администрирование (billing / storage / export / AI / documents) is in this
   initiative's scope?**
   The task centers on widget + channels + settings. The financial/storage/AI screens are already
   inventoried (`scope-inventory` §9) and dispositioned, but they are a distinct, lower-urgency wave
   (billing can't even take money on Android — Play policy routes checkout to the console). Options:
   **(a)** exclude from this initiative and file separately when prioritised; **(b)** include Products
   (K) + billing-read now and defer the rest; **(c)** include all. The slicing above assumed (a)/(b) —
   confirm.
