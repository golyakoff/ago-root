# Move a booking into the new grid instead of cancelling it

- **Stage**: 20
- **Status**: ready — **deferred by the author**, deliberately not queued
- **Depends on**: `20-16-re-cutting-an-already-materialised-horizon.md` — the operation this improves
  the worst outcome of.

## Why this exists as its own item

`20-16` gives a tenant re-cutting their horizon exactly two choices for a day that already has a
booking on it: cancel the booking, or leave the whole day in the old grid. Both are lossy. Cancelling
costs a customer their appointment for an administrative reason they had no part in; keeping the day
means the schedule the tenant just fixed does not apply to precisely the days that matter most,
because those are the days with customers on them.

The author named the third option in the same breath as the second and deferred it explicitly: *"в
идеале — постараться найти подходящий слот в новом расписании (чтобы пересекался день и время) и
запись двинуть туда без удаления (можно отдельной фичой)"*. Written down as its own item rather than
left as a sentence in `20-16`, so that the gap `20-16` ships with is visible rather than implied.

## Sketch, not yet a design

During a re-cut, for each booking the tenant would otherwise cancel, look for a slot in the **new**
grid on the same business-local day whose time overlaps the original, and move the booking into it
rather than ending it. The day then re-cuts fully, with the moved booking occupying a slot the new
template actually produced — which is what makes the whole day consistent again, and is the real prize
here.

## Open questions — all of them, this is not ready to build

- **What counts as "подходящий".** Any overlap with the original window; the candidate whose start is
  nearest; a candidate within N minutes of the original start. These give different answers on an
  ordinary day and the difference is a customer's afternoon.
- **Whether a move needs the customer's consent at all.** This is the one that decides the shape. The
  customer agreed to 14:00 and would be moved to 13:30 by a tenant reorganising their week. Silently
  moving them and sending a notification is one product; asking them and holding the slot until they
  answer is a different, much larger one — it needs a pending state, an expiry, and a fallback when
  nobody replies.
- **What the customer is told, and over which channel.** `14-15`'s verified phone and `20-11`'s
  additional channels are the delivery surface; whether a move is worth an SMS is a cost question as
  well as a courtesy one.
- **Whether a move can cross workers.** Almost certainly not — the customer booked a person, not a
  time slot — but it should be refused explicitly rather than by omission.
- **Multi-slot bookings (`20-18`).** A three-slot run needs three consecutive slots in the new grid,
  which is a materially harder search than one slot and may simply have no answer on a day whose grid
  got finer.

## Out of scope, whenever it is built

- Moving a booking to a different day. If the same day has nothing, the fallback is `20-16`'s existing
  two choices.
- Moving a booking outside a re-cut — that is rescheduling, a different feature with a different
  trigger and a different consent story.
