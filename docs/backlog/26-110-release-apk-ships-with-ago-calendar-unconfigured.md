# 26-110 · The release APK ships with AGO Calendar unconfigured, so «Записи» is empty though Calendar is deployed

- **Stage**: 26
- **Status**: done — confirmed on a reinstalled APK by the author 2026-09-25 (Записи loads the booking, Услуги and Часы). Was: the CI release step now passes `-PagoCalendarApiBaseUrl=https://calendar-api.reserve-me.ru`; the main `publish-apk` run for the merge succeeded, so the published APK carries the calendar origin. Stays open until the author confirms on a reinstalled APK that Записи loads real data.
- **Found**: 2026-09-25, by the author, live on a real phone: the Записи (Bookings) screen shows nothing
  on the stand release build even though a booking exists for the account, the schedule is set, the
  masters/services are configured, and `Ago.Calendar.Api` is deployed on the stand with the data.

## What is actually true today, confirmed against the real code and deploy

- The bookings screens (`ago-android`, `app/.../bookings/**`) are built and merged — «Ожидают»
  (`26-48`), «Утверждены» (`26-51`), «Клиенты» (`26-52`), «Услуги» (`26-96`), «Часы» (`26-97`), the veto
  actions (`26-49`), phone reveal (`26-53`/`26-74`), the «Все» segment (`26-90`) — each with a real
  `ViewModel` and a real network adapter (`KtorBookingsApi`, `KtorWorkingHoursApi`).
- Those adapters query **`Ago.Calendar.Api`** (a separate product, not `ago-chat`):
  `GET /api/v1/console/pending-bookings`, `/confirmed-bookings`, `/contacts`, `/configuration`, etc.
- `Ago.Calendar.Api` **is deployed on the reserve-me.ru stand** — `ago-deploy` ships
  `k8s/base/calendar-api.yaml` and the demo overlay pins the calendar images; its public origin is
  `https://calendar-api.reserve-me.ru` (live).
- The adapters take `calendarApiBaseUrl: String?`. `null` means "this deployment does not run AGO
  Calendar" → they return `NotConfigured` immediately, **zero requests made**, and the screen renders
  its empty/unconfigured state.
- `OidcConfig.calendarApiBaseUrl` comes straight from `BuildConfig.AGO_CALENDAR_API_BASE_URL`
  (`di/AppModule.kt`), with no runtime override. That BuildConfig field is
  `agoOptionalProperty("agoCalendarApiBaseUrl")` — **optional, with no committed default on purpose**
  (unlike `chat-api.reserve-me.ru`, which is baked): "AGO Calendar is a second product a given
  deployment may genuinely not run yet ... a build that wants the value set passes
  `-PagoCalendarApiBaseUrl=<url>`" (`app/build.gradle.kts`'s own comment).
- **The `ago-android` CI `Assemble release APK` step never passes `-PagoCalendarApiBaseUrl`.** So the
  published APK is built with `AGO_CALENDAR_API_BASE_URL = null` → every bookings call returns
  `NotConfigured` → the screen is empty regardless of the data on the backend.

So this is neither "the screens were not built" nor "there is no data" — it is a build-config gap: the
release build never tells the app where AGO Calendar lives.

## The decision (why a CI `-P`, not a committed default)

Baking a default into `app/build.gradle.kts` (as the chat URL is) was considered and rejected: the file
deliberately keeps this one defaultless because a deployment may not run Calendar, and the sanctioned
mechanism is exactly "the build that wants it set passes `-P`". The `ago-android` CI release build IS
that build — it targets the reserve-me.ru stand, which runs Calendar — so it should pass the flag, while
a hypothetical other deployment's build still gets `null` without it. This keeps the documented design
and fixes the actual gap.

## Scope

- Add `-PagoCalendarApiBaseUrl=https://calendar-api.reserve-me.ru` to the `Assemble release APK` gradle
  invocation in `ago-android`'s `.github/workflows/ci.yml` (the step that already passes the version and
  signing `-P` flags).
- Only the published/release APK needs it; the debug `assembleDebug` in `build-test` is not the shipped
  artifact.

## Out of scope

- A committed default in `app/build.gradle.kts` (rejected above).
- Any change to the bookings screens themselves or to `Ago.Calendar.Api` — both already work; this only
  points the app at the deployed backend.

## Done when

- [x] The CI release build passes `-PagoCalendarApiBaseUrl=https://calendar-api.reserve-me.ru`; the
      published APK's `AGO_CALENDAR_API_BASE_URL` is that origin (not empty). Verified locally via
      `generateReleaseBuildConfig` with the flag; the main `publish-apk` run for the merge succeeded.
- [x] Verified on a real phone: the Записи screen loads the real booking(s)/services/hours from
      `Ago.Calendar.Api` instead of the empty state. Confirmed by the author 2026-09-25.
