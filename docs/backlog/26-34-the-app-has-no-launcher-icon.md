# 26-34 · The app has no launcher icon

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-22, by the author, asking to add a real launcher icon drawn from the brand mark.

## What is actually true today, confirmed against real code

`app/src/main/AndroidManifest.xml`'s `<application>` tag carries **no `android:icon`** attribute at
all, and `app/src/main/res` has **no `mipmap-*` or `ic_launcher*` resources whatsoever** — confirmed by
`find app/src/main/res -iname "*ic_launcher*"` returning nothing. The app installs and runs with
whatever fallback the OS supplies for an app that names no icon. `minSdk = 26` (`app/build.gradle.kts`)
is exactly the API level adaptive icons shipped in, so **no legacy pre-adaptive fallback is needed at
all** — this is a pure adaptive-icon job, nothing else.

## The brand mark, read from the real brandbook — do not re-derive or approximate these values

Fetched live from `https://brandbook.reserve-me.ru/logo.html` (the AGO brandbook's own Logo page) and
its computed styles, 2026-09-22:

> "There is no separate logo symbol anywhere in `ago-landing` or `ago-console` today — only the 'AGO'
> name, set in the display face, with a small gradient tile carrying its first letter... That wordmark
> is the logo for this page's purposes; inventing a new symbol would be adding to the identity, not
> documenting it."

The mark to use for the icon is that gradient tile alone (not the trailing "AGO" text — an icon has no
room for a wordmark). Exact computed values, read directly off the live `.g` element, not guessed:

- **Gradient**: `linear-gradient(140deg, #4C8DFF, #9D6BFF)` (`rgb(76,141,255)` → `rgb(157,107,255)`,
  the same `--blue`/`--violet` pair as the landing swatches).
- **Glyph**: capital **"A"**, white (`#FFFFFF`), font **Unbounded**, weight **700** (Bold) — an
  open-source geometric display face on Google Fonts (OFL license), already the brand's display face
  per the brandbook.
- **Reference proportions** (from the 34×34px web tile, `border-radius: 9px`, glyph `font-size: 20.4px`
  centered via `display: grid`): the glyph reads at roughly **60% of the tile's height**, centered. The
  `9px`-on-`34px` corner rounding is a **web-only** detail — see the adaptive-icon note below, it does
  not carry over directly.

## Adaptive icon, not a legacy PNG — and why the corner radius above does not apply here

Since `minSdk = 26`, the only icon that needs writing is the **adaptive icon**
(`developer.android.com/develop/ui/views/launch/icon_design_adaptive`): a background layer and a
foreground layer, each on a 108×108dp canvas, composited and masked by the *launcher*, not by the app —
different OEM launchers apply a circle, squircle, rounded-square or teardrop mask to the same two
layers. That means:

- **Do not bake the `9px`/`34px` corner radius into the background.** A shape baked into the background
  fights whatever mask the launcher applies on top of it. The background is a **full-bleed** 108×108dp
  fill (the gradient, edge to edge, no rounding) — the system supplies the shape.
- **The foreground glyph must sit inside the safe zone**: only the inner ~66×66dp of the 108×108dp
  canvas is guaranteed visible across every mask shape; content outside that circle can be clipped on
  some devices. Scale and center the "A" within that safe zone at a similar visual weight to the
  reference proportion above (roughly 60% of the safe zone's own height, not 60% of the full 108dp).

## Scope

1. **Get the real glyph outline, don't hand-draw it.** Unbounded is a real, freely-licensed font
   (Google Fonts). Download `Unbounded-Bold.ttf`, extract the actual outline of the capital "A" as SVG
   path data with a real tool (e.g. Python's `fontTools`:
   `fontTools.pens.svgPathPen.SVGPathPen` against the glyph's `glyf` table, or `fonttools ttx` +
   manual pen extraction) rather than approximating the letterform by eye — this is a mechanical
   extraction, and the result should be checked by rendering the extracted path to a PNG/SVG and
   looking at it before wiring it into the app.
2. **`app/src/main/res/drawable/ic_launcher_background.xml`** — a `VectorDrawable`, 108×108 viewport,
   full-bleed `<path>` filled with the gradient above. Android vector drawables support a gradient fill
   via `<aapt:attr name="android:fillColor"><gradient android:type="linear" .../></aapt:attr>` (root
   `<vector>` needs `xmlns:aapt="http://schemas.android.com/aapt"`); convert the CSS `140deg` angle to
   the vector's `startX/startY/endX/endY` coordinates on the 108×108 box — show the conversion, don't
   guess coordinates that merely look plausible.
3. **`app/src/main/res/drawable/ic_launcher_foreground.xml`** — a `VectorDrawable`, 108×108 viewport,
   the extracted "A" path scaled/centered into the 66×66dp safe zone, filled solid white.
4. **`app/src/main/res/drawable/ic_launcher_monochrome.xml`** (Android 13+ themed/Material You icons) —
   the same "A" path alone, single fill color (the system re-tints it), no background layer.
5. **`app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`** (and `ic_launcher_round.xml`, identical
   content — the system masks both the same way) wiring background + foreground + monochrome together
   per the standard `<adaptive-icon>` XML shape.
6. **`AndroidManifest.xml`**: add `android:icon="@mipmap/ic_launcher"` and
   `android:roundIcon="@mipmap/ic_launcher_round"` to the `<application>` tag.

## Out of scope

- A Play Store listing icon (512×512 PNG) — this app has no Play Store listing (`26-09`'s own release
  is a direct-download APK).
- Any other brand asset (favicon, notification icon, splash) — not asked for, not investigated here.

## Verify for real

- `./gradlew assembleDebug` succeeds (a malformed vector-drawable gradient is a build-time XML error,
  not a silent runtime issue — this alone catches most mistakes).
- Render each of the three drawables to a PNG (Android Studio's preview, or `resvg`/equivalent against
  the pathData reinterpreted as SVG) and look at it: the "A" should be recognizably the same letterform
  as the brandbook's, not a generic sans-serif "A".
- Install the built debug APK on a real device or emulator and look at the actual home-screen/app-drawer
  icon — confirm it is not clipped by the launcher's mask and that the gradient direction matches the
  brandbook (blue toward the upper-left-ish, per 140deg — state which corner is which once you see it
  rendered, don't assume).

## Done when

- [ ] `AndroidManifest.xml` names a real icon, and it is not the OS's fallback icon anymore.
- [ ] The background is a full-bleed, unrounded 140°-gradient fill; the foreground is the real
      Unbounded-Bold "A" outline (not a hand-approximated shape), white, inside the safe zone; a
      monochrome variant exists for themed icons.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device or emulator — not just "should render", actually looked at.
