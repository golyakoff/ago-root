# 26-130 · [ago-android-design] Split the Android mockup artifact into a git-hosted design mini-site

- **Stage**: 26 — design-ops. New repo `ago-android-design` (created), mirrors `ago-brandbook`'s static-bundle pattern.
- **Status**: ready — author-approved (public, unadvertised; domain `android-design.reserve-me.ru`).
- **Found**: 2026-09-25 — editing the one ~200 KB mockup Artifact per iteration is expensive; move the source
  of truth to small per-section files in git, publish as a static site like the brand-book.

## Structure (by SECTION, not by feature/ticket)
- **Shared shell (`common`)**: phone frame, brand tokens, a single **glyph sprite** (chat, phone, check,
  warning, exclamation, nav icons…), bottom-nav — one include every page pulls, so a glyph change is one edit.
  **Use the corrected glyphs from the start**: chat = rounded-rectangle Material `chat_bubble`; phone =
  MIRRORED handset (26-126); check/warning/exclamation as agreed.
- **Section pages**: `common`, `login-boot`, `dialogs`, `booking`, `team`, `settings` — the screens from the
  current artifact (`8b4fb3a8`) split into these; `booking` uses the latest approved 26-112 screens (names,
  month labels, chat/phone icons, detail sheet).
- **index.html**: a table of contents linking the sections.
- Keep each page's own captions/notes (the documentary `.cap` style) with the screens.

## Build/host scaffold (mirror ago-brandbook byte-for-byte where sensible)
- `Dockerfile` + `nginx.conf` serving the static files; `version.json` carrying the commit (the "image can
  name its own commit" check); `.github/workflows/ci.yml` = build-image on PR + publish `ghcr.io/golyakoff/
  ago-android-design:<sha>` on main (default `GITHUB_TOKEN`, packages:write — no extra secret, same as
  ago-brandbook's first workflow); `README.md`, `LICENSE`, `.gitignore`.

## Out of scope
- The ago-deploy wiring (static.yaml + gateway route + TLS on the subdomain) — that's `26-131`, and waits for
  the domain to be provisioned.

## Done when
- [ ] Repo holds: shared shell, `index.html`, the six section pages with the artifact's screens split in,
      corrected glyphs, and the ago-brandbook-style Docker/nginx/CI scaffold.
- [ ] `docker build` succeeds and `version.json` names the commit (CI's own check).
- [ ] The old Artifact stays as a snapshot; this repo is the new source of truth.
