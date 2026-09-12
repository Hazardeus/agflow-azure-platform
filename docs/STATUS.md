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

**Phase 0 — Repository and Bicep foundation**

Status: **In progress**

The repository structure, development governance, multi-agent instructions, architectural boundaries, and minimal Bicep foundation are being established before the first Azure resource is created.

No Azure infrastructure has been deployed by this repository yet.

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
  Groups (Milestone 1, not yet deployed — see below).

The current Bicep skeleton has been successfully validated with the Bicep compiler and analyzer.

---

## Current milestone

### Milestone 0 — Establish project baseline

Objective:

Create a clean, committed baseline containing:

* repository governance;
* multi-agent instructions;
* architecture documentation;
* development workflow;
* ADR mechanism;
* Bicep skeleton;
* environment parameter structure.

Before this milestone is considered complete:

* all baseline files must be tracked in Git;
* Bicep lint/build validation must pass;
* generated ARM JSON must not be unintentionally committed;
* the baseline must be committed and pushed.

---

## Next milestone

### Milestone 1 — Azure Resource Groups

Status: **In progress**

The first infrastructure implementation will create only:

```text
rg-agflow-platform-{environment}
rg-agflow-workspaces-{environment}
```

The change must:

1. be implemented in Bicep;
2. preserve subscription-level deployment scope;
3. introduce appropriate common tags;
4. compile successfully;
5. pass Bicep linting;
6. be reviewed before deployment;
7. be validated using subscription-level Azure `what-if`.

No actual Azure deployment should occur until the `what-if` output has been reviewed.

Implemented so far:

* `infra/modules/resource-groups.bicep` defines both Resource Groups with
  environment-aware names per ADR-0002 and the common/purpose tags;
* `infra/main.bicep` invokes the module and exposes the Resource Group
  names/IDs as outputs;
* `az bicep lint`, `az bicep build`, and `az bicep build-params` (lab) all
  pass with no errors or warnings.

Remaining before this milestone is complete:

* review the subscription-level `what-if` output;
* explicit approval and deployment.

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

Initial target:

```text
Ubuntu 24.04
Standard_D4as_v5
Spot
Eviction policy: Deallocate
```

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

* Azure Resource Groups;
* VNet;
* subnets;
* NSGs;
* Managed Identities;
* RBAC;
* Azure storage;
* control-plane VM;
* Microsoft Foundry resources;
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

Once the Azure control plane exists, Docker Compose will eventually own the application runtime:

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

Complete and commit the repository baseline.

After that, begin **Milestone 1 — Resource Groups** and implement only:

```text
rg-agflow-platform-{environment}
rg-agflow-workspaces-{environment}
```

No networking, identities, VM, storage, Foundry, or DevPod resources should be introduced during that milestone.
