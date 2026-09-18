# 25-155 · Unify the design of every email this deployment sends

- **Stage**: 25
- **Status**: done — both lanes merged and deployed live, 2026-09-19 (`ago-chat#334`, `ago-deploy#233`).
  One promise this item made - a real send through `NotificationMailSender`'s own path - could not be
  closed here without risking an unwanted email to a real tenant's operators, and is split into `25-157`
  rather than left as an unsettled box. See Outcome.
- **Found**: 2026-09-18, testing `25-73` live. The real invite-code-update email that reached
  `a@golyakov.net` is Keycloak's own stock plain-text template - no branding, no styling, nothing that
  reads as coming from this product. Separately, `25-90`'s own fallback invite-code email
  (`NotificationMailSender`/`OperatorInviteCodeMailTemplate`) is a plain-text multi-line string too -
  functional, never styled.
- **Depends on**: nothing technically, but reads `25-90`'s own investigation of Keycloak's email theme
  mechanism first (see below) rather than re-deriving it.

## What is actually true today

Two independent kinds of email this deployment sends, styled two different ways - which is to say,
neither is styled at all:

1. **Keycloak's own emails** (`execute-actions-email` and friends - password reset, email
   verification, the invite's own action-token email) use whatever `emailTheme` the realm has
   configured. Checked live, 2026-09-18: the `ago-chat` realm has no custom `emailTheme` set at all -
   it renders Keycloak's stock built-in template, plain text with no branding. (The realm does have a
   custom `loginTheme: "ago"`, mounted the way `ago-deploy/k8s/base/keycloak-theme/` already shows for
   the browser-rendered login pages - the identical mechanism, unapplied to email.)
2. **This codebase's own emails**, sent through `INotificationMailSender`/`NotificationMailSender`
   (`Ago.Chat.Infrastructure.Email`) - `InactivityWarningMailTemplate`, `DownloadThresholdWarningMailTemplate`,
   and `25-90`'s own `OperatorInviteCodeMailTemplate` all build a plain-text subject+body string with
   no HTML part, no shared visual identity, each composed independently.

## Every trigger, surveyed 2026-09-18

| # | Trigger | Sender | Subject (ru / en) | Content |
|---|---|---|---|---|
| 1 | Admin creates an operator invite | **Keycloak** (`execute-actions-email`, called from `Ago.Chat.Api`) | ru: «Обновление Вашей учетной записи» / en: "Update Your Account" | Password+profile action-token link, 7-day expiry - Keycloak's own stock template, uncustomized |
| 2 | Same event, `25-90`'s own second, independent channel | **`Ago.Chat.Api`** (`CreateOperatorInviteHandler` → `NotificationMailSender`) | «Резервный код приглашения AGO Chat» / "Your AGO Chat backup invite code" | Plain-text invite code, fallback |
| 3 | Visitor clicks "forgot password" on the hosted login page | **Keycloak** | Keycloak's own stock subject, uncustomized | Password reset link |
| 4 | Self-registration, email verification | **Keycloak** | Keycloak's own stock subject, uncustomized | Verify-email link |
| 5 | A site's operators have gone inactive, account nearing deletion | **`Ago.Chat.Worker`** (`InactivityWatchdogJob` → `NotificationMailSender`) | «Аккаунт {siteName} в AGO Chat будет удалён через {N} дн.» / "...will be deleted in {N} days" | Deletion warning to every operator email on the site |
| 6 | A site crosses its plan's download threshold | **`Ago.Chat.Worker`** (`DownloadThresholdWatchdogJob` → `NotificationMailSender`) | «...приближается к месячному лимиту скачиваний» / "...approaching its monthly download limit" | Overage warning, not yet a block |
| 7 | An operator replies in a conversation whose channel is Email | **`Ago.Chat.Api`/`Worker`** (`EmailChannelAdapter`, `14-09`) | Dynamic - the visitor's own thread subject | An ordinary threaded conversation reply - structurally different from 1-6, probably out of this item's own scope (see below) |

`Ago.Calendar.*` (API and Worker): sends no email at all, confirmed by search, not assumed.

## A starting mockup

`docs/backlog/25-155-email-template-mockup.html` - a real, standalone, cross-client HTML email built
2026-09-18 against `reserve-me.ru`'s own live light-theme tokens (read directly from the site, not
guessed): `--blue:#2F6CE0`, `--violet:#7C4DFF` (the logo mark's own gradient), `--ink:#0F1728`,
`--bg:#F4F6FB`, Onest for headings + IBM Plex Sans for body text - the identical pairing the landing
page itself uses. Table-based layout, every style inlined, MSO/VML conditionals for a real Outlook
desktop button and logo fallback, a hidden preheader, and a `max-width:600px` fluid card that
collapses to full width under 600px. Content shown is the operator-invite scenario (`25-73`/`25-90`),
written as a fill-in-the-blanks example rather than the only email this template could carry - the
same card shape (logo row, hero icon, heading, body copy, one CTA, a warm secondary note, muted
footer) should serve every trigger in the table above with different copy and a different icon/CTA
label. Open it directly in a browser to preview; a real send is the only way to confirm it survives
Outlook desktop's own Word rendering engine, which was designed for but not exercised against here.

## Scope

**Decided by the author, 2026-09-18** - two lanes, touching disjoint files, safe to build in parallel:

### Lane A - `ago-chat`: `NotificationMailSender` grows an HTML part

- **`EmailMimeMessageBuilder` is deliberately `text/plain`-only today** (`14-09`'s own scope cut,
  shared by `EmailChannelAdapter` and `NotificationMailSender` alike) - confirmed by reading the code,
  not assumed. Add a **new** build path (a new method/overload, e.g. `BuildMultipartAlternative`) that
  produces a real `multipart/alternative` body (`text/plain` part first, `text/html` part second - the
  order every mail client expects, so a client with no HTML support falls back cleanly), each part
  base64-encoded exactly like the existing single-part path already does. **Keep the existing
  plain-only method too** - do not delete or repurpose it; the new method is additive. Only
  `NotificationMailSender`'s own call site opts into it in this item.
- Build one shared HTML "shell" (logo row, hero icon, heading, body copy, one CTA, a warm secondary
  note, muted footer) matching `docs/backlog/25-155-email-template-mockup.html`'s own tokens and
  layout exactly - the same file this item's own mockup already is, not a fresh design.
- Rewire `InactivityWarningMailTemplate`, `DownloadThresholdWarningMailTemplate` and `25-90`'s own
  `OperatorInviteCodeMailTemplate` through the shared shell, each supplying its own heading/body copy/
  CTA - **in this item**, not deferred as a follow-up, since two of three otherwise stay unstyled and
  defeat this item's own point.
- **`EmailChannelAdapter`'s own visitor-facing conversation emails are explicitly out of scope here,
  carved into their own item.** The author's own reasoning, 2026-09-18: these should eventually be
  branded too, but with the **tenant's own** brand, not AGO's - a visitor emailing a shop expects that
  shop's identity in the reply, not "AGO Chat". That needs real design work this item's own shell does
  not answer (does a tenant have a logo today? checked: no - `Site` carries `WidgetPrimaryColorHex`
  and `Name` only, no logo image field), so it is `25-156`, not built here.

### Lane B - `ago-deploy`: a real Keycloak `emailTheme`

- `25-90`'s own Scope already investigated this mechanism in outline - read that item's text first.
  A new custom theme (the same `ago-deploy/k8s/base/keycloak-theme/` mounting mechanism the existing
  `loginTheme: "ago"` already uses, at `/opt/keycloak/themes/ago/email` instead of `.../login`),
  covering every Keycloak-native email this realm actually triggers (the invite's own
  `execute-actions-email`, the self-service password-reset flow, self-registration's email
  verification - `25-155`'s own inventory table names all three).
- FreeMarker templates, **both HTML and plain-text** for each (Keycloak sends both parts to every
  recipient - read Keycloak's own base theme templates, extractable from the running container or
  Keycloak's own public source, as the starting point rather than writing these from nothing), styled
  to the identical shell Lane A uses, in `messages_en.properties`/`messages_ru.properties`.
- `emailTheme: "ago"` added to `keycloak-realm-import.json`, applied via `apply-realm-settings.sh` -
  the exact mechanism `25-73`'s own `internationalizationEnabled` fix just used live, 2026-09-18.
- Verified against a real send, in both locales, for at least the invite email (the one this session
  already has a working live-test recipe for, from `25-73`).

## Out of scope

- Redesigning what any individual email *says* - this is about how they *look*, not their content or
  copy.
- A general-purpose email-templating library or vendor - this deployment's own two senders
  (Keycloak's theme mechanism, `NotificationMailSender`) are both already in hand; reach for a third
  system only if a concrete need appears that neither can meet.

## Done when

- [x] `NotificationMailSender` can send a real `multipart/alternative` email; `EmailChannelAdapter`'s
      own plain-text-only path is provably untouched (its own tests still pass unchanged)
- [x] `InactivityWarningMailTemplate`, `DownloadThresholdWarningMailTemplate` and
      `OperatorInviteCodeMailTemplate` all render through the one shared HTML shell - built and proven
      by a real SMTP round-trip in `NotificationMailSenderTests` (a genuine `FakeSmtpServer` TCP
      connection, not a mock). A real send through this path against production mail infrastructure is
      a separate promise, deliberately not attempted here against a real tenant's own operators -
      carried forward as `25-157`.
- [x] A custom Keycloak `emailTheme` renders the invite action-email, password-reset and
      email-verification flows in the same shell, in both `en`/`ru`, `emailTheme: "ago"` applied via
      `apply-realm-settings.sh`
- [x] At least the invite email verified against a real send in both locales, matching `25-73`'s own
      live-verification recipe
- [x] `EmailChannelAdapter`'s own visitor-facing conversation emails are confirmed unchanged - byte-
      identical output for the one path this item deliberately does not touch

## Outcome

Both lanes merged and deployed live to `reserve-me.ru`, 2026-09-19:

- **Lane A** (`ago-chat#334`, `eb7dc01`): `EmailMimeMessageBuilder.BuildMultipartAlternative`, the
  shared `Ago.Chat.Application.Emailing.EmailHtmlShell`, and all three `NotificationMailSender`
  templates rewired through it. Independently re-verified: `dotnet format`/`build`/`test` all clean in
  one run (Domain 750, Application 1426, FakeCrm 21, Architecture 52, Concurrency 89, Integration 1380 -
  0 failed), `EmailChannelAdapter.cs` provably untouched. Deployed and smoke-tested live (46/46).
- **Lane B** (`ago-deploy#233`, `737c597`): the `ago` Keycloak `emailTheme`, covering
  `execute-actions-email`/password-reset/email-verification. Deployed live, `emailTheme: "ago"` applied
  via `apply-realm-settings.sh` and confirmed on the running realm. Real send verified against
  `a@golyakov.net` in both locales (`ru`, then `en` via the test user's own `locale` attribute,
  restored to `ru` afterward) - both arrived as the new branded HTML, matching `25-73`'s own recipe.
- **A footer-copy bug caught before merge**: both lanes' shared shell, ported from this item's own
  mockup, originally claimed "replies are read." Every email either lane sends goes out from a fixed
  no-reply address (`notifications@{domain}` for Lane A - confirmed in `NotificationMailSender`'s own
  remarks; Keycloak's realm SMTP config for Lane B - confirmed live in `25-73`), so that claim was false
  advertising. Fixed in the mockup and both lanes' copy before either PR merged, to say only that the
  address can't receive replies.
- **A wrong drift fix caught and reverted**: `ago-deploy`'s own `deploy.sh` reported the deploy record
  disagreeing with the manifest for `ago-console` (recorded `904e1d3c`, manifest pinned `ea90a80`).
  Trusting that record without checking the live cluster, the manifest was bumped to `904e1d3c` -
  `apply-demo.sh`'s own rollback guard then correctly refused to apply, because the *actual* running
  image was still `ea90a80`. Reverted to match reality; the record/reality mismatch itself is
  unexplained and unrelated to this item - not investigated further here.
- One promise this item made - a real send through `NotificationMailSender`'s own path specifically
  (as opposed to the Keycloak-native flows Lane B covers) - was not closed here: doing so would need a
  real operator-invite flow against a real tenant, and this session had no safe way to trigger one
  without risking an email landing on a real tenant's own operators. Carried forward as `25-157`.
