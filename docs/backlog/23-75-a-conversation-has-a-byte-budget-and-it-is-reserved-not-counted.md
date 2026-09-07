# a conversation has a byte budget, and it is reserved rather than counted

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. `5-13` did the per-file half.
- **Decision**: the author's, 2026-09-07 — 10 MB per file, **100 MB per active conversation**, the same
  in both directions.

## What exists and what does not

**Per file: 10 MB, and it is already real.** `AttachmentOptions.MaxSizeBytes` is 10 MiB, and since
`5-13` the exact declared length is signed into the presigned PUT, so MinIO answers
`403 SignatureDoesNotMatch` before accepting a byte. Two layers, verified against a real MinIO.

**Per conversation: nothing.** `file-storage.md` says the ceiling is *"per file and per conversation"*
— that sentence is false and has been since it was written. `CreateAttachmentHandler` compares one
declared size against one constant and nothing sums anything.

## The part that decides whether this works

**Bytes never pass through the API** — that is the whole point of presigned uploads. So a budget cannot
be *counted as it flows*; it has to be **reserved when the slot is issued** and released when the slot
is not used.

Counting on the client's "I uploaded it" callback fails the obvious way: ten presign requests arrive
together, each reads a budget with 100 MB free, each is allowed, and 1000 MB lands. The debit must be a
compare-and-set inside the same transaction that creates the `pending` row — `CLAUDE.md` rule 8 exactly:
never cache what a write decision depends on.

The release already has a home: a `Worker` job sweeps `pending` rows older than the presign lifetime
(ten minutes) and deletes the orphans. Returning the reservation belongs there rather than in a new
mechanism.

## Scope

- A per-conversation byte budget, **100 MB**, spent by visitor and operator alike — the author's answer
  is that the limit is symmetric.
- **Reserved at presign, released by the existing pending sweep.**
- The refusal names the remaining budget, not just "no". An operator who cannot send a file needs to
  know whether to wait or to compress.
- **"Active" needs a definition.** The author's words are *«пока кто-то не закончит разговор и он не
  отвалится по таймауту»* — so the budget belongs to the conversation and resets when the conversation
  does. `18-06` auto-closes inactive conversations; that is the timeout to reuse rather than invent.

## Where this is likely to go wrong

- **A budget per conversation bounds one conversation.** It is not what protects storage — see `23-76`,
  which is the item that does. Shipping this and believing MinIO is safe would be the worse outcome
  than shipping neither.
- **The number is not measured.** `AttachmentOptions`' own comment already admits its defaults are
  "a starting point, not measured or load-tested". 100 MB inherits that and should say so rather than
  acquiring authority by being written down.

## Done when

- [x] A conversation cannot accumulate more than the budget, whoever uploads.
- [x] Ten simultaneous presign requests cannot together exceed it, proven rather than reasoned.
      **With one caveat worth keeping.** The concurrency test passes with all three `FOR UPDATE` clauses removed, so it proves the budget holds under ten simultaneous presigns but does *not* prove the row lock is what makes it hold. Either the lock is redundant here or the test cannot see its absence; whichever it is, this test will not guard a future edit that removes it.
- [x] An unused slot returns its reservation, and the pending sweep is what does it.
      Delete and release are two CTEs of one statement, so there is no window in which a crash leaks budget.
- [x] The refusal says how much is left.
      `ConversationErrors.AttachmentConversationBudgetExceeded(declaredSizeBytes, reservation.RemainingBytes)` — the refusal carries what was asked for and what is left.
- [x] `file-storage.md`'s claim that a per-conversation ceiling exists becomes true, or is corrected —
      Corrected rather than made true: the per-conversation ceiling `file-storage.md` described had never existed.
      today it is simply false.
