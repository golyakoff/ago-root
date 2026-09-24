# 26-84 · Backgrounding the Android app silently releases the operator's conversations

- **Stage**: 26
- **Status**: filed — as the question. The mechanism and the evidence are both real and confirmed;
  which of several fixes is right is a product call about how a mobile operator is expected to work,
  not something this session decides on its own (`CLAUDE.md` rule 14).
- **Found**: 2026-09-24, by the author, live on the demo stand, while trying to reproduce a reported
  "the conversation list feels slow to update" symptom. The real cause turned out to be several layers
  deeper than list-refresh timing.

## What is actually true today, confirmed against real data on the live demo stand

Three independent pieces of evidence, all from the same live test window (08:44–08:50 UTC):

1. **`conversation_assignments` for the test conversation** shows the operator's claim ending and
   restarting twice within six minutes of active use:

   | `started_at` | `ended_at` | `source` |
   |---|---|---|
   | 08:44:18.08 | 08:44:41.06 (23s later) | Taken |
   | 08:45:10.88 | 08:47:41.12 (2m30s later) | Taken |
   | 08:49:55.40 | *(still open)* | Additional |

   Cross-referencing against the visitor's own messages sent during this window: several arrived
   **between** an ended assignment and the next `Taken` — genuinely unassigned at that moment — which
   is exactly why the author saw "push still hasn't arrived" for messages that, from the phone's own
   screen, looked like they were being received inside an open, assigned conversation the whole time.

2. **The Redis connection registry (`conn:*`) showed zero live connections for the tested operator
   across every multi-minute polling window run this same session** (some over five minutes long,
   sampled every 2–3 seconds) — including windows where the Android app was reported open and in use.

3. **`OperatorDisconnectGraceConsumer` (`ago-chat`, `Ago.Chat.Worker`) is the mechanism connecting the
   two**: on `OperatorPresenceLost`, it waits `GracePeriod` (**30 seconds**, `OperatorDisconnectGraceConsumerOptions`'s
   own default — its doc comment already flags this as "a starting point, not measured or load-tested"),
   checks the connection registry exactly once more, and if the operator still has zero connections,
   calls `OperatorConversationReleaser.ReleaseAllAsync` — releasing **every** conversation that
   operator holds back to the queue.

4. **`OperatorHubConnection` (`ago-android`) documents its own behavior in these exact words**: "Android
   will suspend a background socket… the app connects when it is in front and lets go when it is not."
   `disconnect()` is called deliberately whenever the app leaves the foreground, and a deliberate stop
   is specifically designed **not** to trigger the client's own reconnect loop (`stopRequested` gates
   `onConnectionClosed`'s `attemptReconnect` call) — correct for "the operator closed the app", but it
   fires on every ordinary backgrounding too: screen lock, switching to another app for a moment,
   an incoming call.

5. **Worse than a single grace cycle — the `operator-disconnect-grace` queue stayed saturated for over
   20 minutes straight**, well past the end of active testing. A `rabbitmqctl list_queues` poll every
   ~10 seconds from 08:40 to 09:04 UTC shows `messages_unacknowledged` pinned at a constant **50**
   (this consumer's own prefetch ceiling, per its doc comment's "bounds this consumer's throughput to
   the broker's own prefetch count" remark) the *entire* window, while `messages_ready` — the backlog
   waiting *behind* that saturation — climbed from 4 to a peak of **14** around 08:47 and only slowly
   drained to 9 by 09:03, twenty minutes after the visible test ended. A consumer that holds every
   delivery unacked for its own 30-second `GracePeriod` staying pinned at its prefetch ceiling for
   twenty-plus minutes means **`OperatorPresenceLost` kept being published far faster, and for far
   longer, than one operator backgrounding their phone once should ever produce** — either a genuine
   sustained reconnect loop (matching the pattern already found on the web console's own hub
   connection, `26-83`'s own investigation), or `OperatorPresenceLost` is being re-published on every
   sweep of `OperatorDisconnectSweepJob` for an operator already known to be gone, rather than once per
   actual disconnect. **Not yet distinguished — this item's own scope below now includes finding out
   which.**

**Put together**: the 30-second grace period was written and reasoned about for a desktop console tab
staying open. On a phone, screen-off or switching apps for **more than 30 seconds** — completely
ordinary handling of a physical device — silently unassigns every conversation the operator is holding,
with no warning to the operator that it happened.

## Why this matters more than a list-refresh bug

- **The original symptom ("list feels slow") was a real, correct rendering of a real, silent state
  change** — the list wasn't lagging; the conversation genuinely stopped being "Мои" for a window, then
  became "Мои" again once re-claimed. The Android UI was telling the truth the whole time.
- **Push suppression during the unassigned gaps is also correct, by the same design** — `26-05`'s own
  "the assigned operator only" rule means a message arriving while unassigned is not pushed to anyone,
  which is precisely what the author observed and initially read as broken delivery.
- **The actual product risk**: an operator who locks their phone to answer a doorbell, or gets a phone
  call, or simply doesn't touch the screen for half a minute, can come back to find the visitor they
  were mid-conversation with has been silently handed to someone else — or to nobody, sitting back in
  "Ожидают" with no notice.

## What this item does not decide

Several different fixes are all plausible, and each is a real product/UX call rather than an
engineering default:

- **Raise `GracePeriod` for mobile specifically** — simplest, but picking a number without a measured
  basis repeats the exact thing this option's own doc comment already warns against, only with a
  higher number.
- **Don't disconnect on backgrounding at all** (keep the socket alive, relying on Android's own OS-level
  background execution limits to eventually kill it) — trades battery/OS-compliance risk for
  correctness, and Android's willingness to keep a background socket alive varies by OEM and battery
  settings in ways this app cannot fully control.
- **Disconnect on backgrounding, but don't publish `OperatorPresenceLost` for a "the app is still
  installed and was recently foregrounded" case** — needs a real signal the client would have to send
  (e.g., "backgrounded, not signed out") that does not exist on the wire today.
- **Show the operator, in the app, when a conversation they were holding has been released** — orthogonal
  to any of the above and probably worth doing regardless of which timing fix is chosen.

## Scope

- **First, distinguish the two candidate causes named above** — is `OperatorPresenceLost` firing once
  per genuine disconnect (meaning the Android app really is reconnecting/disconnecting continuously for
  20+ minutes, a client-side reconnect-storm bug), or is `OperatorDisconnectSweepJob`/some other periodic
  path re-publishing it repeatedly for an operator already known to be gone (a server-side dedup gap)?
  This changes which side of the wire the real fix belongs on, and neither has been confirmed yet.
- Once a direction on the grace-period/backgrounding question itself is chosen (see options above),
  prove it with a real backgrounding test on a real phone: background for under the threshold (no
  release), background for over it (release, and the app finds out).
- Update `docs/architecture/realtime.md`/`push-notifications.md` to state the real, chosen behavior —
  today neither document mentions that backgrounding interacts with assignment at all.

## Done when

- [ ] The author has chosen a direction from the options above (or a different one).
- [ ] It is implemented and proven on a real device.
- [ ] The relevant architecture doc states the real, current behavior.
