# the auto-deletion exemption is attached to a tier name instead of to payment

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-73`, which is the auto-deletion itself and is **not built yet** — which is why this is cheap.
- **Found**: 2026-09-08, checking whether `adr/0160` contradicted anything already decided. It did.

## What the rule says, and what it does

The commercial grid states auto-deletion twice, under two different headings:

- Free tier: **the account is deleted if nobody signs in for three months.**
- Paid tier: **there is no auto-deletion for inactivity while payment continues.**

The exemption is written **under the paid tier's heading**, so by its letter it belongs to the *name of
a tier* rather than to the *fact of payment*.

`adr/0160` makes that difference real. An account can now be on the free tier **and paying** — a
tenant whose subscription lapsed keeps a channel they are still being charged for, and a free-tier
tenant may buy one outright. Read literally, that account is deleted for not signing in for three
months: its conversations, its contacts, its attachments and its consent record, while its card is
being charged every month.

**Deleting a paying customer's data is the worst outcome this system can produce**, and it would be
produced by a rule that is correct about everything except which noun it attaches to.

## Why it is cheap right now

`23-73` — the auto-deletion — is `ready` and explicitly *"a question before it is work"*. Nothing
deletes anything today. So this is a specification correction ahead of the implementation, not a
defect in production, and it costs a sentence in the right place instead of an incident.

The grid already worried about the neighbouring case: *"пишут, но в консоль никто не заходит три
месяца — мы удалим работающий сервис"*. This is the sharper version of the same concern — not merely a
service that works, but one that is paid for.

## Scope

- **The exemption attaches to payment, not to a tier name.** An account with any subscription in an
  active state is not deleted for inactivity, whatever its tier is called.
- **`23-73` inherits the corrected rule** rather than the original one. If `23-73` is designed first,
  it must be designed against this.
- **The commercial record is corrected too**, in the private repository, by the author. That text is
  theirs and is not written from here; this item names what needs saying, not the words.

## Where this is likely to go wrong

- **"Active" needs defining once and shared.** A subscription that is `PastDue` is still a paying
  relationship in trouble, not an absent one — deleting during a seven-day retry window would be the
  same mistake in miniature. Whatever `23-73` decides, this and that must use one definition.
- **The tier name will remain the tempting check**, because it is one column and it reads well. It is
  the wrong column, and the reason is on record here.
- **Do not widen this into `23-73`.** What gets deleted, after how long, and with what warning are that
  item's questions. This one only says which accounts are exempt.

## Done when

- [ ] No path can delete an account that has an active paid subscription, whatever tier it is on.
- [ ] `23-73` is written against the corrected rule rather than the original.
- [ ] The definition of "active" is stated once and used by both.
