# 26-111 Android contact-detail panel — implementation slices

All Q1–Q8 decided (see `26-111-thread-contact-detail-panel.md` §5a). **No backend work, no migration** — every
endpoint exists. Much is already shipped: `26-114` (visitor-summary endpoint + past-dialogs widened off
channel-identity, ADR-0182), `26-115` (Android contact-details list+reveal / tags / notes clients), `26-116`
(Permission constants + emoji-pair name fallback). Remaining = a few client adapters + the panel UI.

Decided answers baked in: **Q1** name is plain display text (no pill, no "не подтверждено" caption, no
assessment); **Q2** «Ограничить» = single `block-visitor`, **reversible** (block/lift + is-restricted read);
**Q4** count excludes Pending/erased; **Q6** past dialogs read-only; **Q7** hide-not-disable per permission;
**Q8** notes count = list length fetched on open.

## Parallel-safe client adapters (new files; only `di/AppModule.kt` overlaps — one-line each, rebase touch-up)
- **26-143 (S-A)** visitor-summary client (`core/**/visitorsummary/*`) over `GET /conversations/{id}/visitor-summary` (first-seen + count). Dep: none.
- **26-144 (S-B)** visitor past-dialogs client — list (`GET …/visitor-history`, keyset) + open-one (**hub** method `GetVisitorHistoryConversationAsync` on `OperatorHubConnection.kt` — the one non-new-file touch; may split S-B1 list / S-B2 hub). Dep: none; serialize S-B2 against realtime edits.
- **26-145 (S-C)** restrict-visitor client — block (`POST …/block-visitor`), lift (`POST /visitor-restrictions/{visitorId}/lift`), is-restricted read (`GET /visitor-restrictions` membership). Dep: none.
- **26-146 (S-D)** conversation-actions client (new port, not on the queue port) — close (`POST …/close`), grant/revoke attachment-upload. Dep: none.

## UI assembly (serialize on the panel container + `thread/ThreadScreen.kt`)
- **26-147 (S-E)** bottom-sheet shell + open-from-thread affordance (gated `conversation:read`, hide) + header H1–H5 (H1–H3 from in-hand `ConversationSummary`, H4/H5 from S-A, name fallback from 26-116). **Must land before S-F…S-K.** Dep: 26-143.
- **26-148 (S-F)** КОНТАКТНЫЕ ДАННЫЕ section (fields, masked + «Показать»; Имя plain text, no caption). Dep: 26-147 (+ shipped 26-115 client).
- **26-149 (S-G)** tags section (chips + «+ метка» from site vocab; `conversation:tag`). Dep: 26-147.
- **26-150 (S-H)** «Заметки команды» row + notes sub-screen (count fetched on open; composer `conversation:note_write`). Dep: 26-147.
- **26-151 (S-I)** «Прошлые диалоги» row + read-only history open (reuse the message renderer, no composer/actions). Dep: 26-147, 26-144.
- **26-152 (S-J)** «Приём файлов от посетителя» toggle (reversible; granted-by caption; `conversation:attachment_upload_grant`). Dep: 26-147, 26-146.
- **26-153 (S-K)** «Закрыть диалог» + reversible «Ограничить»/«Снять ограничение» (confirm dialogs; close dismisses + returns to queue). Dep: 26-147, 26-145, 26-146.

**Serialization:** each S-F…S-K adds a section into the panel container + reads the panel VM; put each section in its own file under `thread/contactpanel/sections/` so they're near-parallel, but land S-E solo first, then S-F…S-K sequentially or in tight pairs (they share the container + VM). No migration lane.

## Launch order
1. Parallel: 26-143 (S-A), 26-145 (S-C), 26-146 (S-D) [+ 26-144/S-B if the hub touch is accepted]. 2. 26-147 (S-E) after S-A. 3. Sections after S-E, ordered by ready client (S-F/G/H immediately — clients shipped; S-I after S-B; S-J/K after S-D/S-C).

## Deferred placeholders (separate scope — coarse tickets, not sliced here)
- **26-154** Calendar readiness-chain hub (Android) «Может ли клиент записаться?» (`GET /booking-readiness`).
- **26-155** Masters drill-downs (Android): schedule template / slots / re-cut (calendar backend already exists).
- **26-156** Phone/email contact-detail **edit + assessment** on Android (console has it; shipped Android client is list+reveal only) — parity, out of the panel's scope.
