# the navigation becomes seven sections instead of one strip of twenty-four

- **Stage**: 23
- **Status**: done (2026-09-06). Seven sections behind a two-level accordion, nineteen routes moved
  with eighteen redirects, and `adr/0129` in place of `23-24`'s muting rule. Deployed the same day.
- **Depends on**: nothing. `23-32`…`23-37` reserve places in the structure this item builds and can land after it in any order.
- **Decision**: the author's, 2026-09-06, from a design pass against Jivo's console. Needs **`adr/0129`** for the one part that changes a shipped rule.

## Goal

An operator opens the console and sees four things they can act on. A tenant opens it and finds the
setting they came for without reading twenty-four labels.

## What is actually true today, measured rather than felt

**Twenty-four entries in one horizontally scrolling strip.** The design system already describes it:
*"a flat list of up to 21 items… no grouping, no section heading, no submenu, no break between chat,
settings, calendar and platform"*, and `shell.css`'s own comment records the measurement that produced
the drawer — the bar **"does not fit fifteen items at this width"**. It is now twenty-four, so this
passed the point where it stopped fitting nine entries ago.

The product tagline is hand-maintained from a list of five routes and is **already wrong**: eight of
the thirteen tenant screens are not in it, so somebody on `/settings/tags` reads "Operator console".

## The shape, decided

**Left column, sections expand as an accordion — one open at a time, both levels vertical.** Vertical
rather than tabs across the top because a section with sixteen items breaks a narrow screen, and this
console is used on a phone as well as at a desk.

**Seven sections**, and the count is deliberate: it buys the disappearance of the third level
everywhere except one subheading, so nothing is more than two clicks deep.

| Section | What is in it |
|---|---|
| Диалоги | Мои · Все диалоги · Поиск |
| Аналитика | Мои показатели · Аналитика · Конверсия · Отчёт по меткам · Запись через чат |
| Календарь *(module)* | Мастера · Услуги · Расписание · В ожидании · Записи · Клиенты · Настройка |
| Команда | Сотрудники · Общение |
| Каналы | Установка виджета · Виджет на сайте · Бот MAX · Бот Telegram · Другие каналы |
| Автоматизация | Готовые ответы · ИИ-подсказки · Автоответ офлайн · ИИ-автоответ · ИИ-помощник по вопросам · Метки |
| Администрирование | Продукты · Оплата · Данные на устройстве · Документы · Удалить аккаунт |

**The header says "Офис" and nothing else.** The Operator/Client/Owner tagline goes, and the
five-route `useMatch` list that maintained it goes with it — a hand-maintained list that is already
incomplete is worse than no label.

**The calendar runs from its dictionaries to its results**: who and what and when, then what came of
it, then configuration last.

## The part that changes a shipped decision, and needs `adr/0129`

`23-24` decided that an entry the operator lacks is **drawn muted** rather than hidden, so that
*"you cannot do this"* and *"nobody granted you this"* do not render as the same absence.

**That rule is replaced: muted means "you can obtain this yourself."**

- **A tenant** sees muted entries for modules they can **buy** — the calendar, the AI features. Muting
  becomes an honest label on the upsell, not a permissions hint.
- **An operator sees nothing muted at all.** Their tenant granted what it chose to grant; nothing here
  depends on the operator, so an entry they can neither use nor obtain is noise.

**The cost, stated because `23-24` was right about it:** an operator no longer learns that a feature
exists, so they cannot think to ask for it. Accepted knowingly — the operator's console gets
dramatically shorter, and no action ever hung on that knowledge. This is exactly the trade `adr/0129`
has to record, because the next person to read `23-24` will otherwise think it still holds.

## The half that is easy to forget

**Nineteen of the existing routes move.** `/admin` → `/conversations/all`, `/settings/*` splits into
`/channels/*`, `/automation/*` and `/account/*`, `/calendar/availability` → `/calendar/schedule`, and
so on. Every one needs a redirect from the old address: tenants have bookmarks, our own runbooks and
`ui-inventory.md` cite these paths, and `smoke.sh` checks some of them.

A restructure that lands without redirects is a restructure that breaks every link anybody saved.

## Scope

- The shell: left column, accordion on both levels, "Офис" in the header, the tagline logic deleted.
- The seven sections and their contents, exactly as tabled above.
- The muting rule replaced, with `adr/0129` recording what `23-24` decided and why it changed.
- **Redirects for all nineteen moved routes**, and `smoke.sh` and `ui-inventory.md` updated to the new
  paths in the same change.
- Reserved places for what does not exist yet — `Записи`, `Общение`, the three channel screens,
  `ИИ-подсказки`, `ИИ-автоответ`, `Документы` — drawn as unavailable rather than omitted, so the
  structure does not have to be rebuilt when each arrives.

## Out of scope

- Building any of the reserved screens. Each is its own item.
- The calendar's own service dictionary gaining price and description — `23-35`, and it is a question
  before it is work.
- `/owner`. The platform owner's own screens keep their separate place.

## Done when

- [x] An operator with no tenant-level permissions sees exactly four sections, and nothing muted.
- [x] A tenant without the calendar sees it muted with a label saying it can be bought, not hidden.
- [x] Every one of the nineteen moved routes answers on its old address with a redirect.
- [x] Nothing is more than two clicks from the rail, and the accordion keeps one section open.
- [x] `ui-inventory.md` names the new paths, and the tagline's five-route list is gone.
      **`smoke.sh` needed no change**, checked rather than assumed: it addresses hostnames and API
      routes, and references no console SPA path at all. The item's own scope expected otherwise.
- [x] `adr/0129` records the replaced muting rule, including what `23-24` was protecting against.

## Reference

The agreed mock, with every screen's current and proposed address and what each screen does:
`https://claude.ai/code/artifact/49d80db9-127d-42e9-b43d-985c20a24dde`

## One naming rule, decided 2026-09-06 rather than left open

**Every entry under Каналы is named for the channel it is, not for the action it performs**: «Виджет
на сайте», «Бот MAX», «Бот Telegram», «Другие каналы». The first draft called the widget's own screen
«Внешний вид», which stopped making sense the moment the "Виджет на сайте" subheading was removed —
one word next to «Бот MAX» does not say whose appearance it is.

**«Установка виджета» is the exception and stays one**, above the list: it is a task rather than a
channel. It is done once and never returned to, which is also why it is first and why the empty queue
still calls for it while `SiteInstallationState` is `NotSeenYet`.

## Outcome

**Shipped and deployed 2026-09-06** — `ago-console#130`, this change for the documents it made false.
The strip of twenty-four became seven sections; the header says "Офис"; eighteen of the nineteen moved
routes redirect, and the nineteenth deliberately does not, because `/calendar/setup` keeps answering
with a smaller version of the same screen rather than moving wholesale.

**Two defects the ux-gate found that reading did not**: a bare `1fr` grid track at the mobile
breakpoint let a wide table scroll the page itself instead of its own container, and a `useMatch`
collision gave `/conversations/all` the workspace's fixed layout, because `all` satisfies
`/conversations/:conversationId`.

**And one the gate found only because I stopped believing my own green run.** The gate passed locally
and failed in CI. `playwright.config.ts` sets `reuseExistingServer: !CI`, so repeat local runs were
served by a preview server still holding an older bundle; `CI=1` reproduced it every time. The failure
was not timing — the console rendered an **empty `<body>`**, because two APIs answer
`/api/v1/me/tenancies` with different shapes, the calendar's reader got the chat's body, and
`tenantName.trim()` threw during render. The fixture is fixed here; the blast radius is `23-41`, filed
as a question rather than an answer.

**What is not covered, recorded rather than glossed:** `App.tsx`'s wiring of the redirect table into
its real `<Routes>` tree has no automated test, because rendering it means going through
`OperatorConnectionProvider` and its real SignalR connection. What stands instead is that there is one
`MOVED_ROUTES.map(...)` call rather than eighteen hand-copied elements.

**Out of scope and now stale:** `docs/design/design-system/shell.html`, whose nav specimen still shows
twenty-one flat items.
