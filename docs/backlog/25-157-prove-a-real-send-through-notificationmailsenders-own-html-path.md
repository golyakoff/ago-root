# 25-157 · Prove a real send through NotificationMailSender's own HTML path

- **Stage**: 25
- **Status**: closed - not planned, decided by the author, 2026-09-19
- **Found**: 2026-09-19, closing out `25-155`. That item's own Done-when list asked for "a real send"
  proving `InactivityWarningMailTemplate`, `DownloadThresholdWarningMailTemplate` and
  `OperatorInviteCodeMailTemplate` all render through the shared HTML shell in production - `25-155`
  itself only proved this against a real SMTP round-trip in a test (`NotificationMailSenderTests`, a
  genuine `FakeSmtpServer` TCP connection), and separately proved the *Keycloak-native* invite flow in
  production (Lane B, verified live against `a@golyakov.net` in both locales). It never proved
  `NotificationMailSender`'s own path against production mail infrastructure.
- **Depends on**: `25-155` (merged - `ago-chat#334`, `ago-deploy#233`).

## Why this is split rather than left inside `25-155`

The one remaining promise needs a real trigger - a real operator invite (for `OperatorInviteCodeMailTemplate`),
or a site genuinely crossing the inactivity/download-threshold conditions the two watchdog jobs check for
(for the other two templates). Every such trigger this session could reach either targets a real tenant's
own operators (an unwanted email landing in a real inbox) or needs a full authenticated owner/console
session this session did not have in hand. Rather than force one of those paths carelessly against live
data, or leave `25-155`'s own Done-when list carrying an unsettled box, the live-verification step is its
own item - the same "unfinished work gets a number of its own" rule this repository already follows.

## What this item is

Prove, against real mail infrastructure, that at least one of the three `NotificationMailSender` templates
renders through `Ago.Chat.Application.Emailing.EmailHtmlShell` as intended - the same bar `25-155`'s Lane B
already cleared for the Keycloak-native flows. The safest real trigger is probably a genuine operator
invite created for a test account this session controls (the same `a@golyakov.net` test user `25-73`/`25-155`
already use), rather than waiting for a real site to cross an inactivity or download threshold naturally.

## Done when

- [-] At least one of `InactivityWarningMailTemplate`, `DownloadThresholdWarningMailTemplate` or
      `OperatorInviteCodeMailTemplate` is proven to render through the shared HTML shell by a real send,
      landing in a real inbox this session (or its author) controls - no real tenant's own operator is
      the recipient
- [-] The received email is visually confirmed - plain-text part unchanged from what shipped before
      `25-155`, HTML part rendering the shared shell correctly

## Outcome

Not planned - decided by the author, 2026-09-19. The author confirmed a real send from the *Keycloak*
side of `25-155` (the invite action-email, live against `a@golyakov.net`, matching this same HTML shell)
and judged that, combined with `NotificationMailSenderTests`'s own real SMTP-protocol round-trip already
proving `NotificationMailSender`'s multipart path end-to-end, a second, separate live send through this
specific sender was not worth the extra live-tenant setup this item's own scope required to do safely.
No code changed; nothing here was left half-finished - the decision is that the remaining gap does not
need closing.
