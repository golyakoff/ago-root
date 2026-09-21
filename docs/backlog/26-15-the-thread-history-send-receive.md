# 26-15 · The thread: history, send, receive

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21. This item is where `plan.md`'s Phase 0 becomes true or does not: "sign-in →
  conversation list → open a thread → send a message → watch it arrive on the console. One vertical
  slice, end to end, over the real transport. **Nothing else ships until this does.**"
- **Verified**: 2026-09-21 — `ago-console/src/realtime/protocol/dedup.ts` exports `SeenMessageIds`
  (inbound dedupe by message id) and `newClientMessageId` (the outbound id), with the file's own
  comment citing `realtime.md`'s Client protocol section. Those are the two mechanisms this item
  ports, by name.
- **Depends on**: `26-14`.

## What this item is

An operator reads a conversation, answers it, and sees the reply arrive — over the real transport,
against the real backend. One promise, and it is Phase 0's whole proof.

## Scope

- **The message list ordered by `sequence`**, with keyset history paging upward. Never a timestamp
  ordering, never a client-side sort that could disagree with the server's own (`CLAUDE.md` rule 6).
- **The composer, whose draft survives leaving the screen.** This is not a nicety: it is the exact
  loss `11-06` restructured the console to prevent, and `navigation.md`'s back-button contract states
  it as a guarantee — "back never discards a composer draft silently".
- **Send with a `clientMessageId`**, and **de-duplication on both sides**: by that id on the way out,
  by message id on the way in. At-least-once delivery is assumed everywhere (`CLAUDE.md` rule 5), and
  `dedup.ts` already implements both halves in the console — this is a port, not an invention.
- **Receiving the visitor's reply live** over the hub connection `26-13` owns.
- **Back returns to the list keeping its scroll position and its filters** (`navigation.md`).
- **The visitor chip in the app bar**: present, and either inert until the visitor context sheet lands
  or absent until then. **Pick one and say which** — a chip that does nothing when tapped is worse
  than no chip, and a chip that appears later is a layout change nobody expects.
- **No paperclip.** The attach control is conditional on the open conversation's
  `hasAttachmentUploadGrant`, attachments are a later item, and drawing a disabled one would advertise
  a capability to somebody who will never use it — the hide-rather-than-disable posture
  `AttachmentUploadGrantToggle` already states for itself (`navigation.md` §"The attach control").

## Out of scope

- **Attachments** — the upload grant, the presigned URL, the WorkManager upload. Their own item, and
  `navigation.md` flags one product question that should be answered before that item starts (whether
  an operator may always attach while a visitor may only when granted).
- Canned responses (`/` in the composer), close, claim from within the thread, tags, notes.
- The visitor context sheet — a later-wave item, not yet numbered.
- Search and jump-to-hit.

## Done when

- [ ] **Phase 0's end-to-end proof, recorded with the date it was actually observed**: an operator
      signs in on a real phone, opens a thread, sends a message, and it appears in `ago-console` on a
      desktop; a visitor's reply appears on the phone without a refresh.
- [ ] A send retried after a dropped connection produces **exactly one** message — the
      `clientMessageId` path, proven rather than assumed.
- [ ] A redelivered inbound message renders once.
- [ ] Leaving the thread with a non-empty composer and returning restores the draft, including after
      the process is killed and restored.
- [ ] History pages upward without duplicating or dropping a message at a page boundary — the
      keyset boundary is where this goes wrong, so test it there specifically.
- [ ] Back returns to the list with its scroll position intact.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
