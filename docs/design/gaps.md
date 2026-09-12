# The thirty-seven red blocks, in three piles

`design-system/` marks every place the system has no design rather than filling it, because an
invented state would be read as ours. That is the right call and it leaves a list nobody can act on
as a list — thirty-seven items look like thirty-seven tasks, and they are not.

**They are three different kinds of thing**, and only the third needs the author.

Sorted 2026-09-04 by reading each marked block and, for the first pile, checking the claim against
`ago-console@origin/main` rather than taking the bundle's word for it.

---

## Pile 1 — delete it. No design, no decision, no ticket

Dead surface. The block disappears when the thing is **removed**, and the system gets more honest by
subtraction. Verified individually:

| What | Evidence |
|---|---|
| `--ago-shadow-md` | declared in all three palettes, referenced by **no rule** — `git grep` finds it three times, all declarations |
| `Panel`'s `actions` slot | the prop exists and **no screen passes it** — zero `actions=` in `src/pages` or `src/workspace` |
| `.ago-control--file` | styled in `components.css`, rendered by nothing but itself |

Three items, an afternoon, no conversation. Doing this first shortens the list before anybody argues
about the rest.

**One caution**: `Panel`'s `actions` is the shape a "Save" in a panel header would use. Deleting it is
right *if* the design pass does not want that pattern — so this one waits for the pass rather than
racing it. The other two do not.

---

## Pile 2 — they close by themselves, as stage 23 and the design pass land

Nothing here needs its own decision. The block is a hole a screen will fill when the screen is built,
and it is marked precisely so the designer meets it rather than inventing around it.

**Closed by stage 23's items:**

- **Absent and forbidden look identical** — a permission-gated nav item is simply not there. This is
  `23-21`, and it is the same defect `22-14` was found through.
- **No delivery state on a message** — decision 9 records channel outcomes; the widget half is
  deliberately deferred, so the block half-closes and the remainder is a stated limit rather than a
  gap.
- **The waiting row is styled to look like not-a-control** — because there is no claim action. `23-03`
  builds one, and the row becomes a control.
- **The visitor's end of the conversation is timestamped differently** — story 1.3's item.
- **Three screens have no empty state**, **no first-run or zero-data state anywhere** — decision 3
  makes "nothing yet" a designed first state with a next action, on the screen where it matters most.

**Closed by the design pass, given the stories:**

- Alert cannot be dismissed; Panel cannot collapse and has no footer; Dialog has one width; Table has
  no empty state, no sorting, no sticky header; the thread has no empty state; no skeleton matches a
  real component; no read-only treatment; no required marker; no character counter; no success state
  on a control; no inline validation.

Every one of those is *"what should this look like"*, which is the pass's job. Filing them as tickets
now would decide the designer's answer before the designer runs — which is why the previous slice
deliberately left them out.

---

## Pile 3 — real decisions nobody has made. These need the author

**A red block here is a question, not a task.** Some of them should stay red for ever, and the block
disappears not because we built the thing but because we **wrote down that we will not**.

`adr/0030` closed the component set at eleven **on purpose**. Each of these is an amendment to that
ADR, not an addition to a backlog.

1. **No toast, snackbar or transient notification anywhere.** Every message in the console is an
   `Alert` at the place it concerns. That may be the right answer for ever — a product where feedback
   appears where the thing happened, rather than floating in a corner and vanishing. Decide, then the
   block closes either way.

2. **No warning tone.** `Alert` has danger and success; anything in between is one or the other today.
   The re-cut screen and the lapsed-grant screen both want *"this is fine but look"*.

3. **No icon set, and no icon-only button. Re-opened 2026-09-06 (`23-31`/`adr/0129`), after one day
   answered.** `23-24` answered this narrowly on 2026-09-05 by shipping one inline-SVG lock glyph
   beside a muted nav entry's label (`NavLockGlyph`, `adr/0030`'s second amendment). `23-31` replaced
   the muting rule that glyph existed for — muted now means *"you can obtain this yourself"*, which a
   padlock states wrongly — so the glyph was **deleted rather than repointed** and the calendar's
   muted entry carries a `Badge` instead. There is now no icon anywhere in the console again, which
   is exactly where this question stood before `23-24`.

   Recorded as re-opened rather than quietly restored, because the interesting part is that the
   answer did not survive its own week: it was tied to one meaning, and the meaning changed. A future
   answer to this question should be one that does not depend on a single rule staying true.

   **Answered a third time, 2026-09-12 (`25-47`, `adr/0030`'s fourth amendment).** Three inline
   Material Symbols Outlined glyphs beside the new user menu's own rows (tenant switcher, Appearance,
   Sign out) - `src/shell/menuIcons.tsx`. Unlike the withdrawn lock glyph, each sits beside text that
   already states the same fact in words, so there is no single meaning for a later rule change to
   pull out from under it the way `23-31` did to `NavLockGlyph`. Closed again, narrowly, for these
   three and no others.

4. **No tooltip and no popover.** Every explanation in the console is inline prose today. That is a
   defensible stance and an expensive one on dense screens.

   `25-47` added the console's first real dropdown menu (the header's own user menu) - not a popover
   in this item's sense (an explanatory aside), and `adr/0030`'s fourth amendment reasons explicitly
   about why that menu did not yet justify a headless library.

   **Closed, 2026-09-12 (`25-54`, `adr/0030`'s fifth amendment).** Eight standing explanatory
   paragraphs across the three-panel workspace move behind a new, hover/focus-triggered `Tooltip`
   component - the console's twelfth, the exact trigger this ADR's own Alternatives section named for
   reopening the closed set. No popover (an explanatory aside separate from a trigger control) exists
   yet - that half of this item's own title stays open.

5. **No progress bar, no chart, no sparkline, no meter.** Four report screens and no figure treatment.
   Decision 7 has just made those screens carry more numbers, not fewer.

6. **No multi-select, no combobox, no searchable select.** The transfer-target picker (`23-18`) and the
   tenant switcher both want one; both currently do without.

7. **No grid or columns helper, no responsive utility.** Every multi-column layout is hand-rolled.
   This is the one that decides whether "mobile-first" is a rewrite or a setting.

8. **Badge is the product's only representation of a person** — no avatar, no initial, no name. This
   one is downstream of decision 1: once operators have names, the question is whether they get a
   face.

   **Answered 2026-09-12 (`25-47`).** A circular avatar showing the operator's initials
   (`operatorInitials`, `src/auth/operatorInitials.ts`) is now the header's whole right side. Initials,
   never a photo — nothing in this identity system carries one (Keycloak's `profile.picture` is not
   requested and no upload path exists), so there is no fallback state an image-based avatar would
   need. Closed.

9. **Three surfaces are outside the design system entirely** — the widget (its own one-file styling),
   the Keycloak screens (sign-in, registration, password reset — the *first* thing a new tenant sees),
   and `ago-landing`, which `tokens.css` names as the source of the console's palette and which the
   bundle could not preview. Whether the system is meant to cover them is a scope decision nobody has
   taken.

10. **No unrecoverable-error state, and no offline state for the application.** When permissions fail
    to load, the screen shows nothing in particular. The realtime link has states; the app does not.

---

## What this changes about the number

Thirty-seven sounds like a backlog. It is three deletions, roughly twenty that close as a
side-effect of work already sliced or already coming, and **ten questions**.

All ten are open again as of 2026-09-06. Item 3, the icon question, was answered narrowly by `23-24`
on 2026-09-05 and **re-opened by `23-31`/`adr/0129` one day later** — the answer was one glyph for one
meaning, and `23-31` replaced that meaning, so the glyph went with it. That is worth more than the
count: an answer tied to a single rule lasts exactly as long as the rule does.

Ten was a conversation, and it is the same shape as the nine that produced `decisions.md`: options,
a recommendation, an answer recorded so the next item cannot quietly contradict it. Nine remain that
shape; item 3 was answered by necessity rather than by the pass, which is why it reads differently
above — narrow enough that it did not need the author's own conversation the other nine still do.

**None of the ten blocks stage 23.** They shape how its screens look, not whether its mechanisms can
be built — so the slice can land while the (now nine) rest are still open.
