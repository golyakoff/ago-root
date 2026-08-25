# Say on the demo page that anyone can read what you type there

- **Stage**: 8
- **Status**: ready
- **Depends on**: nothing

## Goal

A stranger typing into the public demo widget knows, before they type, that their message is readable
by anyone who opens the demo console. Today nothing says so anywhere.

## Why

The demo operator account is public by design — the credentials are handed out so a reviewer can see
the product work. The consequence, which was never stated, is that every conversation started from
`demo-shop1`/`demo-shop2` is visible to every stranger with the console open at the same time.

For a demo with invented data that is fine. It stops being fine the moment it is not said, because
people type real things into chat boxes — a name, a phone number, a question about their own business.
`architecture/personal-data.md`'s central point applies exactly here: message content is the one part
of this system's personal data that cannot be minimised by design, only by not collecting it. Telling
people is the cheapest control available and the only one that works before the fact.

## Scope

- One line on both demo pages, above or inside the widget, plain and unhedged: this is a public demo,
  anyone can read what you write here, do not type anything real.
- The same in the console's own sign-in area or first screen, so the person on the operator side knows
  they are looking at strangers' messages rather than a sandbox of their own.
- Nothing dressed up. A polite banner that people skim is worth less than a blunt sentence.

## Out of scope

- `16-04`'s tenant-configurable processing notice — the real product mechanism, for real tenants. This
  item is two lines of copy on our own demo pages and must not wait for it.
- Making the demo private, or gating it behind a form. It exists to be opened by strangers.
- Deleting demo conversations on a schedule. Worth having, and it is `15-04`'s mechanism plus a policy;
  not this.
- `8-07`'s per-viewer demo tenants, which would make this notice narrower but not unnecessary — the
  public demo pages stay shared even then.

## Done when

- [ ] Both demo pages say it, in the widget's own flow rather than in a footer.
- [ ] The console says it too, on the way in.
- [ ] Checked on the live deployment, on a phone-width screen as well.

## Open questions

None.
