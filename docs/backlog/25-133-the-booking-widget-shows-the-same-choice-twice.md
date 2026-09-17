# 25-133 · The booking widget shows the same choice twice

- **Stage**: 25
- **Status**: done — `ago-widget#93`
- **Found**: 2026-09-17, live, reported by the author mid-booking: every choice-shaped step (which
  service, which worker, which date, which time) renders as a numbered text list *and* real buttons
  for the identical options, one directly under the other.
- **Depends on**: none technically. Shares `ago-widget/src/ui/widget.ts` with `25-136` - land in the
  same lane, sequentially, not as two parallel branches touching the same function.

## The gap, and why the fix is narrower than it first looked

Every module-task message carries two things: `Message.Body` (plain text - the mandatory,
every-channel fallback per `adr/0061`, e.g. `"Что вы хотите забронировать?\n1) Консультация…\n2)
Примерка…\nReply with the number."`) and structured `Content` (`contentKind`/`content`/`actions` -
what `ago-widget/src/ui/primitives/render.ts`'s `renderPrimitiveContent` turns into real buttons).

The author's own read of this, confirmed correct: **the console needs the plain-text list, because
the console is not a chat and should not grow a rich-form renderer of its own** - it reads `body`
only (`ago-console/src/realtime/protocol/types.ts` has no `contentKind`/`content`/`actions` field at
all) and an operator scanning a transcript needs to see what a visitor was actually offered. So
`Body` keeps carrying the full plain-text rendering, unchanged, for every consumer that isn't the
live widget - the console, and a real text channel (Telegram/MAX) via `DeliverChannelMessageHandler`'s
own independent re-render at relay time. **No `ago-chat` change is needed for this item at all.**

The actual bug is narrower and lives entirely in the widget: `ui/widget.ts` appends the `body` text
as a message bubble **unconditionally**, then separately appends whatever `renderPrimitiveContent`
returns (the buttons) underneath - both, every time, regardless of whether the primitive renderer had
anything to add. `render.ts`'s own doc comment (lines 60-64) states this is deliberate, citing
`adr/0061`: `"message.body is left to the caller - it is the mandatory, every-channel-renders-it
fallback... shown regardless of whether this function has anything to add."`

That reading of the ADR is stricter than what the ADR is actually protecting. The fallback exists so
a widget build that does **not** recognise a given `contentKind` still shows something usable
(`render.ts`'s own remarks, lines 15-21: "An unrecognised `contentKind`... returns `null`, and the
caller's existing plain-`body` bubble is the whole fallback"). When the widget *does* recognise the
kind and successfully renders a rich form, showing the plain-text version underneath it is not a
fallback being used - it's a redundant second rendering of the same choice, plus (until `25-134`
lands) the English "Reply with the number." line bleeding into an otherwise-Russian conversation.

## Scope

- In `ago-widget/src/ui/widget.ts`, show the `body` bubble **only when `renderPrimitiveContent`
  returned `null`** for that message (i.e., only when the widget could not build a rich form for the
  step's `contentKind`) - never in addition to a successfully rendered primitive.
- No change to `ago-chat`'s `Body` computation, no change to the console, no change to Telegram/MAX
  delivery. This item is `ago-widget`-only.
- Note in the PR (or a short follow-up to `adr/0061`) that its "shown regardless" wording described
  the pre-this-item widget behaviour, not a guarantee the ADR intended to make - the mandatory,
  always-*available* fallback is unchanged; what changes is that the *live widget* now prefers a rich
  form over its own text fallback when both exist for the same message, rather than showing both.

## Where this is likely to go wrong

- `verified_phone_form` and `escalate` are not in the widget's `KNOWN_KINDS`
  (`render.ts:23,25`) - `renderPrimitiveContent` already returns `null` for them today, so they must
  keep showing their `body` text (the only way a visitor can currently even answer a
  `verified_phone_form` step is by typing into the ordinary composer - see `25-136`'s own remarks).
  Confirm this case is exercised by a test, not merely reasoned about.
- `confirmation_card` is choice-shaped in `PrimitiveKinds` but its `Body` today is *not* useful
  prose - it's `Render`'s fallback branch, currently the visitor's own last message echoed back
  (see `25-135`). Suppressing that echo bubble whenever the card renders is a visible improvement on
  its own even before `25-135` lands; don't make this item depend on that one.
- Don't touch `ui/primitives/render.ts` itself - it already returns `null` correctly for an unknown
  kind; the caller's decision of what to do with that `null` is what changes.

## Done when

- [x] A widget visitor on a `choice_list` / `date_time_picker` step sees the prompt once (from the
      rendered primitive, not from a text bubble) and buttons below it - no numbered list, no
      "reply with the number" line, anywhere in the widget
- [x] A step whose `contentKind` the widget does not recognise (or does not yet render, e.g.
      `verified_phone_form`/`escalate`) still shows its `body` text exactly as today - proven by a
      test, not left to reasoning
- [x] The operator console's own view of the conversation is provably unchanged (it reads `body`,
      which is untouched by this item)
- [x] Telegram/MAX delivery is provably unchanged (it re-renders from `Content` independently at
      relay time, which is untouched by this item)

## Outcome

Landed exactly as scoped, `ago-widget`-only: `renderBubble` gained a `showBody` parameter, and
`appendMessageBubble` now computes `renderPrimitiveContent`'s result before deciding whether the
plain-text bubble needs its text at all. Verified independently (typecheck/lint/build clean; 35
files, 407 tests passed; 38.0 KB gzipped against the 45 KB budget). `ago-widget#93`.
