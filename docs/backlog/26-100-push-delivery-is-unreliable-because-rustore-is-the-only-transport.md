# 26-100 · Push delivery is unreliable because RuStore is the only transport — add FCM primary, RuStore fallback

- **Stage**: 26
- **Status**: ready — needs a design pass (a new ADR) before implementation; the *decision* is made
  (below), the *shape* is not.
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
