# Project Status

This document records the current implementation state of the `agflow-azure-platform` repository.

It is intentionally concise and should describe:

* what is currently implemented;
* what is being worked on;
* what the next milestone is;
* what has explicitly not started yet.

It is not a work log and must not duplicate Git history.

For architectural decisions, see [`adr/`](adr/).

For the current target architecture, see [`ARCHITECTURE.md`](ARCHITECTURE.md).

For the development workflow, see [`DEVELOPMENT.md`](DEVELOPMENT.md).

---

## Current phase

**Milestone 6 — Microsoft Foundry**

Status: **Completed**

Milestones 1 (Resource Groups), 2 (shared network foundation), 3
(Managed Identities and RBAC), 4 (Shared Storage), 5 (Control-plane VM),
and 6 (Microsoft Foundry, including Codex, embeddings, and Claude model
deployments) are all implemented, deployed to LAB, and post-deployment
verified. Milestone 7 (Private networking) has not started.

---

## Completed

### Repository foundation

* GitHub repository created.
* Repository cloned locally.
* Git configured for the appropriate GitHub identity.
* `.gitignore` configured.
* Initial repository structure created.

### Multi-agent development setup

The repository is structured so that different coding agents can work from the same canonical project knowledge.

Current model:

* `AGENTS.md`

  * canonical, tool-agnostic AI development instructions;
* `.github/copilot-instructions.md`

  * GitHub Copilot adapter;
* `.github/instructions/bicep.instructions.md`

  * Bicep-specific scoped instructions;
* `CLAUDE.md`

  * Claude Code adapter.

The intention is that GitHub Copilot, OpenAI Codex, and Claude Code all consume the same project architecture, status, governance, and ADRs rather than maintaining separate architectural instructions.

### Documentation foundation

The following documentation structure has been established:

* `docs/ARCHITECTURE.md`
* `docs/DEVELOPMENT.md`
* `docs/STATUS.md`
* `docs/adr/README.md`
* `docs/adr/0001-iac-ownership-boundaries.md`

### Architecture governance

The infrastructure ownership model has been defined and recorded in:

[`ADR-0001 — Infrastructure ownership boundaries`](adr/0001-iac-ownership-boundaries.md)

The core ownership rule is:

> A resource must never be managed by both Bicep and OpenTofu.

Current ownership boundaries:

* **Bicep**

  * long-lived Azure platform infrastructure;
* **devpod-ui / OpenTofu**

  * ephemeral workspace infrastructure;
* **Docker Compose**

  * applications running on the control-plane VM.

### Bicep foundation

The initial Bicep structure exists:

```text
infra/
├── main.bicep
├── bicepconfig.json
├── modules/
└── environments/
    └── lab/
        └── main.bicepparam
```

Current characteristics:

* root deployment scope is `subscription`;
* default Azure region is `swedencentral`;
* environment is parameterized;
* `lab`, `dev`, and `prod` are valid environment names;
* environment-specific values are stored in `.bicepparam`;
* no secrets are stored in Bicep source or parameter files;
* `infra/modules/resource-groups.bicep` declares the two platform Resource
  Groups (Milestone 1, deployed — see below).

The current Bicep skeleton has been successfully validated with the Bicep compiler and analyzer.

### Milestone 1 — Azure Resource Groups

Status: **Completed**

Implemented and deployed:

* `rg-agflow-platform-lab`
* `rg-agflow-workspaces-lab`

Validation completed:

* Bicep lint
* Bicep build
* Bicep parameter build
* subscription-level Azure `what-if`
* Azure deployment
* post-deployment verification

### Milestone 2 — Networking

Status: **Completed**

Implemented and deployed:

* `vnet-agflow-lab`
* `snet-control`
* `snet-workspaces`
* `snet-private-endpoints`
* `nsg-agflow-control-lab`
* `nsg-agflow-workspaces-lab`

Validation completed:

* Bicep lint
* Bicep build
* Bicep parameter build
* subscription-level Azure `what-if`
* Azure deployment
* post-deployment network verification

Outbound connectivity remains intentionally deferred according to ADR-0003.

### Milestone 3 — Managed Identities and RBAC

Status: **Completed**

Implemented per [ADR-0004](adr/0004-managed-identities-rbac.md):

* `id-agflow-control-plane-lab` (user-assigned managed identity, no RBAC
  assignments in Milestone 3);
* `id-agflow-workspace-provisioner-lab` (user-assigned managed identity),
  granted:
  * **Virtual Machine Contributor** (`9980e02c-c2be-4d73-94e8-173b1dc7cf3c`)
    scoped to `rg-agflow-workspaces-lab`;
  * custom role **Agflow Workspace Subnet Joiner**
    (`Microsoft.Network/virtualNetworks/subnets/read`,
    `Microsoft.Network/virtualNetworks/subnets/join/action` only) scoped
    only to `snet-workspaces`.

Both identities are created in `rg-agflow-platform-lab`. New modules:
`infra/modules/identities.bicep`, `infra/modules/rbac-workspace-rg.bicep`,
`infra/modules/rbac-workspace-subnet.bicep`.

Validation completed:

* Bicep lint
* Bicep build
* Bicep parameter build
* subscription-level Azure `what-if`
* Azure deployment
* post-deployment verification

Post-deployment verification confirmed against live Azure state:

* `id-agflow-control-plane-lab` exists with no role assignments;
* `id-agflow-workspace-provisioner-lab` exists with exactly:
  * **Virtual Machine Contributor** on `rg-agflow-workspaces-lab`;
  * **Agflow Workspace Subnet Joiner** on `snet-workspaces`;
* the custom role contains exactly subnet `read` and `join/action`;
* a subsequent idempotence `what-if` showed no unexpected create/delete
  operations (the recurring UAMI `isolationScope` diff is known `what-if`
  noise and not an actual drift).

### Milestone 4 — Shared Storage

Status: **Completed**

Implemented per [ADR-0005](adr/0005-shared-storage-foundation.md) and
deployed to LAB:

* Storage account `stagflowlab56xw4a7zc653` — `StorageV2`, `Hot` access
  tier, in `rg-agflow-platform-lab`;
* SKU `Standard_LRS` for LAB, parameterized per environment;
* security baseline: HTTPS only, minimum TLS 1.2, anonymous Blob access
  disabled, Shared Key authorization disabled, Entra ID/OAuth enabled as
  the default authentication mode, cross-tenant replication disabled,
  network ACL `defaultAction: Allow` / `bypass: None` (no trusted-services
  exception);
* Blob versioning enabled; Blob soft delete enabled with 7-day retention
  for LAB (parameterized); permanent deletion of soft-deleted data
  disabled; Blob static website hosting disabled;
* no containers, file shares, queues, tables, lifecycle policy, workload
  RBAC assignments, or Private Endpoints — all deferred to the milestone
  that introduces a concrete consumer.

New module: `infra/modules/storage.bicep`.

Validation completed:

* Bicep lint
* Bicep build
* Bicep parameter build
* subscription-level Azure `what-if`
* Azure deployment
* post-deployment verification
* second idempotence `what-if`

The idempotence `what-if` reported 2 to modify, 11 no change — the two
Modify entries are the known `isolationScope` false positives on
`id-agflow-control-plane-lab` and `id-agflow-workspace-provisioner-lab`
(already noted under Milestone 3), not actual drift. The Storage Account
and `blobServices/default` reported no change.

### Milestone 5 — Control-plane VM

Status: **Completed**

Deployed to LAB per [ADR-0006](adr/0006-control-plane-compute-persistence-lab-egress.md)
and [ADR-0007](adr/0007-lab-control-plane-vm-sizing-adjustment.md):

* `vm-agflow-control-lab` — Ubuntu 24.04 LTS Gen2, `Standard_D2as_v5` Spot
  (LAB-specific sizing, see ADR-0007), `Deallocate` eviction, Trusted Launch
  with Secure Boot and vTPM, password authentication disabled, Azure-managed
  boot diagnostics;
* `pip-agflow-control-lab` — Standard static IPv4 for explicit LAB egress
  only, paired with an explicit `Deny-Internet-Inbound` rule (priority 100)
  on `nsg-agflow-control-lab`;
* `nic-agflow-control-lab` — single IP configuration in `snet-control`;
* `disk-agflow-control-data-lab` — independent 128 GiB `StandardSSD_LRS`
  managed disk, `Attach`/LUN 0/`Detach`, mounted at `/srv/agflow`;
* both existing UAMIs (`id-agflow-control-plane-lab`,
  `id-agflow-workspace-provisioner-lab`) attached; no new RBAC introduced;
* host bootstrap (`infra/bootstrap/control-plane-cloud-init.yaml`) installs
  Docker Engine and Compose v2 from Ubuntu's distribution-signed packages;
  no application stack deployed.

Post-deployment verification confirmed against live Azure and guest state:

* all Azure resources match the reviewed `what-if` (identities, NSG rule,
  Public IP, NIC, data disk, VM configuration);
* the persistent data disk and its filesystem UUID survived a full VM
  deletion and Bicep-driven recreation, confirmed via a before/after
  checksum-verified marker file;
* Docker Engine and Docker Compose v2 verified installed and active, with
  zero application containers;
* RBAC unchanged (control-plane identity has no role assignments;
  workspace-provisioner's existing RBAC scope is untouched; no Storage
  Account RBAC introduced);
* a final idempotence `what-if` reported 0 Create / 0 Delete / 0 replacement,
  with only known benign Azure-computed default properties remaining as
  Modify (UAMI `isolationScope`, managed-disk/NIC/PIP default sub-properties,
  OS disk reported as Ignore).

New module: `infra/modules/control-plane-compute.bicep`. Modified:
`infra/modules/networking.bicep` (NSG rule only; the module remains the sole
owner of `nsg-agflow-control-lab`).

---

### Milestone 6 — Microsoft Foundry

Status: **Completed**

Design accepted per [ADR-0008](adr/0008-microsoft-foundry-foundation-model-access.md)
and [ADR-0009](adr/0009-foundry-project-managed-identity.md).

**Phase 1 — Foundry foundation: deployed to LAB, post-deployment verified.**

* `aif-agflow-lab-{uniqueString}` — `Microsoft.CognitiveServices/accounts`
  (`kind: AIServices`, `sku: S0`), `identity: SystemAssigned` (required by
  Foundry for `allowProjectManagement`; independent of the control-plane
  UAMI, no RBAC granted to it), `disableLocalAuth: true`,
  `publicNetworkAccess: Enabled` (temporary M6 posture, see ADR-0008);
* `proj-agflow-lab` — one named `accounts/projects` child, `identity:
  SystemAssigned` (ADR-0009, matches current Foundry project-creation
  guidance; no RBAC granted to it);
* RBAC: **Foundry User** (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) granted to
  the existing `id-agflow-control-plane-lab`, scoped to the Foundry account
  only — no Contributor, no RG-level access, no new identity;
* no model deployments yet.

New module: `infra/modules/foundry.bicep`.

Post-deployment verification confirmed against live Azure state:

* the Foundry account and project match the reviewed `what-if` (`kind:
  AIServices`, `sku: S0`, both `identity: SystemAssigned`,
  `allowProjectManagement: true`, `disableLocalAuth: true`,
  `publicNetworkAccess: Enabled`, `customSubDomainName` matches the
  deterministic account name);
* exactly one **Foundry User** role assignment exists, scoped to the
  Foundry account only, principal `id-agflow-control-plane-lab` — no
  RG-level or subscription-level assignment for this identity;
* both Foundry `SystemAssigned` identities (account and project) carry
  **zero** explicit role assignments each, confirming no speculative RBAC
  was introduced;
* zero `accounts/deployments` exist under the Foundry account — Phase 2
  has not started;
* a subsequent idempotence `what-if` reported 0 Create / 0 Delete / 0
  Replace, with only known benign Azure-computed default/read-only
  properties remaining as Modify (the previously documented UAMI
  `isolationScope`/managed-disk/NIC/PIP noise, plus two new same-class
  entries: the account's `associatedProjects`/`defaultProject`/`a365*`
  fields and the project's `kind`/`endpoints`/`internalId`/`isDefault`
  fields, all populated only once the resources actually exist).

**Phase 2 — model deployments, split into sub-phases:**

* **M6-B1 (Codex + embeddings): Complete.**
  `mdl-codex-lab` (`gpt-5.3-codex`, version `2026-02-24`, `GlobalStandard`,
  capacity `10`) and `mdl-embedding-lab` (`text-embedding-3-large`, version
  `1`, `GlobalStandard`, capacity `120`) — both `NoAutoUpgrade`, capacities
  are RP-provided defaults (Azure exposes no minimum/step for either
  model). Both confirmed `provisioningState: Succeeded` /
  `deploymentState: Running` against live Azure state; the Foundry
  account's RBAC remains exactly the one existing **Foundry User**
  assignment — no RBAC, networking, or identity changes beyond the two
  child `accounts/deployments` resources. Sibling deployments are now
  serialized in Bicep (`embeddingDeployment` explicitly `dependsOn`
  `codexDeployment`) after the initial deployment surfaced a transient
  Cognitive Services RP sibling-resource concurrency conflict
  (`RequestConflict`); a subsequent idempotence `what-if` reported
  0 Create / 0 Delete / 0 Replace, with only known benign Azure-computed
  properties remaining as Modify. Managed-Identity inference smoke tests
  passed from `vm-agflow-control-lab`, explicitly using
  `id-agflow-control-plane-lab` (never the workspace-provisioner identity),
  no API keys: Codex Responses API returned a valid completion (HTTP 200);
  embeddings returned a 3072-dimension vector (HTTP 200, after Azure's
  documented data-plane propagation delay following deployment).
* **M6-B2 (Claude): Complete.**
  `mdl-claude-lab` (`Anthropic`/`claude-haiku-4-5`/version `2`,
  Azure-hosted, `GlobalStandard`, capacity `10` — RP-provided default,
  `NoAutoUpgrade`), serialized in Bicep after `embeddingDeployment`. Uses
  `properties: any({...})` to carry `modelProviderData`
  (`organizationName`/`countryCode`/`industry`, operator-supplied via
  environment variables, never committed), a confirmed Microsoft spec
  gap: the RP requires this block for Claude but it is absent from the
  typed `2026-05-01` schema; the stable API was kept (no preview switch).
  Both required human gates were satisfied before deployment: the
  operator confirmed successful interactive Claude access in the same
  Foundry environment/subscription (Marketplace/commercial acceptance),
  and the three attestation environment variables were supplied.
  Deployed and confirmed `provisioningState: Succeeded` /
  `deploymentState: Running` against live Azure state; RBAC remains
  exactly the one existing **Foundry User** assignment; `mdl-codex-lab`
  and `mdl-embedding-lab` unchanged. A subsequent idempotence `what-if`
  reported 0 Create / 0 Delete / 0 Replace, only known benign
  Azure-computed properties as Modify. Managed-Identity smoke test
  passed from `vm-agflow-control-lab`, explicitly using
  `id-agflow-control-plane-lab`, no API keys: the Claude Messages API
  (`https://aif-agflow-lab-56xw4a7zc653a.services.ai.azure.com/anthropic/v1/messages`,
  `anthropic-version: 2023-06-01`) returned a valid, non-empty response
  (HTTP 200) on the first attempt.

All three M6 model categories (Codex, embeddings, Claude) are deployed to
LAB and Managed-Identity inference smoke tests have passed for each,
satisfying the Milestone 6 completion criterion.

---

## Planned milestones

The current intended implementation order is:

### Milestone 1 — Resource Groups

Create:

* `rg-agflow-platform-{environment}`
* `rg-agflow-workspaces-{environment}`

### Milestone 2 — Networking

Create the shared Azure network foundation:

```text
vnet-agflow
10.20.0.0/16

├── snet-control
│   └── 10.20.1.0/24
│
├── snet-workspaces
│   └── 10.20.2.0/24
│
└── snet-private-endpoints
    └── 10.20.3.0/24
```

Include the required NSGs and network ownership boundaries.

### Milestone 3 — Managed Identities and RBAC

Introduce:

* control-plane Managed Identity;
* DevPod workspace provisioning identity;
* minimum required RBAC assignments.

The workspace provisioning identity must not receive broad permissions over the platform resource group.

### Milestone 4 — Shared storage

Introduce durable Azure storage required by the platform, backups, or shared platform services.

### Milestone 5 — Control-plane VM

Deploy the initial control-plane compute in Sweden Central.

Current LAB target:

```text
Ubuntu 24.04
Standard_D2as_v5
Spot
Eviction policy: Deallocate
```

`Standard_D4as_v5` was the original target; ADR-0007 changed the initial LAB
size because of the Sweden Central Spot vCPU quota.

The VM will host the Docker Compose control-plane stack.

### Milestone 6 — Microsoft Foundry

Provision the Azure foundation required for model access.

Target capabilities include:

* Claude models;
* Codex / Azure OpenAI compatible models;
* embedding models.

Exact model deployments and quotas must be verified against current Microsoft Foundry availability at implementation time.

### Milestone 7 — Private networking

Introduce private connectivity where justified:

* Private Endpoints;
* Private DNS;
* Foundry private access;
* other private platform services as required.

### Milestone 8 — DevPod / OpenTofu integration

Connect `devpod-ui` OpenTofu workspace lifecycle to the Azure foundation created by Bicep.

Bicep should expose the required platform contract, such as:

* subscription ID;
* workspace resource group;
* workspace subnet ID;
* location;
* Managed Identity references.

OpenTofu must consume existing shared infrastructure rather than recreate it.

---

## Not started

The following components have intentionally not been implemented yet:

* Private Endpoints;
* Private DNS;
* DevPod/OpenTofu Azure integration;
* Docker Compose deployment;
* Harpocrate;
* Docflow;
* RAG;
* MCP Manager;
* Knowledge Compiler;
* Qdrant;
* Neo4j.

This is intentional.

The platform is being built incrementally.

---

## Application deployment target

Now that the Azure control-plane VM exists, Docker Compose will eventually own the application runtime:

```text
Control-plane VM
│
├── ag-flow stack
│   ├── devpod-ui / Portal
│   ├── Docflow
│   ├── RAG
│   ├── PostgreSQL / pgvector
│   ├── Homepage
│   └── Caddy
│
├── Harpocrate
│   └── PostgreSQL
│
└── MCP Manager
    ├── MCP capability catalog
    ├── Skills catalog
    └── PostgreSQL / pgvector
```

These applications must not be modeled as Azure resources in Bicep.

---

## Workspace target

Workspace infrastructure will eventually be created dynamically by `devpod-ui` using its existing OpenTofu implementation.

Expected profiles include:

```text
coding-small
Standard_D2as_v5 Spot

coding-medium
Standard_D4as_v5 Spot

coding-large
Standard_D8as_v5 Spot
```

These VMs are ephemeral infrastructure and remain outside Bicep ownership.

---

## Key architecture decisions

Current accepted decisions:

* [ADR-0001 — Infrastructure ownership boundaries](adr/0001-iac-ownership-boundaries.md)
* [ADR-0002 — Environment-aware Azure resource naming](adr/0002-environment-resource-naming.md)
* [ADR-0003 — Shared network foundation and outbound connectivity](adr/0003-shared-network-foundation.md)
* [ADR-0004 — Managed Identities and workspace provisioning RBAC](adr/0004-managed-identities-rbac.md)
* [ADR-0005 — Shared Storage Foundation](adr/0005-shared-storage-foundation.md)
* [ADR-0006 — Control-plane Compute, Persistence and LAB Egress](adr/0006-control-plane-compute-persistence-lab-egress.md)
* [ADR-0007 — LAB Control-plane VM Sizing Adjustment](adr/0007-lab-control-plane-vm-sizing-adjustment.md)

Future major architectural decisions should be captured as ADRs when they affect areas such as:

* Azure networking;
* identity and RBAC;
* control-plane compute;
* Microsoft Foundry integration;
* private connectivity;
* secrets management;
* persistent storage;
* major platform dependencies.

---

## Validation policy

For every Bicep milestone:

```text
change
  ↓
lint
  ↓
build
  ↓
review
  ↓
Azure what-if
  ↓
review what-if
  ↓
explicit deployment approval
  ↓
deployment
```

A successful compile is not sufficient authorization to deploy.

---

## Current next action

Milestone 5 is complete: the LAB control-plane VM is deployed and verified
per ADR-0006 and ADR-0007.

Begin Milestone 6 — Microsoft Foundry: provision the Azure foundation
required for model access, per the
[Planned milestones](#planned-milestones) scope above. Milestone 6 must
start with design, model/region availability, and quota validation before
any implementation.
