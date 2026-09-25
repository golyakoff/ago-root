# 26-100 · Push delivery is unreliable because RuStore is the only transport — add FCM primary, RuStore fallback

- **Stage**: 26
- **Status**: in progress — design (ADR-0181) and both code halves merged, and **deployed to the stand
  2026-09-25**: `ago-chat` moved to `2fc67db` (`ago-deploy#266` wired `FCM_SERVICE_ACCOUNT_JSON` into the
  Worker; the real key lives in the node's `.env`, never committed), the Worker booted healthy with FCM
  (`ValidateOnStart` passed), smoke 40/40, drift checks PASS. **Remaining (needs a device):** verify
  end-to-end FCM delivery on a real Google-services phone (a heads-up with no distributor kept resident) —
  then this closes.
- **Found**: 2026-09-24, in a live end-to-end debugging session with the author on two real devices.
- **Decision** (author, 2026-09-24): pursue **option A — FCM as the primary transport, RuStore as the
  fallback** — explicitly to reach "reliability like competitors / banks." The two rejected options and
  the reasoning are recorded below so the new ADR does not re-litigate them.

## What is actually true today, proven live

The Android operator app delivers push **only** through RuStore (VK PNS), by design (`adr/0179`,
`adr/0180`). RuStore Push does not maintain the connection itself — it relies on a **distributor app**
(RuStore, or a VK app) that holds the socket to the push server and hands messages to other apps. This
was traced end-to-end on 2026-09-24:

- **Server side is instant and healthy.** A visitor message produces a `POST …/messages:send` to
  `vkpns.rustore.ru` in the same second; RuStore answers `200` in ~15 ms; no failure is recorded on the
  device row. The latency the author reported is **not** on our side.
- **Delivery to the device is where it breaks.** On a de-Googled phone with no RuStore/VK host,
  `getToken` fails outright (`Host push app is not installed`, `No available hosts found`) — no token,
  no registration, nothing arrives. On a phone *with* VK installed, `getToken` succeeds, the token
  registers, RuStore returns `200` — **but the notification still does not arrive**, until the author
  **manually launched the RuStore app**, at which point the queued pushes came through at once.
- **Root cause, confirmed by that last step:** the distributor app (RuStore/VK) is **killed by the
  OEM's aggressive memory management** (MIUI/HyperOS here), so there is no live connection to receive
  pushes; they only land when the distributor is relaunched. This is inherent to RuStore Push's
  distributor model on OEM ROMs, not a bug in our code.

**Why competitors/banks do not have this:** they deliver via **FCM**, whose distributor is **Google
Play Services** — a system service that is always resident and battery-whitelisted, so the *app* need
not stay in memory. Most serious apps run **multi-transport** (FCM + RuStore/HMS fallbacks). FCM as a
message-delivery channel has generally kept working for Russian apps (the sanctions hit Play billing
and Store distribution, not FCM messaging).

## The decision, and the two options it beat

- **A. FCM primary + RuStore fallback (chosen).** The client uses FCM where Google Play Services is
  present (the majority) — reliable, immediate, app need not stay resident — and RuStore where it is
  not (de-Googled / Huawei / RuStore-only devices). Matches the competitor/bank shape. If FCM is ever
  cut, RuStore still covers. Cost: reintroduces a Google dependency for the majority, needs a Firebase
  project and an FCM server sender, and is a real cross-repo change (client + server + ADR).
- **B. RuStore only, mitigate the OEM kill** (rejected). Asking every operator to whitelist/keep the
  RuStore app alive is fragile and user-hostile — exactly the unreliability this item exists to remove.
- **C. Lean on the app's own live SignalR + presence foreground service** (rejected as a *sufficient*
  fix). It helps while the app/service is alive, but the cold-start wake-up still needs a working
  distributor, and OEMs kill foreground services too. Worth keeping as a complement, not the answer.

## Scope

This is one promise — *operator push is delivered reliably, via FCM where possible and RuStore
otherwise* — spanning two repos plus a decision record. It should get a design pass (one worker,
Opus, covering both repos — the contract is shared) that produces:

- **A new ADR** — "FCM is the primary push transport, RuStore is the fallback" — amending/superseding
  the relevant parts of `adr/0179` and `adr/0180` (which chose RuStore-only). It states the transport-
  selection rule, the geopolitical fallback rationale, and what is given up (a Google dependency for
  the majority).
- **`ago-chat` (server):** a new `Ago.Chat.Infrastructure.Fcm` adapter implementing the existing
  `IPushSender` port (FCM HTTP v1, service-account auth). Routing by `operator_devices.provider`. **The
  architecture is already ready for this**: `IPushSender` (`adr/0179` §5) abstracts the provider, and
  `operator_devices.provider` already exists (today always `RuStore`) — so this is an *additive*
  adapter, not a rewrite. New config/secret for the FCM service account (see `docs/architecture/
  secrets.md`).
- **`ago-android` (client):** integrate Firebase Messaging alongside the RuStore SDK; on startup detect
  Play Services availability and choose the transport, registering the token with the matching
  `provider`; a receiver for FCM messages that feeds the same `IncomingPushRouter`/presenter path
  RuStore already uses. RuStore SDK's own "universal" multi-provider mode is one candidate mechanism to
  evaluate in the design pass.
- **A Firebase project** for AGO Chat (author sets it up; the item records what is needed:
  `google-services.json` for the app, a service-account key for the server).

## Out of scope

- **HMS (Huawei Push)** as a third transport — a separate, later item if Huawei operators turn up. The
  port + `provider` column make it additive whenever it is wanted.
- The three defects this same debugging session found, each filed on its own number: silent push-
  registration failure with no operator warning (**26-101**), `DeviceRegistrationWorker` cannot be
  created in release (**26-102**), and the stale-device-row fan-out "push storm" (**26-83**, already
  open — this session found its likely root cause: dead device rows are never pruned).

## Done when

- [ ] A new ADR records "FCM primary, RuStore fallback", amending `adr/0179`/`adr/0180`, with the
      transport-selection rule and the trade-off stated.
- [ ] `ago-chat` has an FCM adapter behind `IPushSender`, selected per device by `provider`, with the
      RuStore adapter unchanged — proven by a test sending through each provider.
- [ ] `ago-android` registers an FCM token where Play Services is present (RuStore otherwise) and
      surfaces an FCM push through the existing notification path.
- [ ] Proven on a real Google-services device: a visitor message produces a heads-up **without** the
      app or any distributor kept resident — the reliability this item exists for.
- [ ] `dotnet format`/`build`/`test` (ago-chat) and `./gradlew ktlintCheck lint test` (ago-android)
      green.

## Implementation plan

Design decided in `adr/0181` (2026-09-24). The seams `adr/0179`/`adr/0180` built make this an
**additive second transport**, not a rewrite: server-side `IPushSender` + `operator_devices.provider`,
client-side `PushRegistrationGateway` + `IncomingPushRouter`. This is the first exercise of
`adr/0179` §5's own "the trigger that reopens it is a real second provider" prediction.

### The one cross-repo contract (get this right first)

Both transports must deliver an **identical data-only payload** so the client's existing parse/dedupe
path is provider-blind. `RuStorePushSender.BuildData`
(`ago-chat/src/Ago.Chat.Infrastructure.RuStore/RuStorePushSender.cs:106-115`) folds
`title`/`body`/`groupKey` into a flat `data` map alongside `conversationId`/`messageId`
(`NotifyOperatorDevicesHandler.cs:60,107-111`); the client reads exactly those keys
(`ago-android/app/src/main/kotlin/ago/chat/android/devices/IncomingPushRouter.kt:63,100-101`). The FCM
adapter MUST produce the same key set, data-only (no `notification`/`android.notification` block), or
`decideAlert`/dedupe silently break on FCM devices. One designer owns both halves of this contract.

### ago-chat (server) — new `Ago.Chat.Infrastructure.Fcm` adapter, routing by `provider`

1. **Domain.** `src/Ago.Chat.Domain/PushProvider.cs` — add an `Fcm` member (append; stored by CLR name,
   so append is safe per that enum's own remarks). Its `RuStore`-only comment is updated to name both.
2. **New project `src/Ago.Chat.Infrastructure.Fcm/`** (references `Application` + `Domain` only — arch
   tests enforce it; add to `Ago.Chat.slnx`), mirroring `Ago.Chat.Infrastructure.RuStore`:
   - `FcmPushSender : IPushSender` — thin, no retry/timeout (the `ResilientPushSender` wrapper carries
     those, exactly as for RuStore). FCM **HTTP v1**: `POST
     https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`, body
     `{"message":{"token","data",{"android":{"ttl":"300s","priority":"high"}}}}`. Data-only, same flat
     map as `BuildData`. Because FCM (unlike RuStore, `adr/0180` §4a-b) *does* have `android.priority`
     and `android.collapse_key`, restore `priority = "high"` (`adr/0179` §3's original Doze escape) and
     optionally set `collapse_key` from `PushMessage.GroupKey` to collapse *undelivered* queued pushes
     — the one capability `adr/0180` recorded as lost. `PushMessage.RecommendedTimeToLive`
     (`IPushSender.cs:112`) is reused unchanged (`android.ttl` is a protobuf Duration string, the shape
     `RuStoreAndroidConfig.Ttl` already assumed FCM has).
   - Error mapping into the existing `PushSendOutcome` (`IPushSender.cs:120-140`): FCM v1's error body
     carries `error.status` + `error.details[].errorCode`. `UNREGISTERED` / `INVALID_ARGUMENT` (bad or
     stale token) → `TokenGone`; `401`/`403` (our credential) and `429`/`500`/`503` → `TransientFailure`
     — the identical "never revoke a device for our own credential fault" discipline
     `RuStorePushSender.Classify` states. Anything unparseable throws (→ resilience retry).
   - `FcmOptions` (`Push:Fcm` section): `ProjectId` (public, real default like `RuStoreOptions.ProjectId`)
     and the service-account credential (see secrets below).
   - **OAuth2 bearer mint + cache.** The service account JSON must become a short-lived bearer against
     `https://oauth2.googleapis.com/token` (RS256-signed JWT assertion), cached until ~expiry — the
     "second host" `adr/0180` §1 noted RuStore avoids. **Add `Google.Apis.Auth`** for this: it is the
     narrow, official library for exactly this mint (`ServiceAccountCredential`/`GoogleCredential`),
     and hand-rolling RS256 JWT signing + refresh over a raw `HttpClient` is more code, more crypto to
     get wrong, and buys nothing — note this justification in the PR per the "no NuGet package without
     saying what it replaces" rule. (`FirebaseAdmin` is the heavier alternative; rejected — it pulls a
     whole SDK to send one HTTP message this adapter already shapes by hand.)
3. **Routing — a resolver, now that the dispatch table has two real entries.** Add
   `IPushSenderResolver { IPushSender Resolve(PushProvider provider); }` to
   `src/Ago.Chat.Application/Abstractions/` (Application, so the handler stays testable with a fake;
   the alternative — keyed DI attributes in the handler ctor — leaks a DI mechanism into Application).
   Change `NotifyOperatorDevicesHandler` (`.../NotifyOperatorDevices/NotifyOperatorDevicesHandler.cs:42`)
   to take `IPushSenderResolver` instead of `IPushSender`, and inside the per-device loop
   (`:130-143`) resolve by the `device.Provider` it already has in hand (`:134` already computes the
   provider tag). No metric change: `ChatMetrics.RecordPushSend(reason, providerTag, status)` already
   carries the provider tag, so `fcm` flows for free.
4. **Worker DI** (`src/Ago.Chat.Worker/Program.cs:194-247`): bind+validate `FcmOptions`, add
   `AddHttpClient<FcmPushSender>` (base address `…/v1/projects/{projectId}/`, no default auth header —
   the OAuth2 token is per-request from the cached mint), wrap it in its **own** `PushResiliencePipeline`
   instance (a second, separately-keyed pipeline so an FCM outage never trips RuStore's breaker and
   vice-versa — today there is one shared `"Push"` pipeline; split it to `"Push:Fcm"`/`"Push:RuStore"`),
   and register `IPushSenderResolver` mapping both providers. **Startup validation decision:** keep the
   existing `ValidateOnStart` fail-fast for *both* credentials (the Worker already refuses to boot
   without a RuStore token, so requiring FCM too is consistent, and the real deployment wants both). If
   a lighter local-dev story is wanted later, the fallback is "register only the providers configured,
   resolver records `RecordPushSuppressed("no_sender")` for an unconfigured provider" — noted, not built.
5. **Config / secrets.** Reintroduce **`FCM_SERVICE_ACCOUNT_JSON`** in `infra-credentials`, read by
   `Ago.Chat.Worker` only (never `Api`/`Webhooks`), bound to `Push:Fcm:ServiceAccountJson`; rotation
   class **Draining** (a Google service account may hold two keys — better than RuStore's Restart). The
   FCM project id is public (like the RuStore one), supplied as ordinary `.env` config. Update in the
   *same* change: `docs/architecture/secrets.md` §A, `tools/secrets-audit.sh`, the three
   `ago-deploy/**/.env.example` files, and `personal-data.md`'s destinations table +
   `processing-instruction-facts.md` (a **Google/FCM** row *in addition to* the VK/RuStore row) — or the
   secrets audit fails, which is what it is for.
6. **Tests.** `Ago.Chat.Infrastructure.Fcm` unit tests mirroring `RuStorePushSenderTests` — pin the
   exact request JSON (data-only, keys, ttl, priority), classify each documented FCM outcome, and cover
   the token-mint cache (one mint reused, re-mint after expiry). Application: extend
   `NotifyOperatorDevicesHandlerTests` with a two-device case (one `fcm`, one `rustore`) proving the
   resolver routes each to its own sender and revokes the right row on `TokenGone`.

### ago-android (client) — FCM alongside RuStore, per-device transport selection

1. **Gradle.** Add `com.google.firebase:firebase-messaging` (via the Firebase BoM) — `google()` is
   already a resolution repo (`settings.gradle.kts:12`). **Firebase init: recommend the manual
   `FirebaseOptions` path, not the `google-services` plugin.** Build `FirebaseOptions` from `BuildConfig`
   fields populated by `agoProperty(...)` (`app/build.gradle.kts:56,199-203` — the exact pattern
   `AGO_RUSTORE_PUSH_PROJECT_ID` and `AGO_API_BASE_URL` already use), so no `google-services.json` is
   committed to this public repo and every value stays a public-by-construction BuildConfig field like
   its neighbours. New fields: `AGO_FCM_PROJECT_ID`, `AGO_FCM_APPLICATION_ID`, `AGO_FCM_API_KEY`,
   `AGO_FCM_SENDER_ID`. (The conventional `com.google.gms.google-services` plugin + committed
   `app/google-services.json` is the alternative; if the author prefers it, the file must be gitignored
   and injected at build time, since these repos are public.)
2. **Init** (`app/src/main/kotlin/ago/chat/android/AgoChatApplication.kt:64-80`): call
   `FirebaseApp.initializeApp(this, fcmOptions)` in the main-process branch, next to
   `RuStorePushClient.init`. Init is cheap and unconditional; *use* of FCM is gated on availability (3).
3. **Transport selection.** New `TransportSelector` (in `:app/devices`) using
   `GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS`
   → `PushProvider.Fcm`, else `PushProvider.RuStore`. Wire it into the gateway binding at
   `di/AppModule.kt:462` (`providePushRegistrationGateway`), which today binds `RuStorePushGateway`
   directly: replace with a selecting binding that resolves the chosen gateway *and* exposes the chosen
   provider to the coordinator.
4. **FCM gateway.** `FcmPushGateway : PushRegistrationGateway` (`:app/devices`) mirroring
   `RuStorePushGateway.kt` — `FirebaseMessaging.getInstance().token`/`deleteToken()` bridged with the
   same `suspendCancellableCoroutine` idiom (never `Task.await()`, per that file's own rule), and
   `checkAvailability()` mapping Play-Services status onto the existing `PushAvailability`/
   `PushUnavailableReason` types (`PushRegistrationGateway.kt:51-81`) — reuse `HostAppNotInstalled`-style
   reasons or add a `PlayServicesUnavailable` reason. `RuStorePushGateway` is untouched.
5. **Provider must reach the server.** `DeviceRegistrationApi.register` currently has no provider
   parameter and `KtorDeviceRegistrationApi` hardcodes `"rustore"`
   (`core/network/.../KtorDeviceRegistrationApi.kt:47,72`). Add a `provider: String` (or a
   `PushProvider` enum) argument to `DeviceRegistrationApi.register`
   (`core/domain/.../DeviceRegistrationApi.kt:26`) and pass it through the wire DTO
   (`KtorDeviceRegistrationApi.kt:80-84`). `DeviceRegistrationCoordinator`
   (`app/src/main/.../DeviceRegistrationCoordinator.kt:59-80`) passes the selected provider for
   `registerThisDevice()`, and each messaging service passes *its own* provider into
   `onNewToken(provider, token)` (`:77`). The `PLATFORM = "android"` literal stays.
6. **Receive path.** New `AgoFcmMessagingService : FirebaseMessagingService` (`:app/devices`) mirroring
   `AgoPushMessagingService.kt` — `onNewToken` → `coordinator.onNewToken(Fcm, token)`,
   `onMessageReceived(RemoteMessage)` → `router.handleMessage(message.messageId, message.data)`,
   `onDeletedMessages()` → `router.handleDeletedMessages()`. **`IncomingPushRouter` needs no change** —
   it already takes a nullable message id + a `Map<String,String>` and is provider-blind (`:59-92`).
   Manifest (`app/src/main/AndroidManifest.xml`): add the FCM service with
   `<intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT"/></intent-filter>`,
   `android:exported="false"` (FCM, unlike RuStore's distributor model, starts it in-process). No new
   permission — `POST_NOTIFICATIONS` already covers both.
7. **RuStore "universal" SDK mode — evaluated, rejected** (`adr/0181` Alternatives). The universal
   client bundle would pick a transport for us, but it hides which one from the server (breaking
   route/observe/revoke by `provider`), pulls in HMS this stage does not want, and still needs the
   Google service account server-side. Two explicit gateways behind the one existing
   `PushRegistrationGateway` seam are cheaper to reason about and already half-built. Named as the
   reopening point when iOS arrives.
8. **Tests.** `FcmPushGatewayTest` (mapping logic behind a seam, JVM); extend
   `DeviceRegistrationCoordinatorTest` for provider pass-through and `KtorDeviceRegistrationApiTest`
   (`core/network/src/test/...`) to assert the wire `provider` varies (`fcm`/`rustore`); a
   `TransportSelector` unit test (Play Services present → `fcm`, absent → `rustore`); an
   `IncomingPushRouterTest` case proving an FCM-shaped data map routes identically. `ktlintCheck`,
   `lint`, `test`, and the Playwright-style `ux-gate` where applicable — real end-to-end (the last
   Done-when box) needs a physical Google-services device and cannot be proven in the sandbox (no
   emulator); flag it for the author's own device.

### Firebase artifacts the author must produce (implementation is blocked until these exist)

1. **A Firebase project** for AGO Chat (Firebase console). Everything below comes from it.
2. **`google-services.json`** for the Android app registered under package `ago.chat.android` with the
   release signing SHA fingerprint already recorded in `secrets.md` §E
   (`SHA256:60:96:05:98:D6:9B:5D:16:AB:A3:70:19:A5:C4:B7:3A:3E:F8:7C:AA:2B:68:97:AD:26:CB:6E:CC:46:34:CC:09`).
   Under the recommended manual-init path its values go into `gradle.properties` (agoProperty) →
   `BuildConfig`, **not** a committed JSON file; the FCM project id is public like the RuStore one.
3. **A service-account key (JSON)** with the Firebase Cloud Messaging API enabled (Project settings →
   Service accounts → Generate new private key). Held only as `FCM_SERVICE_ACCOUNT_JSON` in
   `infra-credentials`, never committed, bound to `Push:Fcm:ServiceAccountJson` on `Ago.Chat.Worker`.

### One promise, one item — with a safe two-PR split along the repo seam (rule 15)

The promise ("operator push is delivered reliably, via FCM where possible and RuStore otherwise") lands
green only when both repos ship. But the server half is **inert until the client half exists**: no
device reports `provider = fcm` until the client selects it, so the FCM adapter + resolver change no
runtime behaviour and are exercised only by their own tests. That makes a legitimate split where the
first half is green on its own:

- **PR 1 (ago-chat):** FCM adapter, resolver, per-provider resilience, `Fcm` enum member, secret +
  doc/audit updates. Promise: *"the Worker sends through FCM for a device whose row says `fcm`, proven
  by test"* — green, and observably a no-op in production until PR 2.
- **PR 2 (ago-android):** Firebase init, transport selection, FCM gateway + messaging service, provider
  on the registration call. Promise: *"a Play-Services device registers `fcm` and surfaces a push
  through the existing notification path"* — the end-to-end promise lands here.

Neither PR leaves the other red (PR 1 does not depend on any device sending `fcm`; PR 2 relies on PR 1
already merged). One designer/worker owns both because of the identical-`data`-key contract above — the
"one worker per cross-repo task" rule. This is exactly the additive-adapter shape `adr/0179` §5
predicted, so a single item with this two-PR landing is the right shape rather than two items.
