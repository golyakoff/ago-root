# 25-107 · `JoinAsync` crashes instead of refusing when conversation creation is rate-limited

- **Stage**: 25
- **Status**: done — fixed and merged (`ago-chat` [PR #309](https://github.com/golyakoff/ago-chat/pull/309)).
- **Depends on**: nothing
- **Found**: 2026-09-15, running the first real `capacity-ramp` load test locally (`load/reports/2026-
  09-15-local-capacity-ramp.md`) - a burst of new conversations against one site tripped
  `ConversationCreateRateLimitOptions`'s per-site bucket, and every rate-limited visitor got a raw
  `500` with a server-side stack trace instead of a rate-limit response.

## What is actually true

`VisitorHub.JoinCoreAsync` (`ago-chat/src/Ago.Chat.Api/Hubs/VisitorHub.cs:131`):

```csharp
var started = await startConversation.HandleAsync(
    new StartConversation(siteId, visitorId, source), Context.ConnectionAborted);
var conversationId = started.Value.ConversationId;
```

`StartConversationHandler.HandleAsync` returns `Result<StartConversationResult>` and genuinely fails
when `ConversationCreateRateLimitOptions`'s per-visitor or per-site bucket is exhausted
(`ConversationErrors.ConversationCreateRateLimited`, referenced by `StartConversationHandler.cs`).
`JoinCoreAsync` never checks `started.IsFailure` before dereferencing `.Value` - `Result<T>.Value`
throws `InvalidOperationException("Cannot access Value of a failed Result: ...")` on a failed result,
by design (`Ago.Platform.Kernel.Result<T>`'s own contract). That exception is unhandled, so SignalR
reports it to the client as a generic `500`/hub-invocation failure with no rate-limit information at
all - confirmed live: `System.InvalidOperationException: Cannot access Value of a failed Result:
Conversation.CreateRateLimited: Too many new conversations - retry after 5.1s..` in the API pod's own
logs, for every visitor who happened to join while the site's bucket was empty.

**This is a local, isolated omission, not a systemic pattern** - `SendMessageAsync` in the same file
(`VisitorHub.cs:257`) checks `sent.IsFailure` and translates the failure into a proper `HubException`
carrying the real error message; `JoinConversationAsync`'s own history read (`VisitorHub.cs:308`) does
the same for `page.IsFailure`. `JoinCoreAsync` is the one call site in this file that skips the check
already established, correctly, right below it.

## Scope

- `JoinCoreAsync`: check `started.IsFailure` before `started.Value`, and throw a `HubException` naming
  the real error (matching `SendMessageAsync`'s own established shape at `VisitorHub.cs:257-259`) -
  including the rate limit's own `RetryAfter`, if `ConversationCreateRateLimited`'s error carries one
  (check `ConversationErrors.ConversationCreateRateLimited`'s own shape before assuming).
- A regression test: a visitor whose site has exhausted `ConversationCreateRateLimitOptions`'s bucket
  gets a real `HubException` from `JoinAsync`, not an unhandled `InvalidOperationException` - proven
  failing against the code above, passing after the fix.

## Out of scope

- Whether `ConversationCreateRateLimitOptions`'s own default (100/site, ~100/hour) is the right number
  for production - untouched, a separate question this item has no opinion on.
- The two other rate limiters this same load test needed raised locally
  (`VisitorSessionRateLimitOptions`, `MessageSendRateLimitOptions`) - neither has this crash-on-refusal
  bug (confirmed: `SendMessageAsync`'s own `IsFailure` check already handles the message one correctly;
  the visitor-session handshake is a plain REST endpoint, not a hub method, and returns its rate limit
  as an ordinary HTTP response).

## Done when

- [x] A rate-limited `JoinAsync`/`JoinWithTrafficSourceAsync` call returns a `HubException` naming the
      real reason, not an unhandled `InvalidOperationException` - `JoinCoreAsync` now checks
      `started.IsFailure` and throws `new HubException(started.Error!.Value.Message)`, the same shape
      `SendAsync`'s own established `sent.IsFailure` branch already uses two methods below in the same
      file.
- [x] A test proves it - `VisitorJoinRateLimitedTests.JoinAsync_WhenConversationCreateIsRateLimited_
      ThrowsAHubExceptionNamingTheRealReason`, fails-before confirmed live (reverting the fix, the
      test's own `Assert.ThrowsAsync<HubException>` failed with `InvalidOperationException` instead),
      restored from the staged fix, full suite re-run clean (3492/3492, 0 failed).
