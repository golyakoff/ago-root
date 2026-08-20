# Architecture Decision Records

One file per decision a reviewer could reasonably argue with. Numbered, and immutable once accepted:
a decision that changes gets a **new** ADR superseding the old one, and the old one stays with its
status updated. Rewriting history here destroys the only artefact showing how the design was reasoned about.

Write an ADR when a technology is chosen over an alternative, a guarantee is weakened or strengthened,
a boundary is crossed deliberately, or a reviewer would ask "why on earth". Do not write one for
naming, formatting, or anything a convention doc already covers.

| # | Decision | Status |
|---|---|---|
| 0001 | Record architecture decisions | Accepted |
| 0002 | Clean Architecture layering and the dependency rule | Accepted |
| 0003 | Platform/product split, modular monolith, two hosts | Accepted |
| 0004 | PostgreSQL, EF Core for writes, Dapper for reads | Accepted |
| 0005 | Transactional outbox for reliable publishing | Accepted |
| 0006 | Broker abstraction at topic + partition key + at-least-once | Accepted |
| 0007 | Connection registry instead of a SignalR backplane | Accepted |
| 0008 | Presigned direct-to-storage uploads | Accepted |
| 0009 | Redis is a cache and coordination store, never truth | Accepted |
| 0010 | No sticky sessions at the edge | Accepted |
| 0011 | All instants are UTC `DateTimeOffset`, rendered per request | Accepted |
| 0012 | Multiple repositories, platform published as packages | Accepted |
| 0013 | Three deployables split by failure profile; webhooks as a bulkhead | Accepted |
