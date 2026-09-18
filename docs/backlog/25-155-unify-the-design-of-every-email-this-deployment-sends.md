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
