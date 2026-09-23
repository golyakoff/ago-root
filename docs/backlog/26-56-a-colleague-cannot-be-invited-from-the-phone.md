# 26-56 · A colleague cannot be invited from the phone, where sending the link is easiest

- **Stage**: 26
- **Status**: ready
- **Depends on**: `26-55` (the Люди roster this action lives on)
- **Found**: 2026-09-23, reading `ago-console/src/pages/OperatorsTeamPage.tsx` and
  `ago-console/src/api/operatorTeamApi.ts` against `ago-android` `main` at `b099282`, with the
  approved mockup Artifact ("AGO Chat для Android", `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own
  graph: `People -- "Пригласить" --> InviteSheet`, and
  `InviteSheet -. "Поделиться" .-> Share["Системная шторка Поделиться"]`.

## Found

This is the one screen in the whole port where the phone is **better** than the console, and the
mockup says why in its own graph: the console's invite dialog ends in a copy-to-clipboard button
(`OperatorsTeamPage.tsx:127`, "the link's own 'copied' confirmation"), because a browser has nowhere
to send a link to. A phone does. The actual goal of creating an invite is getting the link to a
person, and Android's share sheet is that, in one tap, into whichever messenger the colleague already
uses.

`scope-inventory.md` §6 states it as the port's own judgement: "strictly better than the console's
copy button, since sending the link is the actual goal."

## What is actually true today, confirmed against real code

- The call: `createOperatorInvite(token, siteId, roleName, email)` (`operatorTeamApi.ts:142-152`),
  `POST /api/v1/sites/{siteId}/operator-invites`.
- Its response is the one place the plaintext code ever exists —
  `CreateOperatorInviteResponseDto { operatorInviteId, code, expiresAt, sendFailed }`
  (`:61-72`), whose comment records the rule: the code is "shown exactly once". **That makes this a
  screen with a one-shot secret on it**, and losing it to a rotation, a background, or a stray back
  press means the invite has to be revoked and re-created.
- `sendFailed` is a real, separate outcome (`:64-71`): Keycloak's realm relay failed at the SMTP
  layer, the invite **still exists**, and the dialog shows a warning rather than treating the create
  as failed. A port that renders `sendFailed` as an error would have an administrator revoke a
  perfectly good invite.
- `email` is required server-side and a bad one comes back as `OperatorInvite.InvalidEmail` (`400`,
  `:139-141`) — a refusal to surface verbatim, not a client-side validation to reimplement.
- The role is one of exactly two names, already constants: `ROLE_OPERATOR` / `ROLE_ADMIN`
  (`operatorTeamApi.ts:136-137`).
- The seat pre-flight the console runs before offering the button is **not** the same predicate as
  `overLimit`: `operatorTeamApi.ts:39-45` spells out that the invite-time check is `heldSeats >= limit`
  ("at capacity"), while `overLimit` is `heldSeats > limit`. `26-55` reads the second; this item needs
  the first, computed from the same `heldSeats`/`limit` the summary already carries.
- Android has nothing: `PlaceholderScreens.kt:57-62`.

## Scope

One promise: **an administrator can invite a colleague from the phone and hand them the link.**

1. `createOperatorInvite` on the `OperatorTeamApi` port `26-55` introduces.
2. A bottom sheet from Люди: an email field, a role choice between the two real role names, and a
   submit. The at-capacity check for the chosen role runs before submit, from the summary already in
   hand, using `heldSeats >= limit` and saying so — not `overLimit`.
3. **The result sheet keeps the one-shot code alive.** It survives a rotation and a process death
   (`rememberSaveable`, the same mechanism `ConversationsTabHost.kt:51` already relies on for the open
   conversation), and it does not close on an outside tap — losing a code that cannot be shown again
   to a stray gesture is the failure this screen must not have.
4. **The primary action is the Android share sheet** on the invite URL, not a copy button. A copy
   action may sit beside it; it is not the primary.
5. `sendFailed` renders as a warning on a created invite, never as a failure. `InvalidEmail` and every
   other refusal render the server's own message.

## Out of scope

- **Revoking an invite, and the invite list.** `listOperatorInvites`/`revokeOperatorInvite`
  (`operatorTeamApi.ts:157`, `:164`) are a separate screen answering a separate question ("what is
  outstanding"), and they are its own item.
- **The seat toggle, role change and removal** on an existing operator. Each is a write against a
  colleague's access with its own confirmation; none of them belongs in an item about invites.
- **The invite App Link** (`/invite/:code` opening the app rather than the console,
  `scope-inventory.md` §1). That is the *recipient's* side and a manifest/intent-filter change; this
  item is the sender's side and shares only a URL string with it.

## Done when

- [ ] An administrator creates an invite from the phone and sends the link through the system share
      sheet.
- [ ] Rotating the device while the created-invite sheet is open still shows the same code.
- [ ] An invite created with `sendFailed: true` is presented as created-with-a-warning, and the
      invite is confirmed present in the console's own invite list afterwards.
- [ ] A malformed email shows the server's own refusal; no client-side email regex exists in the
      change.
- [ ] Inviting into a role already at capacity is refused before the call, naming the role.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked end to end on a real device: invite created on the phone, link shared, redeemed in a
      browser.
