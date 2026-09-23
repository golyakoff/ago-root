# 26-59 · A network failure shows the operator a Java class name, and possibly the API hostname

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ago-android` `main` at `b099282` — every path that turns a caught
  exception into on-screen text.

## Found

Four files each carry their own private copy of the same one-line function, and every one of them
feeds an operator-visible string:

```kotlin
private fun Exception.describe(): String = "${this::class.simpleName}: ${message ?: "no detail"}"
```

So an operator on a train with no signal is told, in the app's own error colour,
`UnknownHostException: Unable to resolve host "chat-api.reserve-me.ru": No address associated with
hostname`. Two things are wrong with that sentence and they are not the same wrongness:

1. **It is not a sentence anybody can act on.** It names a Java class. The operator's actual question
   — "is it me, or is it broken?" — goes unanswered, and there is no wording anywhere in the app that
   says "нет сети".
2. **It can contain the deployment's hostname.** `26-45`, `SignInScreens.kt:117-121` and
   `scope-inventory.md` §11 all state the same rule from three directions: this app names no
   deployment, and "whoever has the app should be able to forget `office.reserve-me.ru` exists". The
   sign-in screen was carefully built to obey that — and then the first failed call prints the API
   host on the screen right next to it, through
   `R.string.routing_unavailable_transport` (`SignInScreens.kt:324`), before the operator is even
   signed in.

## What is actually true today, confirmed against real code

Four copies, all identical:

- `core/network/.../conversations/KtorConversationsApi.kt:88`, reached at `:37`, `:52`, `:68`
- `core/network/.../identity/KtorIdentityApi.kt:122`, reached at `:48`, `:64`, `:104`
- `core/network/.../permissions/KtorOperatorPermissionsApi.kt:59`, reached at `:38`, `:54`
- `app/.../thread/ThreadViewModel.kt:336`, reached at `:156` and `:193`

Where each one lands on screen:

- `QueueResult.Failed(...)` → `ConversationListUiState.loadError` → drawn raw in `error` colour,
  `ConversationListScreen.kt:204-211`.
- `ClaimResult.Refused(...)` → the per-row claim error, `ConversationListScreen.kt:632-647`. Note
  this one is worse than the others: a genuine server refusal (RFC 7807 `detail`, a real sentence)
  and a transport failure arrive through the *same* field, so the screen that renders a refusal
  correctly also renders a class name identically.
- `ProbeFailure.Transport`/`Malformed` → `routing_unavailable_transport`/`_malformed`,
  `SignInScreens.kt:322-326`.
- `historyError` → `JoinErrorBody` (`ThreadScreen.kt:270-288`) and the load-older banner
  (`ThreadScreen.kt:355-359`).

There is also a non-transport status form in the same neighbourhood: `"http.${status.value}"`
(`KtorConversationsApi.kt:41`, `:84`), which reaches the operator as the literal string `http.503`.

The app already knows how to do this properly elsewhere:
`SignInScreens.kt:304-315`'s `describe(failure)` maps a `RoutingFailure` onto one of three real
Russian sentences naming *which question* went unanswered, and that whole arm exists because `11-17`
decided one sentence for three different problems was not good enough.

## Scope

One promise: **a failure this app cannot explain never puts an exception class or a hostname on the
screen.**

1. **One shared classification**, in `:core:domain` — a small sealed type distinguishing at least "no
   network", "the server answered with a status", and "something else went wrong" — replacing all
   four `describe()` copies. `:core:domain` because it is a plain mapping with no Android or Ktor
   dependency, and because every adapter and every view model needs the same answer; the alternative,
   a fifth copy in each new API client, is exactly how there came to be four.
2. **Rendering lives in `:app`**, as string resources. `:core:domain` classifies; only the UI layer
   turns a classification into Russian. A network adapter must never hold a user-facing sentence —
   that is the same reason the refusal `detail` comes from the server rather than from
   `KtorConversationsApi`.
3. **A server-supplied refusal keeps its own text, verbatim.** `ClaimResult.Refused` must stop
   carrying transport failures at all: those are a different outcome and the row needs to tell them
   apart to render them differently (a refusal is final; a transport failure is worth retrying).
4. **Nothing renders `this::class.simpleName` or an exception `message` anywhere.** A test that greps
   the source for the old shape is cheap and is the only thing that stops a fifth copy appearing with
   the next API client (`26-48`, `26-54` and `26-55` each add one).
5. The raw detail may still be *logged* — but this neighbourhood is under a stated no-logging rule
   (`AgoAuthSession`, cited at `MainActivity.kt:116-119`), so the honest answer is probably "not at
   all", and the item should say which it chose.

## Out of scope

- Retry affordances. Whether an error is *recoverable* is `26-60`; this item is only about what the
  words say.
- The hub's own `SendMessageResult.Refused` (`OperatorHubConnection.kt:258`), which already prefers
  the server's message and falls back to a class name only for a non-hub exception while still
  connected. Worth fixing by the same mechanism if it falls out; not what this promise is about.

## Done when

- [ ] Putting a real device into airplane mode and opening the app produces a stated Russian sentence
      on every screen that can fail — sign-in, the conversation list, the thread — and no class name
      anywhere.
- [ ] No API hostname appears on any screen in that state.
- [ ] A `503` from the server renders as something other than `http.503`.
- [ ] A genuine claim refusal still renders the server's own `detail`, unchanged.
- [ ] All four `describe()` copies are gone, and a test fails if one comes back.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
