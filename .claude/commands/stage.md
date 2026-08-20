---
description: Start work on a roadmap stage - read state, plan the slices, propose the order
---

Prepare work for roadmap stage: $ARGUMENTS

1. Read `docs/roadmap.md` for that stage's goal, deliverables and "done when".
2. Read the architecture docs it depends on, and the ADRs that constrain it.
3. Inspect the repo to establish what already exists — do not assume the previous stage finished.
4. Produce an ordered list of vertical slices, each small enough for one branch, with dependencies
   between them made explicit.
5. Flag anything in the stage that needs a decision from the author before code can start, and any
   deliverable you believe is mis-scoped.
6. Write each slice as a file in `docs/backlog/` using the format in `docs/backlog/README.md`.

Do not start implementing. Do not commit.
