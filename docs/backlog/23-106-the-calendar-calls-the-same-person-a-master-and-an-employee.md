# the calendar calls the same person a master in the menu and an employee on the screen

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing.
- **Found**: 2026-09-08, by the author, opening the screen for the first time.

## What is inconsistent

The navigation entry reads **«Мастера»**. The screen it opens reads:

> Сотрудники
> Сотрудников пока нет.
> Добавить сотрудника

`ru.ts` carries **twenty-four** occurrences of «сотрудник» against three of «мастер», and one of those
three is the nav entry itself.

## Why it is not a matter of taste

**The two words were separated on purpose.** The author's own reason: a calendar's staff are
**мастера** precisely so nobody confuses them with the people answering chat, who are **операторы**.
A tenant reading «сотрудник» on a calendar screen cannot tell which of the two populations it means —
and that tenant may well have both, since one account can hold both products.

So this is not a synonym chosen carelessly. It is the one distinction the vocabulary exists to draw,
collapsed on the screen where it matters most.

## Scope

- **Every calendar-facing string says «мастер»** where it means a person on a calendar. The English
  side keeps `worker`, which is already consistent — this is a Russian-copy problem.
- **«Оператор» stays untouched**, and stays chat's. The point is the distinction, not a global rename.
- **Check the screens as well as the strings.** A label read from a shared component may print the
  wrong noun without a string of its own.

## Where this is likely to go wrong

- **`operators` is also a table name and a permission prefix** (`site:manage_operators`). Nothing here
  touches those; this is user-facing copy only, and a rename that reaches an identifier has overrun.
- **`ru.ts` and `en.ts` must stay in step** — `11-16`'s gate — but the two languages are not
  symmetrical here: English already says `worker` throughout, so the change is one-sided by nature.
- **The booking-facing surfaces too.** A visitor picking a time sees this vocabulary; the widget and
  the public booking page are part of the sweep, not only the console.

## Done when

- [x] A person on a calendar is called «мастер» everywhere a tenant can read. The widget names no
      staff at all (no such string in `ago-widget/src`), and `ago-calendar-console` carries no
      Russian copy whatsoever - so neither surface could be inconsistent. That second absence is a
      real gap, but it is localisation, not vocabulary, and belongs to the console-i18n line.
- [x] Nothing that means a chat operator has been renamed. `navOperatorsTeam` keeps «Сотрудники»
      deliberately - `23-31` chose that word for chat's own team, and with the calendar now reading
      «Мастера» the distinction the two words exist to draw is actually drawn.
- [x] The screens are checked, not only the string file: no hard-coded Russian staff noun exists
      in any `.tsx`, so every occurrence a tenant sees comes from the strings that were changed.
