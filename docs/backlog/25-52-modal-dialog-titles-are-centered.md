# 25-52 · Modal dialog titles are centered

- **Stage**: 25
- **Status**: ready
- **Verified**: 2026-09-12 — the single shared `Dialog.tsx` component confirmed as every modal's own
  source: `<h2 className="ago-dialog__title">{title}</h2>` (line ~92), styled by `.ago-dialog__title`
  in `components.css`. One component change covers every dialog in the console.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## Scope

- In every message-box/dialog popup: the title becomes center-aligned; the body text stays
  left-aligned; the action buttons stay right-aligned, exactly as today.

## Done when

- [ ] Every dialog's own title is horizontally centered; body and buttons are unchanged.
