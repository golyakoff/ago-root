# 25-213 · The OIDC redirect receiver crashes without an AppCompat theme

- **Stage**: 25
- **Status**: done — `ago-android#21`
- **Found**: 2026-09-22, live, on a real physical phone — the first real sign-in attempt this
  deployment has ever had, and it crashed every single time.

## What is actually true today, confirmed against real code and a real crash

`26-12`'s own manifest comment reasoned that declaring `net.openid.appauth.RedirectUriReceiverActivity`
in `app/src/main/AndroidManifest.xml` would be "a second place for [the redirect] scheme to be
wrong", and left it entirely undeclared so AppAuth's own library manifest — which supplies the scheme
via the `appAuthRedirectScheme` placeholder — is the only place that activity is named at all. That
reasoning covered the scheme; it did not cover the theme, and the two are independent attributes of
the same merged manifest entry.

Extracting `net.openid:appauth:0.11.1`'s own `AndroidManifest.xml` shows AppAuth declares **two**
activities, and treats them differently:

```xml
<activity android:name="net.openid.appauth.AuthorizationManagementActivity" ...
    android:theme="@style/Theme.AppCompat.Translucent.NoTitleBar" />
<activity android:name="net.openid.appauth.RedirectUriReceiverActivity" android:exported="true">
    <intent-filter> ... <data android:scheme="${appAuthRedirectScheme}" /> </intent-filter>
</activity>
```

`AuthorizationManagementActivity` (launched first, to open the browser) ships its own theme and never
crashed. `RedirectUriReceiverActivity` (launched second, when the browser redirects back after
Keycloak sign-in) declares **no theme of its own**, so the merged manifest gives it this application's
own `android:theme="@style/Theme.AgoChat"` — which `themes.xml` declares as
`parent="android:Theme.Material.Light.NoActionBar"`, a plain platform theme, not a `Theme.AppCompat`
descendant. Both AppAuth activities extend `AppCompatActivity`, whose `onCreate` requires the latter
unconditionally.

**The crash, verbatim, from a real device (`adb logcat`, 2026-09-22)**:

```
java.lang.RuntimeException: Unable to start activity
    ComponentInfo{ago.chat.android/net.openid.appauth.RedirectUriReceiverActivity}:
    java.lang.IllegalStateException: You need to use a Theme.AppCompat theme (or descendant)
    with this activity.
	at androidx.appcompat.app.AppCompatDelegateImpl.createSubDecor(AppCompatDelegateImpl.java:846)
	...
	at net.openid.appauth.RedirectUriReceiverActivity.onCreate(RedirectUriReceiverActivity.java:49)
```

**Consequence**: every sign-in attempt on a real device crashed the instant the browser redirected
back — 100% of the time, since this activity is unconditionally on the OIDC happy path. `26-12`'s own
unit tests never exercise it: `PostSignInRouterTest`'s fake port has no Android `Activity` to launch
at all, so this was invisible to everything except a real device — exactly the gap `26-22` exists to
close, and exactly why closing it matters.

## Fix

Declare `RedirectUriReceiverActivity` in the app's own manifest with **only** a theme override — no
`intent-filter`, no `data`, so the scheme is still spelled exactly once, in the library manifest via
the existing `appAuthRedirectScheme` placeholder. The manifest merger unions the two declarations by
activity name; the app's theme attribute wins, the library's intent-filter is untouched.

```xml
<activity
    android:name="net.openid.appauth.RedirectUriReceiverActivity"
    android:theme="@style/Theme.AppCompat.Translucent.NoTitleBar" />
```

**Verified live, on the same real device, immediately after**: sign-in completed without a crash,
reached the conversation list, and a real message sent from the app on a real, existing widget
conversation (`golyakov.net`) was delivered and answered — see `26-22`'s own record of that session,
carried out from `26-15`.

## Out of scope

- `26-22`'s own remaining real-device proofs (this item only unblocks them; it does not perform them).
- Any other AppAuth manifest attribute — `AuthorizationManagementActivity` was already correct and is
  untouched.

## Done when

- [x] `RedirectUriReceiverActivity` carries an AppCompat-descendant theme, without a second
      declaration of the redirect scheme.
- [x] `./gradlew ktlintCheck lint assembleDebug` green.
- [x] Confirmed live, on a real physical device: sign-in survives the Keycloak redirect with no crash.

## Outcome

Landed as `ago-android#21`. One manifest attribute, on the one AppAuth activity that needed it. Found
and fixed within minutes of the first real-device sign-in attempt this deployment has ever had — a
crash unreachable from any of `26-12`'s existing tests, since none of them launch a real `Activity`.
