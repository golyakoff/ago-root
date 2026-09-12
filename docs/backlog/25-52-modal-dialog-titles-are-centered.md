# 25-52 · Modal dialog titles are centered

- **Stage**: 25
- **Status**: done — `ago-console#198`
- **Verified**: 2026-09-12 — the single shared `Dialog.tsx` component confirmed as every modal's own
  source: `<h2 className="ago-dialog__title">{title}</h2>` (line ~92), styled by `.ago-dialog__title`
  in `components.css`. One component change covers every dialog in the console.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## Scope

- In every message-box/dialog popup: the title becomes center-aligned; the body text stays
  left-aligned; the action buttons stay right-aligned, exactly as today.

## Done when

- [x] Every dialog's own title is horizontally centered; body and buttons are unchanged.

## Outcome

`components.css`'s `.ago-dialog__title` rule (~line 521) gets `text-align: center`; nothing else in
that rule or in `.ago-dialog__inner`/`.ago-dialog__footer` changed, so the body content and the
right-aligned footer buttons are untouched — confirmed by rendering the real stylesheet against a
modal-variant and a drawer-variant `Dialog` side by side.

The drawer variant (`.ago-dialog--drawer .ago-dialog__title`, ~line 585, the mobile nav drawer
`AppShell` mounts) is deliberately left out of the centring: its title already reads as an uppercase,
letter-spaced section label rather than a modal headline, and centring it would have fought that
existing convention rather than served it. Since it no longer inherits the ordinary block
start-alignment once the base rule centres, the drawer override now sets `text-align: left` explicitly
to keep its current look unchanged.

`Dialog.tsx` itself needed no change — one shared component, one CSS rule, covers all sixteen call
sites. Branch `fix/25-52-modal-dialog-titles-centered` in `ago-console-25-52`, commit-prepped but not
yet pushed or opened as a PR. `npm run typecheck`, `npm run lint`, `npm test` (111 files / 1175 tests),
and `npm run build` all pass clean in that worktree.
