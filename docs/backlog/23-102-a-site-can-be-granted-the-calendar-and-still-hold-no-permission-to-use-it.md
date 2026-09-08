# a site can be granted the calendar and still hold no permission to use it

- **Stage**: 23
- **Status**: ready — **and the first question in it is where the permission should come from**
- **Depends on**: nothing. `adr/0151` draws the line this falls through.
- **Found**: 2026-09-08, on the first real module grant this system has ever performed.

## What happened

The platform owner granted the calendar to site `01a06262`. The grant succeeded — `enabled_modules`
has its row, the calendar provisioned its own tenant, everything `23-65`, `23-87` and `23-66` built
worked exactly as designed.

The tenant's own owner then opened the calendar and was told:

> У вас нет прав на просмотр очереди бронирований календаря.

The message is **correct**. That account holds both seeded roles, and neither carries a calendar
permission:

- **Admin**: `site:configure`, `site:manage_operators`, `attachment:delete`, `site:erase`,
  `conversation:erase`, `site:export` — **no `calendar:configure`**
- **Operator**: `conversation:read`, `send`, `assign`, `note_write`, `tag` — **no `booking:*`, no
  `customer:read`**

`CalendarQueuePage` requires any of `booking:confirm`, `booking:reject`, `booking:cancel` (`23-57`).
Nothing in either role grants one.

## Why this was inevitable rather than unlucky

`22-05` added the calendar permissions to `RegisterSiteHandler`'s seeded sets — `booking:*` and
`customer:*` to Operator, `calendar:configure` to Admin. **Roles are seeded once, at registration, and
never revisited.** So `22-05` reached every site registered after it and no site registered before.

**On the demo stand, four of ten sites are in that state.** It is not an edge case, it is the older
half of the tenant base.

## The gap `adr/0151` leaves, said plainly

That ADR separates two layers deliberately: an **entitlement** says the account may use a capability,
a **permission** says this person may act for the account. It is right, and this item is the seam
between them nobody has had to look at until a grant actually succeeded.

**A grant creates the entitlement. Nothing creates the permission.** So the platform owner can sell
the calendar, the tenant can pay for it, and no human being can open it.

## The question this opens with

Three readings, and it is not obvious which is right:

- **Grant-time.** Enabling a module for a site ensures that site's roles carry the permissions the
  module needs. Closest to the moment the need becomes true, and it means a purchase is usable
  immediately. But it makes a grant write to roles, which is a tenant's own sandbox under `adr/0151` —
  the ADR would need to say whether that is a violation or the intended shape.
- **A backfill.** Something brings every existing site's roles up to the current seeded set, once.
  Fixes today's four and any future gap of the same kind, but it is a one-off unless something keeps
  running it, and it decides for tenants what their roles contain.
- **The tenant grants it themselves.** Most consistent with `adr/0151` — the account has the
  entitlement, its administrator decides who may use it — but **there is no screen for editing a
  role's permissions**, and `23-72` added changing which role an operator holds, not what a role
  carries. This reading is only available if that screen is built.

**Do not pick one by implementing it.** The stand has a live tenant blocked on this, so the temptation
to write the rows and move on is real; doing that answers the question in the dark.

## Where this is likely to go wrong

- **`22-28` is a different backfill.** That one is about the role-assignment projection reaching the
  calendar's own database. This is about what the roles contain in chat's. Adjacent, not the same.
- **The message the tenant sees is accurate and unhelpful.** It tells them to ask an administrator —
  and they *are* the administrator, and the administrator has no way to grant it. Whatever is chosen,
  that sentence needs to stop being a dead end.
- **Whichever reading wins, the existing four sites still need fixing**, and that is a separate act
  from deciding the mechanism.

## Done when

- [ ] The reading is chosen by the author and recorded where a reader will find it.
- [ ] A site that has been granted the calendar has somebody who can open it.
- [ ] The four sites already in this state are fixed, and how many there were is written down.
