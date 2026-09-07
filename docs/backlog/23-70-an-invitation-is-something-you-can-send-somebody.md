# an invitation is something you can send somebody

- **Stage**: 23
- **Status**: ready — **the link is work; the e-mail is a decision, named below**
- **Depends on**: nothing for the link half.
- **Found**: 2026-09-07, by the author using the screen: *«Я ждал хотя бы ссылки или поля ввода для
  почты, куда она отправится. А что делать с этим инвайтом?»*

## What the screen does today

Команда → Сотрудники → «Пригласить коллегу» produces a bare token — `invite_2Zv…` — shown once, with
an expiry, and nothing else. No link, no destination, no instruction.

**The question the author asked is the defect**: a person who has just created an invitation does not
know what to do with it. The screen ends where the task begins.

## The link half, which is ordinary work

- **The invitation is a URL**, not a token — something that can be pasted into whatever the tenant
  already uses to talk to their colleague, and that lands the colleague somewhere that explains itself.
- **Copying it is one action**, and the screen says plainly that it is shown only once.
- **The landing page tells the colleague what they are accepting** — which shop, from whom, and that it
  expires. A stranger opening a link they were sent should not have to guess.
- **The expiry is already there** and should be visible on the link, not only at creation.

## The e-mail half, which is a decision and not a task

The author expected a field to type an address into. That is a reasonable expectation and it is a
bigger thing than it looks.

**This deployment sends no mail to anybody outside it.** `adr/0045` is a zero-credential Postfix on the
node used for operational alerts to ourselves; `25-03` reused it today for exactly that. `adr/0040`
already rejected every third-party mail provider considered, on payment and data-residency grounds.

So *«отправить приглашение на почту»* means: customer-facing mail, from our infrastructure, to a
stranger's inbox — which brings deliverability, SPF and DKIM for the sending domain, bounces, and what
happens when a shop's colleague never receives it and nobody knows. **None of that is hard. All of it
is a decision nobody has taken**, and it is the same decision that will be needed for a booking
confirmation, a password reset and every other message this product will eventually want to send.

**Recommendation: ship the link, and take the mail decision on its own terms** — because the link is
useful on its own and because deciding how this product sends mail deserves better than being settled
inside an invitation screen.

## Where this is likely to go wrong

- **A link is a credential.** Anyone holding it can join the tenant as whatever role it carries. It is
  already a one-time, expiring token, and putting it in a URL does not change that — but it does make
  it more likely to end up in a chat history, a ticket, or somebody's clipboard manager. Say what the
  expiry is and keep it short.
- **The landing page is reachable by strangers**, so it must not leak anything about the tenant beyond
  what a person being invited needs to see.

## Done when

- [ ] Creating an invitation produces a link a person can send, with an obvious way to copy it.
- [ ] The screen says what to do with it and that it will not be shown again.
- [ ] A colleague opening the link sees what they are joining and when it expires.
- [ ] The e-mail question is recorded as its own decision rather than answered by implication here.
