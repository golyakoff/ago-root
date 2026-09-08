# the chat button asks to be noticed

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing
- **Decision**: the author's, 2026-09-07 — a setting, off unless the tenant turns it on.

## Goal

A visitor who has not noticed the chat button notices it, and a tenant who thinks that is undignified
can leave it off.

## Scope

- **The launcher moves to draw attention while the widget is closed**, and stops the moment it is
  opened. Nothing moves once the panel is open — a moving thing beside a conversation is a distraction,
  not an invitation.
- **A checkbox «Привлекать внимание» in the widget settings screen**, off by default. It rides the same
  site configuration the colour and the position already do, so a tenant changes it in the console and
  a returning visitor sees it — within the refresh window `adr/0140` set, which is a day.
- **`prefers-reduced-motion` turns it off**, regardless of the setting. That is not a nicety: for some
  people repeated motion is a symptom trigger, and a tenant cannot consent on their visitor's behalf.

## Where this is likely to go wrong

- **It must not run forever.** A button that shakes every few seconds for as long as somebody reads the
  page is not attention, it is harassment, and it is the reason this pattern has a bad name. Decide how
  many times it happens and when it stops, and say so — a small number of attempts, then silence, is
  the shape to beat.
- **It must not shake once the visitor has dismissed the widget.** Somebody who closed it has answered.
- **The bundle budget.** It is a hard number checked on every build; an animation is CSS, and it should
  stay CSS rather than becoming a library.
- **Shadow DOM.** The animation is the widget's own and must not touch the host page's layout — a
  transform on the launcher, never anything that reflows what is around it.

## Out of scope

- Auto-opening the panel, which is `23-64`. This item only makes the closed button noticeable.
- Sound. No.

## Done when

- [x] `WidgetConfigPage` gets an `attractAttention` checkbox, off by default, sibling to
      `requireContactConsent`. Stored as a plain `bool` (no `[JsonRequired]` counterpart) - an
      omitted flag binding to `false` is not a security regression here, unlike the consent gate.
- [x] `ui/widget.ts` schedules the pulse only while the launcher is closed and cancels scheduling
      the moment the panel opens or the launcher is dismissed - there is deliberately no path that
      clears it later than the moment it is checked.
- [x] `MAX_ATTRACT_ATTEMPTS = 3` in `ui/styles.ts`, named in code rather than left to iterate
      until dismissed.
- [x] Checked at the moment scheduling is attempted and wins unconditionally over the tenant's
      own setting, asserted in `ui/widget.test.ts`.
- [x] Proved by the build that enforces it, run on the exact base this landed against:
      **31.8 KB gzipped against the 45 KB budget** (`npm run build`).
