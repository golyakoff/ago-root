# the chat button asks to be noticed

- **Stage**: 23
- **Status**: ready
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

- [ ] A tenant can turn «Привлекать внимание» on, and it is off until they do.
- [ ] The launcher draws attention while closed and stops when opened or dismissed.
- [ ] It stops on its own after a bounded number of attempts, and the bound is stated in the code.
- [ ] `prefers-reduced-motion` disables it whatever the setting says, asserted by a test.
- [ ] The widget's bundle budget still holds.
