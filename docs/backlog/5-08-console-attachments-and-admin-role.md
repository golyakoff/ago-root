# Console: attachments UI and the admin/supervisor role

- **Stage**: 5
- **Status**: done
- **Depends on**: `5-03-attachments-upload-and-download.md`, `5-04-attachment-thumbnails-and-orphan-
  sweep.md`, `5-07-console-conversation-experience.md`

## Goal

Two related closeouts `authorization.md` already named as belonging to Stage 5's console work: an
operator can attach and view files in a conversation, and an admin/supervisor role exists with
`site:configure`/`site:manage_operators` and (the moderation action paired with it) `attachment:delete`
- the console is the first thing that actually needs either permission to exist for real.

## Context to read first

`authorization.md`'s "Permissions and roles beyond Stage 1" section - the admin-role and
`attachment:delete` bullets in full, they already state the reasoning; do not re-derive it. `adr/0016`
- how a new permission and role get added to the existing RBAC model (the pattern `1-02`/`1-06`
established, not a new mechanism). `5-03`'s attachment endpoint shapes for the upload/download calls
this UI drives. `file-storage.md`'s "Validation and safety" - the CSP/`Content-Disposition` behaviour
the console's own attachment viewer must respect (never render a downloaded file as if it were trusted
same-origin content).

## Scope

- `Permission.SiteConfigure`/`Permission.SiteManageOperators` (or whatever exact names `adr/0016`'s
  existing catalogue implies - match its naming convention) and an `"Admin"` role, seeded the same way
  `1-05`'s `"Operator"` role was, granted only via the seed script or (if this item's own scope grows
  to need it) a minimal role-assignment surface in the console itself - decide and state which, since
  `adr/0016` left "who can grant the Operator role itself" ungranted by anything but the seed script,
  and this item is where that gap either gets closed or explicitly deferred again.
- `Permission.AttachmentDelete`, checked the same way every other permission check already is
  (`IPermissionChecker`), on a new delete endpoint/handler (`ago-chat`) this console item calls -
  small addition to `5-03`'s surface, scoped here rather than there because it has no reason to exist
  before an admin role can use it.
- Admin console views: every conversation for a site (not just this operator's own assigned ones -
  the distinguishing feature of the admin role per `authorization.md`), and the attachment-delete
  action in the message thread for users holding it.
- Attachment UI in the ordinary conversation view (from `5-07`): upload with progress (from the PUT
  itself, not a fake progress bar), inline preview using the thumbnail `5-04` generates, download via
  the presigned URL `5-03` issues.

## Out of scope

- Any permission or role beyond the two named above - `authorization.md` explicitly deferred
  `conversation:transfer` to Stage 4 (already shipped or explicitly skipped there, confirm which before
  assuming it is still open) and `attachment:upload`/`attachment:view` as separate permissions were
  explicitly rejected in the same doc; do not resurrect either without a new reason.
- A general role-editor UI (arbitrary custom roles/permission combinations) - `adr/0016`'s Consequences
  already flagged this as future work, not named as a Stage 5 deliverable.

## Done when

- [x] `Ago.Chat.Integration.Tests`/`Application.Tests`: the new permission(s) and role are seeded and
      checked the same way `PermissionCheckerTests` already proves the existing ones.
- [x] `attachment:delete` actually deletes (row + storage object via `IFileStorage.DeleteAsync`, same
      "tolerate already-gone" reasoning `5-04`'s sweeper uses) and is denied to an operator without the
      permission.
- [x] Manually verified against the local cluster: an admin account sees every conversation for its
      site; an ordinary operator account does not; an admin can delete an attachment an ordinary
      operator cannot.
- [x] Manually verified: uploading an attachment from the console, sending it, and viewing it (with
      thumbnail) works end to end against the real backend chain (`5-02`-`5-04`).
- [x] `authorization.md`'s admin-role and `attachment:delete` bullets get a "Shipped in `5-08`" note,
      moved out of the "deliberately deferred" list.

## Open questions

None - scope and naming both follow directly from `authorization.md`'s own already-written reasoning;
the only real decision (role-grant surface) is scoped as part of the item itself, above.
