# 26-15 · The thread: history, send, receive

- **Stage**: 26
- **Status**: done — `ago-android#20`; remainder carried out to `26-22`
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

- [~] **Phase 0's end-to-end proof, recorded with the date it was actually observed**: an operator
      signs in on a real phone, opens a thread, sends a message, and it appears in `ago-console` on a
      desktop; a visitor's reply appears on the phone without a refresh. **Carried to `26-22`** - no
      real authenticated session exists in this environment. This is the single most important box
      this item leaves open, named plainly rather than buried among the others.
- [~] A send retried after a dropped connection produces **exactly one** message — the
      `clientMessageId` path, proven rather than assumed. **Both halves independently confirmed, the
      live race carried to `26-22`**: the client always retries with the same `clientMessageId`
      (`SendMessageResult.OutcomeUnknown` keeps it rather than minting a fresh one), and the server's
      own dedup is real (`Conversation.AddMessage`: a repeated `clientMessageId` returns the original
      message, no new sequence assigned) - confirmed by reading that method directly. The actual
      two-write race has not been observed live.
- [x] A redelivered inbound message renders once - `MessageSubscription`'s own dedup (`26-13`),
      exercised again by this item's own tests.
- [x] Leaving the thread with a non-empty composer and returning restores the draft, including after
      the process is killed and restored - `RoomComposerDraftStore`, proven with a real SQLite
      instrumented test that closes and reopens the same database file, simulating process death.
- [x] History pages upward without duplicating or dropping a message at a page boundary — the keyset
      boundary is where this goes wrong, so test it there specifically. `ThreadViewModelTest` builds a
      fake hub reproducing `ConversationReadStore`'s own real SQL exactly (confirmed by reading that
      file directly: `sequence < @BeforeSequence`, descending, cursor = last item's sequence only on a
      full page) and proves a 151-message walk lands on exactly `1..151` with no boundary value
      duplicated or missing.
- [x] Back returns to the list with its scroll position intact - `rememberSaveableStateHolder`, the
      same primitive `NavHost` uses internally.
- [x] `./gradlew ktlintCheck lint test` green; counts reported. 124 tests (31 `:core:domain`, 57
      `:core:network`, 36 `:app`), 0 failures; ktlint clean.

## Outcome

Landed as `ago-android#20`. Ports the real hub contract - `OperatorHub.JoinConversationAsync`/
`GetHistoryAsync`/`SendMessageAsync`, confirmed against the real backend source, not assumed - into a
thread screen with keyset history paging, live receive over `26-13`'s hub connection, send with a
ported `newClientMessageId`, and a Room-backed composer draft that survives process death. The
visitor chip is absent (not inert) until the visitor context sheet exists; the attach control is
hidden unless `hasAttachmentUploadGrant` is true, carried from the already-fetched queue row rather
than a second network call.

**A real bug found and fixed during the implementing worker's own self-review**: an earlier draft
tied releasing the hub subscription to `DisposableEffect.onDispose`, which also fires on a plain
device rotation - wrongly wiping history on every rotation. Fixed: the release now fires only from
the real "leave" callback (the back button/gesture); `ON_STOP` only flushes the draft, which is
harmless on rotation. Confirmed in place by reading `ThreadScreen.kt`/`ThreadViewModel.kt` directly.

**Verified independently, beyond the implementing worker's own report, against the real backend
source** - every citation checked, all six confirmed exact: `OperatorHub.cs`'s three method
signatures and the real 4-argument `SendMessageAsync` call order; `ConversationReadStore.cs`'s real
keyset SQL; `Conversation.AddMessage`'s dedup mechanism; `ConversationSummaryDto.cs`'s
`HasAttachmentUploadGrant` field. Re-ran the full build myself, green; confirmed all 124 tests from
the real JUnit XML.

**Two boxes carried to `26-22`**: the end-to-end phone-to-console proof (this item's own single most
important remaining gap), and the live send-retry race (both halves independently confirmed, the
actual race unobserved).
