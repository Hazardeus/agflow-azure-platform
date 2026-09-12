---
name: azure-platform-milestone
description: 'Standard milestone workflow for the agflow-azure-platform repository. Use when implementing or continuing a milestone, changing Bicep infrastructure under infra/ or infra/modules/, adding managed identities/RBAC/networking, deciding whether an ADR is needed, running az bicep lint/build/build-params, running Azure what-if, or preparing/reviewing an Azure deployment for this repo. Enforces ADR-0001 IaC ownership boundaries (Bicep vs OpenTofu vs Docker Compose), gates implementation on resolved architecture questions, and never deploys without explicit approval.'
argument-hint: 'Optional: milestone number or description of the change'
---

# Azure Platform Milestone Workflow

## When to Use

- Starting or continuing work on a milestone in `docs/STATUS.md`.
- Adding or modifying Bicep resources/modules in `infra/`.
- Any change to networking, identities, RBAC, or a major Azure service.
- Deciding whether an ADR is required for a change.
- Running Bicep validation, Azure `what-if`, or an Azure deployment for this repo.

## Required Reading (always, before any work)

1. `AGENTS.md`
2. `docs/ARCHITECTURE.md`
3. `docs/STATUS.md`
4. `docs/DEVELOPMENT.md`
5. Relevant ADRs under `docs/adr/` (index in `docs/adr/README.md`)
6. Relevant existing modules under `infra/modules/` that the change touches, plus `infra/main.bicep`

## Ownership Boundaries (ADR-0001) — never violate

- **Bicep**: durable Azure platform infrastructure.
- **devpod-ui / OpenTofu**: ephemeral workspace infrastructure.
- **Docker Compose**: applications running on the control-plane VM.
- A resource must never be managed by both Bicep and OpenTofu.

## Workflow

### 1. Determine the current milestone

Read the "Current phase" / "Current milestone" section of `docs/STATUS.md`. Do not start a later milestone unless the current one is complete or the user explicitly requests it.

### 2. Design review before implementation

Before writing any code:

- Summarize the intended change and how it maps to the current milestone's scope.
- Identify which `infra/modules/*.bicep` files and `infra/main.bicep` wiring are affected.
- Surface architectural questions or ambiguities and get them resolved with the user.

**Do not implement while architectural questions remain open.**

### 3. ADR requirement gate

Create an ADR under `docs/adr/` (next sequential number, following the existing file pattern) **before implementation** when the change:

- affects infrastructure ownership boundaries;
- introduces or replaces a major Azure service;
- changes networking or security posture;
- changes identity or RBAC strategy;
- changes the Bicep / OpenTofu / Docker Compose boundary;
- introduces a significant dependency;
- is difficult or costly to reverse.

Do not create ADRs for trivial implementation details. Never silently rewrite an accepted ADR — supersede it with a new one.

### 4. Implement only the milestone scope

- Touch only the modules relevant to the current milestone.
- Do not scaffold resources for future milestones (see "Planned milestones" in `docs/STATUS.md`).
- Follow `.github/instructions/bicep.instructions.md` for Bicep style.

### 5. Update documentation when needed

- Update `docs/STATUS.md` as the milestone progresses (implemented → validated → deployed → completed).
- Update `docs/ARCHITECTURE.md` when the resulting architecture changes — it describes current state, not history.
- Do not create AI activity logs or work journals duplicating Git history.

### 6. Local Bicep validation (mandatory before any deployment step)

Run, in order:

```powershell
az bicep lint --file infra/main.bicep
az bicep build --file infra/main.bicep
az bicep build-params --file infra/environments/lab/main.bicepparam
```

### 7. Stop on validation failure

If any command fails, stop, report the failure and relevant diagnostics, and fix it. Do not proceed to `what-if` or deployment with a failing validation.

### 8. Deployment gating

- Never run a real `az deployment ... create` automatically.
- Only run `az deployment sub what-if` when the user explicitly requests it, or after implementation and validation are complete and have been reviewed.

### 9. What-if review

Run:

```powershell
az deployment sub what-if `
  --location swedencentral `
  --template-file infra/main.bicep `
  --parameters infra/environments/lab/main.bicepparam
```

Review the output for unexpected Create/Modify/Delete operations, especially anything outside the current milestone's scope. Report anomalies to the user before proceeding — do not proceed past an unreviewed or surprising diff.

### 10. Explicit approval required before deployment

Do not run `az deployment sub create` (or any equivalent apply) without an explicit, unambiguous instruction from the user to deploy this specific change.

### 11. Post-deployment checks

After a real deployment, verify deployed resources match intent (e.g. checks against identities, RBAC role assignments, or network resources appropriate to the milestone).

### 12. Idempotence check

Run a second `az deployment sub what-if` after deployment. It should report no changes (or only expected no-ops). Investigate any unexpected diff before continuing.

### 13. Mark the milestone Completed

Only after implementation, validation, what-if review, deployment, post-deployment checks, and the idempotence what-if all pass, update `docs/STATUS.md` to mark the milestone **Completed**.

## Quality Checklist

- [ ] Required docs and ADRs read
- [ ] Architectural questions resolved before implementation
- [ ] ADR created if any gating criterion is met
- [ ] Only current milestone scope touched
- [ ] `lint` / `build` / `build-params` pass
- [ ] `what-if` reviewed, no unexpected diffs
- [ ] Explicit deploy approval obtained (if deploying)
- [ ] Post-deployment checks done (if deployed)
- [ ] Second `what-if` confirms idempotence (if deployed)
- [ ] `STATUS.md` / `ARCHITECTURE.md` updated
