# 25-155 · Unify the design of every email this deployment sends

- **Stage**: 25
- **Status**: needs analysis — filed to hold the idea, not yet scoped for implementation
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

**Not yet decided how far this goes - this item's own first deliverable is a proposal, not a build**,
per the same "analysis first, decision recorded, then implementation" shape `25-138` used. At minimum,
scope should answer:

- **A shared visual identity across both kinds of email** - likely a simple HTML template (logo,
  accent color, consistent typography) that both `NotificationMailSender`'s own callers and a new
  Keycloak `emailTheme` can each render into, rather than two independently-designed looks.
- **The Keycloak `emailTheme` half**: `25-90`'s own Scope already investigated this mechanism in
  outline (a custom theme overriding `executeActions.ftl`/`executeActions-text.ftl` and friends,
  mounted the same way the existing `loginTheme` is, `emailTheme` set via `keycloak-realm-import.json`
  + `apply-realm-settings.sh`) - read that item's own text before re-deriving it. Real work: FreeMarker
  templates (HTML **and** plain-text - Keycloak sends both parts to every recipient) for every action
  type this deployment actually triggers (password reset, email verification, the invite action-token
  email), each in `en`/`ru`, verified against a real send in both locales.
- **The `NotificationMailSender` half**: does `SendAsync`/`NotificationMailMessage` grow an HTML body
  alongside (or instead of) plain text? Every existing caller (`InactivityWarningMailTemplate`,
  `DownloadThresholdWarningMailTemplate`, `OperatorInviteCodeMailTemplate`) would need updating to the
  new shared look - decide whether that happens in this item or is carried out as smaller follow-ups
  once the shared template exists.
- **Whether `EmailChannelAdapter`'s own visitor-facing conversation emails** (a different thing - an
  operator's actual reply, not a system notification) are in scope at all. They plausibly should stay
  exactly as plain as an ordinary conversation reads today; naming this explicitly rather than
  assuming either way is this item's own job.

## Out of scope

- Redesigning what any individual email *says* - this is about how they *look*, not their content or
  copy.
- A general-purpose email-templating library or vendor - this deployment's own two senders
  (Keycloak's theme mechanism, `NotificationMailSender`) are both already in hand; reach for a third
  system only if a concrete need appears that neither can meet.

## Done when

- [ ] Not yet defined - this item's own first deliverable is a scoped proposal (a shared visual
      identity, which emails it covers, HTML-vs-plain-text for each sender) handed back to the author
      as a decision, per this item's own Scope.
