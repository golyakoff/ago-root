# ADR-0012: Multiple repositories, platform published as packages

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 0
- **Supersedes**: the single-solution layout assumed by ADR-0003 (its modular-monolith reasoning stands)

## Context

ADR-0003 established a platform/product split enforced by an arch test inside one solution. An arch
test forbids the illegal reference; it does not make it impossible, and it says nothing about whether
the platform's API is stable enough to be called an API. The components also have genuinely different
release cadences: a widget embedded on shops we do not control cannot be forced to update, while a
backend deploy is ours to schedule.

## Decision

Each component is its own repository: `ago-platform`, `ago-chat`, `ago-widget`, `ago-console`,
`ago-deploy`, and this docs repository. The platform ships as **versioned NuGet packages**; products
consume them. The hosts (Api, Worker, Webhooks) live in the product repository, because a host must
reference the product module it composes, and the dependency arrow must not invert.

A new repository is justified only when the thing versions or deploys independently. Splitting the
platform per adapter is rejected for now: it multiplies the version matrix with no independent consumer.

## Consequences

- The platform physically cannot reference a product - the strongest possible form of the rule.
- The platform gets a version and a changelog, which forces its surface to be designed rather than
  accreted.
- The widget can be released on its own cadence, which is a real requirement, not a preference.
- Cost: a change spanning platform and product is two branches, two merge requests, a version bump
  and a package publish. This is the main price, and it is paid on every cross-cutting change.
- Cost: local development needs a file-based feed and a documented `ProjectReference` dev override,
  plus the discipline that no merged branch keeps the override.
- Cost: a reviewer needs several links instead of one. The docs repository is the entry point and
  must say so.

## Alternatives considered

- **One repository, one solution** - the simplest thing, and what most portfolio projects do. It
  keeps cross-cutting changes atomic, and it leaves the platform boundary resting entirely on an arch
  test that any future session could delete.
- **One repository, several solutions** - keeps atomic commits and separates build units, but the
  platform still has no version and the product can always reach into its source.
- **Git submodules** - repository separation with a shared checkout, and a well-earned reputation for
  pain that would not buy us anything the package boundary does not.
