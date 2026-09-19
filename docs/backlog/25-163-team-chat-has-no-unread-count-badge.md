# 25-163 · "Общение" (team chat) carries no unread-count badge, unlike "Мои"

- **Stage**: 25
- **Status**: code merged — `ago-console#258`
- **Found**: 2026-09-19. The console's "Диалоги > Мои" nav item already shows an unread-message-count
  badge (`consoleNav.ts`'s `buildTalkItems`, `badge: badgeFor(unreadCount, strings.queueUnreadMessageOne,
  strings.queueUnreadMessageOther)`, landed by `25-51` deliberately only on "Мои", never "Все
  диалоги"/"Поиск"). "Команда > Общение" (`TeamChatPage`, `navTeamChat`, wired unconditionally in
  `consoleNav.ts` by `23-32`) has **no badge parameter at all** on its own nav entry - an operator with
  unread team-chat messages gets no equivalent visual signal.

## Scope

- Give "Общение" the same badge treatment "Мои" already has: a new unread-count source for team chat
  (confirm whether `TeamChatPage`'s own data layer already tracks an unread count anywhere, or whether
  this needs its first one - team chat is operator-to-operator, a different data source from visitor
  conversations, so `25-51`'s own `unreadCount` plumbing cannot be reused as-is, only its pattern).
  Wire it into `consoleNav.ts` the same way `buildTalkItems` takes `unreadCount` today - most likely a
  new parameter on whatever builds the team/people section, following `badgeFor`'s existing helper
  rather than inventing a second badge shape.

## Out of scope

- Any other team-chat feature or notification channel (e.g. desktop/push notifications) - a nav badge
  only, mirroring what "Мои" already has.

## Done when

- [x] "Общение" shows an unread-count badge in the nav when there are unread team-chat messages, using
      the same `badgeFor` shape "Мои" already uses, proven by `TeamChatUnreadProvider.test.tsx` and
      `consoleNav.test.ts`
- [x] The badge clears when the page is open, proven by `TeamChatUnreadProvider.test.tsx`'s own
      clear-on-open case
- [x] "Мои"'s own existing badge test still passes unchanged, proven by `consoleNav.test.ts`

## Outcome

Merged 2026-09-19: `ago-console#258` - `TeamChatUnreadProvider`/`TeamChatUnreadContext`, the sole owner
of `OperatorConnection.onTeamMessage` (previously a single-listener setter `TeamChatPage` called
directly; now fans pushes out to subscribers so it can also own the badge). Excludes the operator's own
echoed sends via a new `operatorId` field on `PermissionsState` (already on the wire from
`/operators/me`, never surfaced before). Wired into `consoleNav.ts`'s `buildTeamItems` via a third
`buildTenantNavSections` parameter; `OperatorShell` reads it through a tolerant
`useTeamChatUnreadBadge()` (0 with no provider) so existing shell-only test harnesses keep passing
unchanged. Rebased cleanly onto `25-160`'s merged `EmailChannelPage` nav entry - both touch
`consoleNav.ts`/`i18n`/`App.tsx` but in disjoint regions. 141 files / 1528 tests, independently
re-verified by the managing session, matching counts exactly.
