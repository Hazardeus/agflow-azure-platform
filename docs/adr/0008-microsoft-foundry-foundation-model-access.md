# ADR-0008 — Microsoft Foundry Foundation and Model Access

## Status

Accepted

## Context

Milestone 6 introduces the Azure foundation required for model access:
Claude, Codex/Azure-OpenAI-compatible coding models, and embedding models,
per `docs/STATUS.md`. The current Microsoft Foundry resource model,
verified against live Azure Resource Manager schema and this subscription's
actual catalog/quota state (not documentation assumptions alone), is:

```text
Microsoft.CognitiveServices/accounts        kind = AIServices
└── Microsoft.CognitiveServices/accounts/projects
```

No legacy AI Hub/Workspace resource is required or used.

## Decision

### Resource model and API versions

- `Microsoft.CognitiveServices/accounts@2026-05-01` (stable)
- `Microsoft.CognitiveServices/accounts/projects@2026-05-01` (stable)
- `Microsoft.CognitiveServices/accounts/deployments@2026-05-01` (stable)

No preview API versions are used.

### Topology

One Foundry account and one named project per environment, in
`rg-agflow-platform-{environment}`:

- Account: `aif-agflow-{environment}-${uniqueString(subscription().id)}`
  (also used as `customSubDomainName`, which must be globally unique)
- Project: `proj-agflow-{environment}` (e.g. `proj-agflow-lab`)

No additional projects are introduced without a concrete isolation or
lifecycle requirement, consistent with the "one foundational resource"
pattern already used for shared storage (ADR-0005).

### Foundry account identity

The Foundry account is created with:

```text
identity: { type: SystemAssigned }
properties: { allowProjectManagement: true }
```

This is a resource-bound System Assigned Managed Identity required by
Foundry itself for project-management operations. It is independent of,
and does not replace, `id-agflow-control-plane-lab`. No RBAC role is
assigned to this identity — it is created because the platform requires
it, not because a concrete consumer need exists. If a real need for this
identity to access another Azure resource is identified in a future
milestone, permissions will be added then, not speculatively.

The project's own identity remains `None`. No requirement for a
project-level identity has been identified.

### Authentication and RBAC

Entra ID / Managed Identity authentication only. No API keys are issued
or used by any consumer.

| | |
|---|---|
| Role | Foundry User |
| Role definition ID | `53ca6127-db72-4b80-b1b0-d745d6d5456d` |
| Assignee | `id-agflow-control-plane-lab` (existing UAMI, no new identity) |
| Scope | the Foundry account only |

`disableLocalAuth = true` on the account. No Contributor, no Cognitive
Services Contributor, and no resource-group-level RBAC are granted, per
least privilege.

### Networking

`publicNetworkAccess = Enabled` for Milestone 6 only. This is an explicit,
temporary posture, not an oversight: authentication remains Entra/RBAC
based regardless of network exposure, and no data-plane children beyond
the project and model deployments exist to widen the exposure surface.
Private Endpoints, Private DNS, and any network restructuring are
strictly Milestone 7 scope and are not introduced here.

### Claude hosting choice

Both Azure-hosted and Anthropic-hosted Claude models are Anthropic
(non-Microsoft) products distributed through the Azure Marketplace model
flow, regardless of which infrastructure serves inference. For Milestone 6
LAB validation, `claude-haiku-4-5` version `2` (Azure-hosted, GA,
`GlobalStandard`) is approved: Azure-hosted per architectural preference,
generally available, backed by real quota in this subscription/region, and
the lowest-cost validation choice. Azure-hosted `claude-opus-5` and any
future Azure-hosted Sonnet-tier quota remain documented escalation paths
for later milestones or application-level needs, not implemented now.

Marketplace/Anthropic commercial-terms acceptance for Claude:

- is explicit and performed manually by a human, never automated in Bicep
  or any script in this repository;
- is a deployment gate scoped only to the Claude model deployment — it
  does not block the account/project foundation or the non-Anthropic
  model deployments.

### Model deployment ownership

Bicep owns three durable, version-pinned model deployments as part of
Milestone 6, deployed as a second phase after the account/project
foundation is reviewed:

| Deployment | Model | Version |
|---|---|---|
| Claude | `claude-haiku-4-5` | `2` |
| Coding | `gpt-5.3-codex` | `2026-02-24` |
| Embeddings | `text-embedding-3-large` | `1` |

No deployment uses `"latest"`. Moving to a newer model version requires an
explicit future Bicep change, consistent with the deterministic-naming
principle already established in ADR-0002.

### Quota / commercial gates

- Claude: manual Marketplace/Anthropic terms acceptance, performed by a
  human, before the Claude deployment only.
- OpenAI Direct-from-Azure models (`gpt-5.3-codex`, `text-embedding-3-large`):
  governed by standard Microsoft Product Terms; no Marketplace offer
  acceptance required.
- All deployments use pay-per-token/serverless (`GlobalStandard`/`AOAI`);
  no provisioned throughput is introduced.

## Consequences

### Positive

- keyless, Entra-only inference access for the control-plane identity;
- deterministic, collision-free account/project naming;
- explicit, auditable separation between the Foundry-required system
  identity and the application-consuming identity;
- version-pinned model deployments avoid silent behavior changes;
- Claude's Marketplace/commercial nature is explicit, not hidden behind
  "just another model deployment".

### Negative

- `publicNetworkAccess = Enabled` is a temporary exposure until Milestone 7;
- the `Foundry User` role's `Microsoft.CognitiveServices/*` data action is
  broader than the narrowest theoretically possible grant, but is the
  Microsoft-documented role for this scenario and no finer-grained built-in
  role exists;
- Claude deployment cannot be automated end-to-end due to the manual
  Marketplace/commercial gate.

## Alternatives considered

### Cognitive Services User role instead of Foundry User

Rejected on architecture review: `Foundry User` is the role intended for
Foundry account/project data-plane access and was verified as the correct
built-in role for this scenario.

### Deferring all model deployments to a later milestone

Rejected: Milestone 6's goal includes proving real inference capability,
not just standing up the account/project shell. Deployments are
implemented as an explicit second phase of the same milestone instead.

### Sonnet-tier Claude for LAB

Rejected for now: no Azure-hosted Sonnet-tier quota exists in this
subscription/region today. Anthropic-hosted Sonnet remains a documented,
not-yet-adopted alternative if Sonnet-level quality is required later.
