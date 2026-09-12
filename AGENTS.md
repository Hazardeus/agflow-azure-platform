# AI Agent Instructions

This repository contains the Azure platform foundation for ag-flow.

## Required context

Before making changes, read:

1. `docs/ARCHITECTURE.md`
2. `docs/STATUS.md`
3. `docs/DEVELOPMENT.md`
4. Relevant ADRs under `docs/adr/`
5. Any scoped instructions applicable to the files being changed.

Do not assume architectural decisions that are not documented.

## Infrastructure ownership

- Bicep owns long-lived Azure infrastructure.
- devpod-ui/OpenTofu owns ephemeral workspace infrastructure.
- Docker Compose owns applications deployed on the control-plane VM.

A resource must never be managed by both Bicep and OpenTofu.

## Development principles

- Work incrementally.
- Do not generate the full infrastructure at once.
- Explain architectural changes before implementing them.
- Never deploy unless explicitly requested.
- Never commit secrets.
- Validate Bicep changes with lint/build.
- Use `what-if` before Azure deployment.

## Documentation discipline

Documentation is part of the implementation.

Before completing a meaningful change:

- update `docs/STATUS.md` if project state changed;
- update `docs/ARCHITECTURE.md` if the current architecture changed;
- create or update an ADR when an architectural decision is made;
- update operational documentation when commands or deployment procedures change.

Do not create ADRs for trivial implementation details.

## Architecture Decision Records

Create an ADR when a decision:

- affects infrastructure boundaries;
- introduces or replaces a major Azure service;
- changes networking or security posture;
- changes ownership between Bicep, OpenTofu, or Docker Compose;
- introduces a significant dependency;
- is difficult or costly to reverse.

ADRs live under `docs/adr/`.

Never silently rewrite an accepted ADR.
Supersede it with another ADR when the decision changes.

## Current work

Read `docs/STATUS.md` before starting work.

Do not start a later project phase unless the current milestone is complete
or the user explicitly requests it.