# ADR-0178: The Android client is standalone native Kotlin, and `ago-mobile-common` is not created yet

- **Status**: Accepted
- **Date**: 2026-09-21
- **Stage**: 26

## Context

Stage 26 opens a native Android operator client for AGO Chat, in a new repository `ago-android`
(`26-00`). The author intends a native iOS client after it. That second, stated-but-unbuilt consumer
is what forces a decision now rather than later: the question "how much do the two mobile apps
share" is cheap to answer before either exists and expensive to answer once one of them has twenty
thousand lines.

Three facts about the current system constrain the answer, and all three were read from the code
rather than assumed.

**There is no OpenAPI description of the API anywhere.** No `AddOpenApi`, no `MapOpenApi`, no
Swashbuckle, no NSwag, in `ago-chat`, `ago-platform` or `ago-calendar`. Both existing clients
hand-write their wire types from `Ago.Chat.Contracts` and say so
(`ago-console/src/realtime/protocol/types.ts`: "it exists so the rest of the console never guesses
field names"). So the cheapest and most commonly proposed shared layer — *generated* API models and
a generated client — is not an option that exists today. Creating it means a 236-endpoint annotation
pass across the two .NET hosts that actually serve a public contract (`Ago.Chat.Api`,
`Ago.Calendar.Api` - confirmed by reading `ago-deploy/k8s/base`, not assumed from repository count),
which is a change to `ago-chat` that `26-00`'s own Out-of-scope forbids and which nobody has asked for
on its own merits.

**The realtime half of the product runs on SignalR, and its client library is not portable.**
Microsoft ships an official Java client (`com.microsoft.signalr:signalr`) which runs on Android
because Android is a JVM. Microsoft ships nothing for Swift or Objective-C. This matters more than
it first appears: the realtime layer is the largest, subtlest piece of client logic in the product
(reconnect with a token factory that must re-read the current token on every negotiate, per-conversation
ordering by server-assigned `sequence`, at-least-once de-duplication) and it is precisely the piece a
shared layer would be most valuable for — and it is also the piece whose *dependency* cannot be
shared, because a Kotlin Multiplatform `commonMain` source set cannot use a JVM-only library on an
iOS target. Sharing that layer means hand-writing a SignalR client over Ktor's WebSocket, which is
real, unestimated work.

**The client surface is large.** `ago-console` has 54 routes and roughly 8,000 lines of
hand-written API-client code across more than 40 modules. Whatever is shared or not shared is shared
or not shared at that scale, not at the scale of a couple of DTOs.

Against those, one rule this project already applies to itself repeatedly: **an abstraction with one
caller is a guess about the second one** (`clean-architecture.md`), and premature generalisation is
the named failure mode of a shared layer (`CLAUDE.md`). `adr/0027` refused a shared `Operator`
hoisted into `Ago.Platform.*` on exactly this ground, for exactly this kind of
"the-second-product-is-coming" argument.

## Decision

### 1. Android is a standalone native Kotlin/Compose application in `ago-android`

Jetpack Compose with Material 3, Ktor client, `kotlinx.serialization`, Microsoft's official Java
SignalR client, AppAuth for OIDC. It is a client of the existing public API on the same footing as
`ago-console` and `ago-widget`: it holds no domain logic the server does not own, invents no
permission, and requires no change to `Ago.Chat.*`.

It hand-writes its wire types from `Ago.Chat.Contracts`, the same way both existing clients do, and
for the same reason they do — there is nothing to generate from.

### 2. `ago-mobile-common` is **not** created

No third repository, no shared module, no published artifact. Today it would have exactly one
consumer, which by this project's own rule makes it a guess about the second.

### 3. The Android app is laid out so that sharing later is a build-file change, not a rewrite

Three Gradle modules: `:core:domain` (pure Kotlin JVM — no `android.*`, no `androidx.*`, no
`Context`), `:core:network` (wire types, HTTP, SignalR), and `:app` (Compose UI, Android framework,
and the only module where DI is wired).

`:core:domain` declares no Android Gradle plugin, so an Android import **does not compile**. That is
the same "make it impossible rather than merely forbidden" discipline `adr/0012` gives the platform's
package boundary, and it is what keeps the option genuinely open: converting a pure-Kotlin JVM
module into a KMP `commonMain` source set is a plugin swap and a directory move. The day that stops
being true is the day something in `:core:domain` reached for `Context`, and the build is what
prevents that day.

Two library choices are made with this in mind and cost nothing extra today: Ktor client over
Retrofit, and `kotlinx.serialization` over Moshi. Both are multiplatform; both are the equal of
their Android-only alternatives on Android.

### 4. Whether iOS shares any Kotlin at all is **explicitly not decided here**

It turns on a fact nobody has: whether a hand-written SignalR client over Ktor WebSockets is
acceptable in place of Microsoft's Java client, or whether iOS should take a community Swift SignalR
client and share nothing with Android but the wire contract. That is a measurement — of effort, of
protocol conformance, of reconnect behaviour under iOS backgrounding — and this project does not
invent numbers in place of measuring (`CLAUDE.md`).

**The trigger that reopens it** is the first real iOS screen. At that moment the choice is between
converting `:core:domain` and `:core:network` in place to KMP and consuming them from Swift, or
writing the second implementation in Swift. Nothing before that moment produces information that
would improve the answer, and everything after it does.

### 5. When sharing does become real, the default is a module, not a third repository

Stated now so the question is not reopened from zero. `adr/0012` makes the platform a separate
repository because a package boundary makes a forbidden dependency *impossible* and forces the API
to have a version — and records the price: "a change spanning platform and product costs two merge
requests, a version bump, and a package publish."

Nothing about iOS's correctness depends on it being unable to see Android code, so the first half of
that trade buys nothing here. The second half is paid on **every** feature, because two mobile apps
of one product change together far more often than a platform and a product do.

So `ago-mobile-common` earns its own repository only if a third consumer appears (a desktop client, a
KMP-based web client) or the two apps' release cadences genuinely diverge. Absent that, shared
Kotlin lives as a module in `ago-android`.

## Consequences

**What this buys.** The Android app ships without waiting on an OpenAPI programme, a hand-written
cross-platform SignalR client, or a repository whose only consumer does not exist. It uses the best
available library on each axis rather than the best portable one, except where the portable one is
already the best. And the cost of changing our mind is bounded by a Gradle plugin line rather than by
a port.

**What becomes harder.** When iOS arrives, any rule that lives in `:core:domain` and is *not*
converted to KMP gets written a second time in Swift — and two implementations of one rule drift.
This is a real cost and it is accepted knowingly: it is the same cost `adr/0027` accepted when it
chose two parallel `Operator` entities over one hoisted into the platform, and the same reasoning
applies (the duplication is visible and small; the wrong shared abstraction is invisible and large).

**What has to be maintained.** The no-Android-dependency property of `:core:domain` is load-bearing
for the whole option. It is enforced by the build, but a future contributor adding an Android
dependency "just for one thing" would be removing the decision rather than bending it — that is what
the module's own build file should say in a comment, and what a reviewer should refuse.

**One thing this decision does not make cheaper.** The app's most valuable behaviour — telling an
operator that a visitor is waiting while the phone is in a pocket — is a backend change, not a
client one: there is no push infrastructure anywhere in `Ago.Chat.*`. No client architecture makes
that free, and this ADR should not be read as having addressed it.

## Alternatives considered

**Kotlin Multiplatform from day one, shared domain and networking, native UI on each side.** The
most defensible alternative, and it loses on one fact rather than on principle: the shared layer's
most valuable member is the SignalR client, and the SignalR client is the one member KMP cannot
carry, because Microsoft's implementation is JVM-only. Adopting KMP now therefore means either
hand-writing SignalR immediately (unestimated work, for a second consumer with no date) or adopting
KMP for everything *except* the part that most justified it. Deferred rather than refused — §3 and
§4 exist precisely so this stays cheap to choose later.

**Compose Multiplatform for both apps, one UI codebase.** It loses on the requirement, not the
technology. The author asked for a **native iOS app**; Compose Multiplatform renders a Material
surface on iOS, which is by definition not that. Choosing it would be answering a question the
author did not ask.

**A generated API client shared between the two apps, from an OpenAPI spec.** There is no spec, and
producing one is a 236-endpoint annotation pass across two .NET hosts that this stage may not make.
It is also worth noting the obvious: this option is frequently proposed because it sounds free, and
here it is the *most*
expensive of the three, because it starts with backend work.

**A thin hand-written shared models layer only (no logic), published now.** The smallest possible
version of sharing, and the least useful: DTOs are the cheapest thing to write twice and the thing
the compiler catches fastest when they disagree. It would pay `adr/0012`'s two-merge-request tax for
the least valuable cargo.

**Creating `ago-mobile-common` empty now, to be filled later.** Rejected as the worst of both: it
commits to the repository boundary — the expensive, hard-to-reverse half — while deferring the only
thing that would tell us whether the boundary is right.

**A React Native or Flutter app reusing `ago-console`'s own code.** Nothing of the console is
reusable across such a boundary anyway (it is React DOM throughout), the SignalR and OIDC stories are
worse, and a web-shaped UI on Android is the outcome `26-00` explicitly set out to avoid.
