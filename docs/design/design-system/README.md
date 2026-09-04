# The AGO design-system bundle

Twenty standalone HTML pages describing the design system that **already exists** in `ago-console`.
Built for a design tool to read, so that it speaks this product's vocabulary instead of inventing a
second one.

This is not a proposal. Nothing here was designed, restyled or improved on the way in.

## Provenance

Every CSS rule in every page is a byte-for-byte slice of a file in `ago-console` at commit
`a64fcac7f50a3cecec4ea9f217575978bcbaadc8`:

| Source | Appears in |
|---|---|
| `src/design/tokens.css` | every page — the complete `:root`, the `prefers-color-scheme` block, and the `[data-theme="dark"]` block, all with their measured-contrast comments intact |
| `src/design/base.css` | every page |
| `src/components/components.css` | the eleven component pages and the states page, sliced at that file's own section banners |
| `src/shell/shell.css` | the shell, dialog and select pages |
| `src/workspace/workspace.css` | the workspace, badge and states pages |
| `src/index.css` | the screen-helpers, field and panel pages |

The three webfonts are requested from the same Google Fonts URL `ago-console/index.html` uses.
Opened offline, every page falls back to the system stacks declared in `tokens.css` — which is
exactly what the console does when that request fails.

To check that nothing has drifted, diff a page's CSS block against the source files named in its own
header.

## How to read a page

- Open the file. There is no build step, no shared asset and no server.
- `index.html` is the contents page.
- The first line of every file is a `<!-- @dsCard group="…" name="…" source="…" -->` marker.
- **Anything prefixed `dsp-` is preview chrome and is not part of the design system.** It is
  namespaced and banner-separated inside each `<style>` block for exactly that reason.
- The theme control in each header writes the same `data-theme` attribute `src/design/theme.ts`
  writes, and nothing else. It deliberately does not persist to `localStorage`.

## Groups

The groups are the codebase's own, not a generic taxonomy:

| Group | Is | Cards |
|---|---|---|
| Foundations | `src/design/` | 4 |
| Components | `src/components/` — the set `adr/0030` closed at eleven | 11 |
| States | the section of that name inside `components.css` | 1 |
| Shell | `src/shell/` | 1 |
| Workspace | `src/workspace/` | 1 |
| Screen helpers | `src/index.css`, which calls itself exactly that | 1 |
| Overview | this bundle's own contents page | 1 |

Anything in *Shell*, *Workspace* or *Screen helpers* is screen-local by the codebase's own reckoning
and should not be treated as a reusable system component.

## The rule this was built under

**If a component has three variants in code, its page shows three — not four aspirational ones.
Where a state has no design, the page says so in place rather than filling the gap.**

Those gaps are marked in red and worded as findings of fact. There are **thirty-seven** of them
across the nineteen cards — three of which are the same three control-level gaps, repeated on the
Input, Textarea and Select pages because they are true of each. An invented state would be read by a
design tool as ours, which is worse than a named hole.

## What this bundle does not contain

- **The widget has no design system.** `ago-widget/src/ui/styles.ts` is one template string of
  hard-coded hex values inside a Shadow DOM with `:host { all: initial }`. It shares no token, no
  scale and no component with the console; one accent colour crosses the boundary and nothing else.
- **The Keycloak screens** (sign-in, registration, password reset, account) live in `ago-deploy` and
  read a vendored, light-only copy of these tokens. They are the first screens a new tenant sees.
- **`ago-landing`**, which `tokens.css` names as the source of the palette and the type.

## Related

- `../ui-inventory.md` — where each of these appears on a real screen, and every screen's states.
- `../flows.md` — what people are trying to do.
- `../briefs/` — the two joined, per role.
