# 25-163 · "Общение" (team chat) carries no unread-count badge, unlike "Мои"

- **Stage**: 25
- **Status**: ready — reported live 2026-09-19, queued behind `25-161` and `25-162`
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

- [ ] "Общение" shows an unread-count badge in the nav when there are unread team-chat messages, using
      the same `badgeFor` shape "Мои" already uses, proven by a test
- [ ] The badge clears (or decrements) when those messages are read, proven by a test
- [ ] "Мои"'s own existing badge test still passes unchanged
