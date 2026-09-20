# 25-171 · The landing page's channel marks are hand-drawn placeholders too

- **Stage**: 25
- **Status**: done — `ago-landing` (`21af60f`). Independently re-verified by the managing session
  before merging: all five icon files byte-identical to `25-172`'s canonical source (checked both
  in the worktree and pulled back out of the built container), `Dockerfile`'s new `COPY icons/` line
  confirmed necessary (local `docker build` + all five icon paths return 200), and a live browser
  check against the running container — real icons render correctly (MAX circle-cropped, Avito sized
  to 76%, Telegram/VK/WhatsApp as full circles), the grayscale↔full-color toggle and the calculator's
  pricing logic both still work correctly with a channel clicked live.
- **Depends on**: nothing (the icon assets themselves ship as part of 25-170's icon-replacement work
  in `ago-widget`, but this item can start once those five files exist regardless of that item's own
  status)

## What is actually true today

`ago-landing/index.html`'s own pricing calculator renders one toggle button per channel
(`.chbtn[data-ch]`), each carrying a small colored mark (`.mk`) - and every one of those marks is a
hand-drawn placeholder, not the channel's real brand icon:

```html
<button class="chbtn" data-ch="MAX"><span class="mk" style="background:linear-gradient(135deg,#8a4dff,#5b6bff)">M</span>MAX</button>
<button class="chbtn" data-ch="ВКонтакте"><span class="mk" style="background:#0077ff;font-size:8px">VK</span>ВКонтакте</button>
<button class="chbtn" data-ch="Авито"><span class="mk" style="background:#00aaff">A</span>Авито</button>
<button class="chbtn" data-ch="Telegram"><span class="mk round" style="background:#2aabee"><svg>...generic paper-plane path...</svg></span>Telegram</button>
<button class="chbtn" data-ch="WhatsApp"><span class="mk round" style="background:#25d366"><svg>...generic phone-handset path...</svg></span>WhatsApp</button>
```

MAX, VK and Avito are single-letter text badges on an approximate brand color. Telegram and WhatsApp
are a generic inline monochrome glyph on an approximate brand color - not the real logos, the same
category of stand-in `ago-widget`'s own channel-switcher card shipped under `25-149` and is being
replaced under `25-170`'s icon work.

## Goal

The five channel toggle buttons in the pricing calculator (and any other spot on the landing page that
marks a channel the same way - check `home.js`/`pricing.html` while implementing, this file only
confirmed `index.html`) render the same real brand icon files `25-170` produces for the widget, instead
of a hand-drawn letter or a generic glyph.

## Context to read first

- `25-170`'s own backlog file and the channel-icon review it was built against - the five source files
  it lands (`telegram.svg`, `whatsapp.svg`, `vk.svg`, `max.svg`, `avito.svg`) are this item's own
  assets; do not re-source or redraw them.
- `ago-landing/index.html`'s `.mk`/`.mk.round`/`.chbtn` CSS, to fit the real icons into the existing
  badge size/shape rather than changing the calculator's layout.

## Scope

- Replace each of the five `.mk` placeholder marks above with the corresponding real icon file from
  `25-170`.
- MAX and the others are already meant to render as a filled circle (`25-170`'s own resolution) -
  match that here too rather than reintroducing a rounded-square or plain-letter badge.
- Check `home.js` and `pricing.html` for any other hand-drawn channel mark using the same `.mk`
  convention and fix those too - this file only confirms `index.html`'s calculator.

## Out of scope

- Any change to which channels the calculator lists, their copy, or the calculator's own pricing logic.
- Adding a channel not already present here (e.g. SMS/Email have no such mark today and this item does
  not add one).

## Done when

- [x] Every `.mk` channel mark in the landing page's pricing calculator renders the real brand icon,
      confirmed live in a browser against both the light calculator background and any hover/pressed
      state the button has. — verified live: unpressed marks render desaturated, pressed marks render
      full color, confirmed by toggling ВКонтакте live.
- [x] Any other `.mk`-style placeholder found in `home.js`/`pricing.html` during implementation is
      either fixed the same way or explicitly noted here as out of scope with a reason. — checked:
      `home.js` only reads/writes `aria-pressed`/`data-ch`, no icon markup; `pricing.html` has no
      `.mk`/`.chbtn`/`.chgrid` at all. `index.html`'s calculator is the only place this pattern
      appears.
