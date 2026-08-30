# Text commands

What counts as a command inside a visitor's or an operator's own message text, how it is matched, and
how two different kinds of command vocabulary stay from colliding with each other.

## Syntax

A command is the message body's own **first whitespace-delimited token**, optionally prefixed with `/`,
followed by zero or more further whitespace-separated arguments (`/linkidentity telegram`). The leading
slash is always shown in anything this system generates for a human to type or tap - system-generated
instructions, canned-response-style quick-inserts, this document's own examples - because it is the
convention every messaging platform this project integrates with already trains visitors on (Telegram's
own bot commands are the direct model: `TriggerCommandMatcher`'s own remarks name it explicitly). Parsing
itself tolerates the slash being absent on input, the same `TrimStart('/')` `TriggerCommandMatcher`
already applies to both sides of the comparison - a visitor who types `linkidentity 4821` without the
slash is not refused for a punctuation choice.

## Matching

**Exact, case-insensitive, whole-first-token - never a substring or a fuzzy match.** `20-07`/`adr/0065`
decision 6 states the reason once and it holds for every command this system will ever add, not only
module triggers: "a visitor who types 'I'd like to book' gets no special treatment; they use the entry
point like a menu." A command is something a visitor deliberately invokes, not a phrase this system goes
looking for inside ordinary text - matching only the first token is what keeps a command word from
firing because it happened to appear mid-sentence.

## Two vocabularies, never one parser

This system has, and will likely keep having, more than one *kind* of command, and they are kept
structurally separate rather than merged into one parser or one word list:

- **Module triggers** - a site's own configured words that open a module task (`TriggerCommandMatcher`,
  sourced from `IEnabledModuleReadStore`). Per-site, per-module, data-driven; `Ago.Chat.*` does not know
  what any of them mean.
- **Chat's own built-in commands** - a fixed, closed, product-level vocabulary that ships with AGO Chat
  itself and means the same thing on every site (`/linkidentity`, `14-12`). Never sourced from a site's
  own configuration, never module-routed.

A visitor's message is checked against exactly one of these, decided by which use case is asking - a
module trigger only matters where `RouteConversationToModuleHandler` already looks for one (an existing
conversation with no active task); a Chat-native command's own use case decides for itself where it
applies (`14-12`'s own confirmation branch, for one, fires ahead of the ordinary inbound-message path
entirely, on an address with no identity yet). **The two vocabularies must never be allowed to collide
in the first place** - not resolved by a runtime precedence rule between two matches, which would make
the outcome depend on which check happened to run first. A site registering a module trigger word that
collides with a reserved Chat-native command name is refused at registration time
(`EnableModuleForSite`'s own validation), the same "catch it once, at the boundary, not every time a
message arrives" discipline this codebase already applies elsewhere. The reserved list is exactly the
set of Chat's own built-in command names, kept in one place a registration check and a test can both
read from.

## Adding a new command

State, in the new use case's own doc comment, which of the two vocabularies it belongs to and why -
`14-12`'s own remarks are the template. If it is a Chat-native command, add its name to the reserved
list `EnableModuleForSite` checks against, and prove the collision refusal with a test, the same way any
other reserved-word list in this codebase is proven rather than trusted.
