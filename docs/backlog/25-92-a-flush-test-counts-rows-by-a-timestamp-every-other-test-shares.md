# 25-92 · A flush test counts rows by a timestamp every other test shares

- **Stage**: 25
- **Status**: done — `FlushAsync_WithNoPendingMessageAtAll_WritesNothing` now seeds its own
  conversation and scopes its count by that `ConversationId`, the same isolation key every other
  assertion in the file already uses. Verified: `dotnet format --verify-no-changes`/`dotnet build`
  clean; a full run of `Ago.Chat.Integration.Tests` (1222/1222, ~10.5 min, real Postgres, every
  sibling test in the collection running alongside it) is the order-independence proof the second
  Done-when box asks for — not an isolated re-run, the actual shared-database conditions that made
  the original assertion order-dependent. A grep for the same unscoped `CreatedAt == Now` shape
  elsewhere in the project found no other instance.
- **Depends on**: nothing
- **Found**: 2026-09-14, landing `25-83` — CI failed `ago-chat`'s required check on a test file `25-83`
  never touched. The same failure had already shown up twice locally that same evening: once in the
  `25-83` worker's own finish-pass run, once in the managing session's independent re-verification —
  and then did *not* reproduce in a third, independent run against a different worktree/branch minutes
  later. Three runs of the identical unmodified test, two outcomes, is what made this worth a number of
  its own rather than a shrug.

## What is actually true

`Ago.Chat.Integration.Tests.MessageBatchWriterAutoGreetingTests.FlushAsync_WithNoPendingMessageAtAll_WritesNothing`
asserts `Assert.Equal(0, await verify.Set<Message>().CountAsync(m => m.CreatedAt == Now))` — a count
scoped by **timestamp alone**, no `ConversationId`, no `SiteId`, nothing test-specific. `Now` is
`new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero)` — a hardcoded literal, and not this file's own: the
identical literal is `private static readonly DateTimeOffset Now` in dozens of other classes across
`Ago.Chat.Integration.Tests` (`AcceptanceRecordErasureGuardTests`, `AttachmentUploadFlowTests`,
`ChannelCredentialRepositoryTests`, and many more — a project-wide convention for a deterministic
clock, not a coincidence).

`PostgresFixture`'s own remarks already say the quiet part out loud: "**one Postgres container per
test class collection**, migrations applied once - not per test, since Stage 1 has no
truncation/reset story yet and every test isolates itself with fresh ids instead." Every Integration
test class shares `[Collection(PostgresCollection.Name)]` — one real, never-truncated database for the
whole assembly's run. "Isolates itself with fresh ids" is exactly what this one test does not do: it
is the only assertion in the file (checked against its siblings in the same class, which all filter by
`ConversationId`) that has no id to filter by, so any other already-run test in the same process that
wrote a `Message` row stamped with the same shared `Now` literal is invisible to this test's own logic
and counted anyway.

xUnit gives no ordering guarantee for tests within a collection. When this test happens to run before
the suite has written any `Message` row with that exact timestamp, it passes. When it runs after even
one sibling test has (which is most of the file, and most of the project), it fails on whatever count
those already-committed rows add up to — `4`, in every failure observed tonight, though nothing pins
that number down as fixed rather than incidental to which tests ran first.

## Why this is worth its own item

Not a `25-83` regression — the file is untouched by that diff (`git diff origin/main -- <this file>`
is empty), and the failure has already been separately observed against a different, unrelated branch
tonight. It also is not the same shape as `25-81`'s Mono.Cecil race (no concurrent writer to a shared
in-memory structure) — it is order-dependence in a shared, never-truncated database, which is exactly
the risk `PostgresFixture`'s own comment already names as accepted ("isolates itself with fresh ids
instead") for every test except this one, which does not.

## Where this is likely to go wrong

- **The fix is this one test, not the fixture.** `PostgresFixture`'s no-truncation design is a
  deliberate, working convention every other test in the project honors correctly by scoping its own
  assertions to ids it created itself. Making this test do the same (filter by `ConversationId`,
  `SiteId`, or a `MessageId` it can name) is the targeted fix; introducing per-test truncation to
  rescue one under-scoped assertion would be `25-81`'s own rejected-alternative shape — touching shared
  infrastructure every other test already depends on, to fix the one test that used it wrong.
- **This may not be the only test in the project with the same shape.** This item's own Done-when only
  requires closing the one instance CI actually caught; a broader grep for `CountAsync` / `Assert.Equal`
  scoped only by `CreatedAt == Now` across `Ago.Chat.Integration.Tests` is worth doing while in the
  file, but expanding this item to fix every instance found is a judgment call for whoever picks this
  up, not a scope commitment made here.

## Done when

- [x] `FlushAsync_WithNoPendingMessageAtAll_WritesNothing` scopes its own count by something this test
      itself created (a fresh `ConversationId`, `SiteId`, or equivalent), not by the shared `Now`
      literal alone. Reuses `SeedWaitingConversationAsync`, the identical helper every other test in
      the file already seeds its own conversation with.
- [x] Proven order-independent: the full `Ago.Chat.Integration.Tests` project (1222 tests, every
      sibling that stamps rows with the identical `Now` literal running in the same shared,
      never-truncated database) passes clean, including this test.
