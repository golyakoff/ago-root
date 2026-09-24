# 26-104 · The launcher icon's letter «A» is too small inside its circle

- **Stage**: 26
- **Status**: done — merged as [ago-android#93](https://github.com/golyakoff/ago-android/pull/93) (notification icon enlarged; the first pass's launcher change was reverted).
- **Found**: 2026-09-24, by the author, from a real notification: the «A» monogram reads as a tiny
  glyph floating in a large blue circle. It shows up wherever the app icon is drawn as an avatar —
  the notification shade's large icon, the launcher, the task switcher.

## What is actually true today

`app/src/main/res/drawable/ic_launcher_foreground.xml` (the adaptive-icon foreground from `26-34`)
draws the «A» far too small relative to the circle the background fills. The author's reference: the
letter's **height relative to the circle** should be roughly as in the second (small) sample image —
the glyph fills most of the circle, not a fraction of it. **The typeface/shape is fine — only the
size is wrong.**

## Scope

- Enlarge the «A» in `ic_launcher_foreground.xml` so its cap-height fills the circle to about the
  reference proportion (the letter clearly dominant, not a small mark in a big disc), kept centred.
- Apply the same size change to `ic_launcher_monochrome.xml` (the themed-icon variant) so the two
  stay consistent.
- Respect the adaptive-icon **safe zone**: the guaranteed-visible area is the central 66 of 108 dp, so
  size the glyph to look full within that masked circle without letting it collide with the mask edge
  on an aggressive OEM shape. Bigger, but still inside the safe zone.

## Out of scope

- The background gradient, the circle, the colours — unchanged (`26-34`).
- Any change to the monochrome small (status-bar) notification icon's own shape.

## Done when

- [~] The «A» in `ic_launcher_foreground.xml` (and `ic_launcher_monochrome.xml`) is enlarged — a 1.5×
      `<group>` scale about the shared (54,54) centre, cap-height 55% of the 108dp canvas, centred,
      height within the safe zone. Delivered and CI-green; **on-device eyeball (notification large icon
      + launcher) pending — the phone was disconnected 2026-09-24; verify when reconnected.**
- [x] `./gradlew ktlintCheck lint test` green.
