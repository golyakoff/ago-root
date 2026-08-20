# AGO Platform

> **Status: design phase.** No application code yet. The architecture, decisions and development plan
> are written; implementation starts at Stage 0 of `docs/roadmap.md`. This README is rewritten for a
> reviewer audience at Stage 7, once there are real numbers to put in it.

**AGO Platform** is a backend platform — hosting, realtime transport, messaging, persistence,
caching, object storage, observability. **AGO Chat** is the first product on it: a customer-support
chat that a shop embeds with one script tag. **AGO Ads** is the planned second product, and exists
mainly to keep the platform boundary honest.

It is a portfolio project. It is built to demonstrate concurrency, database work under load,
message-broker work, and Clean Architecture — in a form another engineer can review.

## Stack

.NET 10 · ASP.NET Core Minimal API + SignalR · PostgreSQL (EF Core writes, Dapper reads) · RabbitMQ
(Kafka in Stage 8) · Redis · S3/MinIO · Kubernetes · OpenTelemetry · k6

## Where to read

| | |
|---|---|
| What it is and why | [docs/vision.md](docs/vision.md) |
| How it is shaped | [docs/architecture/overview.md](docs/architecture/overview.md) |
| Why decisions were made | [docs/adr/](docs/adr/) |
| What gets built, in what order | [docs/roadmap.md](docs/roadmap.md) |
| Rules for contributors and AI sessions | [CLAUDE.md](CLAUDE.md), [SKILLS.md](SKILLS.md) |

## How this repository is worked on

Implementation is done in AI sessions (Claude Code) driven by the rules in this repository:
[CLAUDE.md](CLAUDE.md) holds the non-negotiables, [SKILLS.md](SKILLS.md) indexes the procedures, and
`docs/adr/` keeps decisions stable across sessions that share no memory. That tooling is public on
purpose — directing this kind of work reproducibly is part of what the project demonstrates.

## Honesty notes

Kept here deliberately, and expanded at Stage 7:

- Several things are hand-built that a production team should take off the shelf — the outbox,
  retries and dead-lettering (MassTransit does this well), and cross-node delivery (the SignalR Redis
  backplane does this in three lines). They are hand-built because demonstrating the mechanism is the
  point of the project; the ADRs say so.
- No performance number appears anywhere in this repository until Stage 6 measures it on stated
  hardware and writes it into `load/reports/`.
