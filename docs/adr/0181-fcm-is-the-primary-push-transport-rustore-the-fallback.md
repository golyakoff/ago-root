# ADR-0181: FCM is the primary push transport, RuStore is the fallback

- **Status**: Accepted; **amends ADR-0179 and ADR-0180**. It reverses `adr/0180`'s single provider
  choice (RuStore *instead of* FCM) into a two-transport rule, and keeps everything both ADRs built:
  `adr/0179`'s schema, fan-out and client-owns-loudness design stand entire, and `adr/0180`'s RuStore
  adapter is not removed - it becomes the fallback. This is an amendment, not a supersession, because
  neither prior ADR becomes wrong: `adr/0180`'s RuStore adapter is exactly what the fallback path is,
  and `adr/0179` §5's `provider` column and `PushMessage`-shaped port are what make adding a second
  transport a code change rather than a redesign - the trigger that ADR named ("the first real second
  device") has fired, and this is the change it predicted.
- **Date**: 2026-09-24
- **Stage**: 26

## Context

`adr/0180` chose RuStore Push as the operator app's only transport, to satisfy `personal-data.md`'s
"in Russia" default without the written legal escalation FCM would need. It named RuStore's distributor
model as its worst consequence and made no latency claim. On 2026-09-24 that consequence was traced
end-to-end on two real devices, and the result is the force that reopens the decision.

- **The server side is healthy and instant.** A visitor message produces a `POST …/messages:send` to
  `vkpns.rustore.ru` in the same second; RuStore answers `200` in ~15 ms; no failure is recorded on
  the device row. Nothing on this project's side is slow.
- **Delivery to the device is where it breaks, and it breaks by design.** RuStore Push has no
  connection of its own: it depends on a distributor app (RuStore, or a VK app) that holds the socket
  and forwards to embedding apps. On the tested MIUI/HyperOS phone the OEM kills that distributor, so
  queued pushes arrived only when the RuStore app was **manually relaunched**. On a de-Googled phone
  with no distributor at all, `getToken` fails outright (`Host push app is not installed`) - no token,
  no registration, nothing.
- **Competitors and banks do not have this**, because FCM's distributor is Google Play Services - a
  system service that is always resident and battery-whitelisted, so the *app* need not stay in memory.
  FCM as a message channel has kept working for Russian apps; the sanctions hit Play billing and store
  distribution, not FCM messaging.
- **The residency default `adr/0180` optimised for was never free** - it was paid in reliability, which
  is the one thing the Android app exists to deliver ("a phone in a pocket that vibrates", `adr/0178`).
- **There are still zero real tenants and not one operator token in any table** (`adr/0180`), so this
  is again taking a decision while it is cheap, not responding to an exposure.
- **The seams for a second transport already exist and are unused for it.** Server-side, `IPushSender`
  is a provider-neutral port and `operator_devices.provider` is a real column with one member today.
  Client-side, `PushRegistrationGateway` already isolates the SDK behind a seam a JVM test can fake,
  and `checkPushAvailability()` already reports whether the current transport can deliver.

## Decision

**Operator push uses FCM where it can and RuStore where it cannot, chosen per device.**

1. **The transport-selection rule is the client's, made once per device, recorded on the row.** On
   registration the client asks whether Google Play Services is available and usable
   (`GoogleApiAvailability`); if so it registers an **FCM** token with `provider = fcm`, otherwise it
   registers a **RuStore** token with `provider = rustore` exactly as today. The server holds no
   selection logic: it reads `operator_devices.provider` and sends through the matching transport. A
   phone that changes state (Play Services installed, or a RuStore account signed in) re-registers on
   its next sign-in / rotation / periodic job and flips its own row - the registration path is already
   an idempotent upsert (`adr/0179` §1), so nothing new is needed to carry a provider change.

2. **The server gains a second `IPushSender`, selected by `provider`.** `adr/0179` §5 registered one
   implementation directly and refused a provider registry because "a dispatch table with one entry is
   a guess about the second". The second is now real, so the dispatch table earns its place: a
   resolver maps `PushProvider → IPushSender` (two entries), and `NotifyOperatorDevicesHandler` picks
   the sender by `device.Provider` inside its existing per-device loop. Both senders keep their own
   resilience wrapper; the RuStore sender is unchanged.

3. **`adr/0179` §3 holds unchanged on both transports: data-only messages, the client decides
   loudness.** FCM's data-only messages were `adr/0179`'s original mechanism and RuStore's were
   `adr/0180`'s proof it survived a provider change; nothing about running both alters it. Each
   transport delivers a `data` payload with no `notification`/`android.notification` block, and the
   client applies `decideAlert` before rendering. The server never suppresses on presence.

4. **FCM reintroduces a second credential and a second host, held by the Worker alone.**
   `FCM_SERVICE_ACCOUNT_JSON` (the credential `adr/0179` designed and `adr/0180` removed) returns to
   `infra-credentials`, read only by `Ago.Chat.Worker`, never by the internet-facing `Ago.Chat.Api`.
   FCM HTTP v1 mints an OAuth2 bearer from that service account against `oauth2.googleapis.com` and
   sends to `fcm.googleapis.com` - the "two hosts, not one" cost `adr/0180` §1 noted RuStore avoided.
   `RUSTORE_PUSH_SERVICE_TOKEN` stays exactly as it is.

5. **HMS (Huawei Push) is explicitly out of scope.** A Huawei operator with neither Play Services nor
   a RuStore distributor is still unreached; that is a third transport for a later item if such
   operators turn up, additive behind the same port and column, and this ADR does not build it.

## Consequences

**What this buys.** The reliability the Android app exists for, on the majority of phones, delivered by
an OS-resident distributor rather than an app the OEM kills - and it is reversible: if FCM is ever cut,
RuStore already covers every device, and the selection rule degrades to "RuStore everywhere" by a
single availability check returning false.

**What it costs, stated plainly.**

- **A Google dependency is back for the majority of devices** - the exact thing `adr/0180` set out to
  avoid. `personal-data.md`'s destinations table now needs **both** rows: the VK/RuStore row `adr/0180`
  added *and* the Google/FCM row `adr/0179` designed, because a real deployment now sends to both.
  Both read differently from every other row for the reason both prior ADRs give: the subject is an
  **operator**, so by `adr/0076` AGO is the controller and each transfer is AGO's own decision.
- **The residency question `adr/0180` routed around is open again**, and this time it cannot be routed
  around: FCM is a Google destination, `personal-data.md`'s default is "in Russia", and this is a
  deliberate move out of that default. It is the author's to ask, in writing, and it is a precondition
  on the implementation item, not on this design. The mitigation `adr/0179` took stands and is
  unchanged: no message body, no visitor identity beyond a truncated pseudonym, no conversation
  content - the same minimal payload crosses whichever transport carries it.
- **A Firebase project and its two artifacts must exist and be held.** A `google-services.json` for
  the app and a service-account key for the Worker - the author creates the project (implementation is
  blocked until it exists), and `secrets.md` + `tools/secrets-audit.sh` gain `FCM_SERVICE_ACCOUNT_JSON`
  in the same change, or the audit fails, which is what it is for. FCM's own service account can hold
  two keys at once, so its rotation class is **Draining** - better than RuStore's **Restart**, the one
  axis where the returning credential is easier than the one it joins.
- **FCM carries its own geopolitical risk** - it is foreign infrastructure that could be curtailed. It
  is mitigated, not eliminated, precisely by keeping RuStore: the fallback is not dead weight, it is the
  standing answer to FCM being cut, which is the whole reason this is FCM-primary-with-RuStore rather
  than FCM-only.
- **Two of everything to maintain.** Two `IPushSender` implementations and a resolver; two client
  messaging services (`FirebaseMessagingService` and RuStore's) feeding one `IncomingPushRouter`; two
  gateways behind one `PushRegistrationGateway`; two credentials the Worker needs and two host
  reachabilities (`fcm.googleapis.com`/`oauth2.googleapis.com`) to establish by `adr/0070`'s method,
  in addition to `vkpns.rustore.ru`. The duplication is bounded - one extra provider, not a framework -
  and it is the direct price of covering both device populations.

## Alternatives considered

**RuStore only (the status quo, `adr/0180`).** Rejected on the live evidence above: it is unreliable on
exactly the OEM ROMs a Russian market ships, its distributor is killed by the OS, and it reaches no
de-Googled phone at all - the failure this item exists to remove. It remains the right *fallback*, which
is why it is kept, not deleted.

**FCM only.** The simplest two-repo change and the most reliable transport on stock Android. Rejected
because it drops every device without Google Play Services - de-Googled ROMs, Huawei, the RuStore-only
phones `adr/0180` §5 enumerated - and because it puts the product's single delivery guarantee behind
one foreign service with no domestic standby. Keeping RuStore as the fallback costs one already-built
adapter and buys both coverage and a hedge.

**RuStore's Universal Push (server `vkpns-universal` API, or the client universal SDK), fanning one
request through RuStore + FCM + HMS.** Genuinely attractive: one integration, and it is the iOS answer
`adr/0178` foresees. `adr/0180` rejected it for putting the Google destination back conditionally and
invisibly - but this ADR *decides* to put FCM back, so that objection is spent. It is still rejected
here, on two grounds `adr/0180` also named. First, control and visibility: the server must know which
transport a device actually uses to route, observe and revoke by `provider`, and a universal fan-out
hides that behind a single opaque call - the explicit per-device `provider` this design keeps is what
makes a dead-token revocation and the `ago.chat.push.*` metrics mean anything. Second, credential
custody: RuStore's own docs state each provider's credentials travel **in the request body** and are
not stored, so the Worker would hold the Google service account regardless - no saving over doing FCM
directly - while also pulling in HMS this stage does not want. The clean seams already built
(`IPushSender` + `provider`, `PushRegistrationGateway`) make two explicit transports cheaper to reason
about than one opaque one. Named as the reopening point if maintaining two adapters proves worse than
expected, or when iOS arrives.

**HMS (Huawei Push) now.** Out of scope, not rejected on merit - a third transport for real Huawei
operators, additive behind the same port and column whenever it is wanted.

**Answer the residency legal question and stay RuStore-only.** The honest alternative `adr/0179` and
`adr/0180` both named. It does not fix the reliability failure this item is about - a legally-blessed
RuStore is still killed by MIUI - so it is not an answer to *this* question, though the question it
does answer still has to be answered, now, because FCM is a Google destination either way.
