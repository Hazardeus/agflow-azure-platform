# ag-flow Azure Platform Architecture

## 1. Purpose

This repository defines the long-lived Azure platform foundation for the ag-flow environment.

The platform is intended to provide:

* a stable Azure control plane;
* dynamic development workspaces;
* centralized AI model access;
* structured knowledge management;
* semantic retrieval;
* MCP capability discovery and runtime access;
* secret management;
* a future enterprise Knowledge Compiler architecture.

The primary Azure region is:

```text
Sweden Central
```

Azure resource location:

```text
swedencentral
```

This document describes the intended architecture and current architectural boundaries.

Implementation progress is tracked separately in [`STATUS.md`](STATUS.md).

Development rules are defined in [`DEVELOPMENT.md`](DEVELOPMENT.md).

Architecture decisions are recorded under [`adr/`](adr/).

---

## 2. Architecture principles

The platform follows several core principles.

### Clear infrastructure ownership

A resource must have exactly one infrastructure owner.

The most important rule is:

> A resource must never be managed by both Bicep and OpenTofu.

The ownership decision is formally recorded in:

[ADR-0001 — Infrastructure ownership boundaries](adr/0001-iac-ownership-boundaries.md)

### Separate infrastructure lifecycles

The platform has two fundamentally different infrastructure lifecycles:

```text
Long-lived platform infrastructure
               │
               ▼
             Bicep


Ephemeral workspace infrastructure
               │
               ▼
      devpod-ui / OpenTofu
```

Stable platform resources should not be destroyed when a development workspace is deleted.

### Separate infrastructure from application deployment

Azure infrastructure and application containers are managed independently:

```text
Bicep
→ Azure infrastructure

Docker Compose
→ control-plane applications

devpod-ui / OpenTofu
→ ephemeral workspace infrastructure
```

### Incremental delivery

Infrastructure is implemented capability by capability rather than generated as one large deployment.

Each milestone should be:

```text
implemented
→ validated
→ reviewed
→ what-if
→ explicitly approved
→ deployed
```

---

## 3. Infrastructure ownership

### Bicep

Bicep owns long-lived Azure platform infrastructure.

Expected responsibilities include:

* Resource Groups;
* Virtual Network;
* shared subnets;
* Network Security Groups;
* Managed Identities;
* RBAC;
* shared Azure storage;
* control-plane VM;
* Microsoft Foundry foundation;
* future Private Endpoints;
* future Private DNS infrastructure.

Bicep does not own ephemeral development workspace VMs.

---

### devpod-ui / OpenTofu

`devpod-ui` already contains OpenTofu-based workspace lifecycle management.

OpenTofu owns ephemeral workspace infrastructure:

* workspace VM;
* workspace NIC;
* workspace-specific disk;
* workspace provisioning;
* workspace destruction;
* workspace recreation after Spot eviction where appropriate.

OpenTofu consumes the shared Azure foundation created by Bicep.

It must not recreate shared infrastructure such as:

* the platform VNet;
* shared subnets;
* platform resource groups;
* Foundry;
* shared identities;
* control-plane infrastructure.

---

### Docker Compose

Docker Compose owns applications running on the control-plane VM.

Expected applications include:

* devpod-ui / Portal;
* Docflow;
* RAG;
* PostgreSQL / pgvector;
* Harpocrate;
* MCP Manager;
* Caddy;
* supporting frontend services.

These application workloads are not modeled as Bicep resources.

---

## 4. High-level architecture

The intended platform architecture is:

```text
                         Azure — Sweden Central
                                  │
        ┌─────────────────────────┴──────────────────────────┐
        │                                                    │
        ▼                                                    ▼
 Long-lived platform                              Ephemeral workspaces
       Bicep                                      devpod-ui / OpenTofu
        │                                                    │
        │                                            ┌───────┼───────┐
        │                                            ▼       ▼       ▼
        │                                           D2      D4      D8
        │                                          Spot    Spot    Spot
        │
        ▼
┌─────────────────────────────────────────────┐
│ Azure platform foundation                   │
│                                             │
│ Resource Groups                             │
│ VNet + subnets                              │
│ NSGs                                        │
│ Managed Identities / RBAC                   │
│ Storage                                     │
│ Control-plane VM                            │
│ Microsoft Foundry                           │
│ Future Private Endpoints / DNS              │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
              Control-plane VM
                       │
                Docker Compose
                       │
        ┌──────────────┼─────────────────┐
        │              │                 │
        ▼              ▼                 ▼
      ag-flow       Harpocrate       MCP Manager
        │
   ┌────┼────┐
   ▼    ▼    ▼
Portal Doc  RAG
```

---

## 5. Azure resource organization

Two primary Resource Groups are planned.

```text
rg-agflow-platform-{environment}
```

contains durable platform infrastructure such as:

* VNet;
* control-plane VM;
* Foundry;
* shared storage;
* platform Managed Identities;
* future Private Endpoints and DNS resources.

```text
rg-agflow-workspaces-{environment}
```

contains ephemeral workspace infrastructure managed by DevPod/OpenTofu:

* workspace VMs;
* workspace NICs;
* workspace disks.

This separation reinforces both lifecycle and RBAC boundaries.

---

## 6. Networking architecture

The planned Azure network is:

```text
vnet-agflow-lab                     10.20.0.0/16
│
├── snet-control                    10.20.1.0/24
│   ├── defaultOutboundAccess=false
│   └── nsg-agflow-control-lab
│
├── snet-workspaces                 10.20.2.0/24
│   ├── defaultOutboundAccess=false
│   └── nsg-agflow-workspaces-lab
│
└── snet-private-endpoints          10.20.3.0/24
    ├── defaultOutboundAccess=false
    ├── privateEndpointNetworkPolicies=Enabled
    └── no NSG initially
```

Milestone 2 does not provision outbound Internet connectivity.

The platform must not rely on implicit Azure outbound access.
The outbound mechanism will be selected when the first workload requiring
public Internet access is introduced, with lab cost efficiency considered explicitly.

See [ADR-0003](adr/0003-shared-network-foundation.md).

### `snet-control`

Hosts durable control-plane compute.

Initial expected workload:

* control-plane VM.

### `snet-workspaces`

Hosts dynamically created DevPod workspace VMs.

The subnet itself is owned by Bicep.

Workspace NICs connected to the subnet are owned by OpenTofu.

### `snet-private-endpoints`

Reserved for future Azure Private Endpoints.

Keeping this subnet separate avoids later restructuring when private connectivity is introduced.

---

## 7. Control-plane compute

The initial control plane is intentionally simple.

Target starting configuration:

```text
Ubuntu 24.04
Standard_D4as_v5
4 vCPU
16 GiB RAM
Spot
Eviction policy: Deallocate
```

The exact VM SKU remains parameterized.

The initial strategy avoids AKS until operational requirements justify Kubernetes.

The control-plane VM hosts Docker Compose applications.

---

## 8. Control-plane application architecture

The target Docker Compose runtime is:

```text
Control-plane VM
│
├── ag-flow/installation
│   │
│   ├── devpod-ui / Portal
│   ├── Docflow
│   ├── RAG
│   ├── PostgreSQL / pgvector
│   ├── Homepage
│   └── Caddy
│
├── Harpocrate
│   ├── backend
│   ├── frontend
│   └── PostgreSQL
│
└── MCP Manager
    ├── backend
    ├── frontend
    ├── MCP catalog
    ├── Skills catalog
    └── PostgreSQL / pgvector
```

Application deployment is intentionally independent of Bicep.

Bicep provides the host and Azure dependencies.

Docker Compose provides the application runtime.

---

## 9. ag-flow application responsibilities

### Portal / devpod-ui

Portal has two primary responsibilities:

1. manage agent/workspace sessions;
2. act as the runtime MCP gateway.

Portal is not the document database and is not the search engine.

Conceptually:

```text
Claude / Codex / Agent
         │
         ▼
       Portal
   MCP runtime gateway
      /          \
     ▼            ▼
 Docflow         RAG
```

---

### Docflow

Docflow is the structured knowledge and documentation layer.

Responsibilities include:

* hierarchical Markdown documents;
* document types;
* typed properties;
* statuses;
* relations;
* views;
* MCP read/write access.

Docflow should not become a semantic search engine.

---

### RAG

RAG owns search and retrieval.

Expected capabilities include:

* lexical search;
* semantic search;
* embeddings;
* PostgreSQL / pgvector;
* source ingestion;
* structured chunking;
* MCP retrieval interface.

Docflow stores structured knowledge.

RAG indexes and retrieves knowledge.

---

## 10. MCP Manager

MCP Manager provides capability discovery and cataloging.

Its responsibilities are distinct from the Portal MCP gateway.

```text
MCP Manager
     │
     ├── MCP server discovery
     ├── MCP metadata enrichment
     ├── Skills discovery
     ├── skills.sh ingestion
     ├── GitHub SKILL.md scanning
     ├── LLM summaries
     └── installation recipes
```

Conceptually:

```text
                         MCP Manager
                      Capability catalog
                       /             \
                      /               \
                 MCP servers         Skills
                     │                 │
                     ▼                 ▼
            Portal MCP Gateway   Workspace profiles
                     │                 │
                     └────────┬────────┘
                              ▼
                       Agent workspace
```

MCP Manager is therefore a discovery and enrichment layer.

Portal remains the runtime gateway.

---

## 11. Skills architecture

Skills should initially remain native agent/workspace capabilities.

Target flow:

```text
skills.sh
    │
    ▼
MCP Manager ingestion
    │
    ▼
GitHub repository scanning
    │
    ▼
SKILL.md parsing
    │
    ▼
LLM enrichment
    │
    ▼
Curated capability catalog
    │
    ▼
Workspace profile / recipe
    │
    ▼
Claude Code / Codex workspace
```

Skills should not automatically be converted into MCP resources unless there is a concrete runtime requirement.

---

## 12. Microsoft Foundry

Microsoft Foundry is intended to centralize model access.

Target model categories include:

```text
Microsoft Foundry
│
├── Claude
├── Codex / Azure OpenAI compatible models
└── Embeddings
```

Foundry may be consumed by:

* Claude Code workspaces;
* Codex workspaces;
* MCP Manager summarization;
* MCP Manager embeddings;
* RAG embeddings;
* future Knowledge Compiler agents.

Exact models, SKUs, quotas, API versions, and availability must be verified at implementation time rather than hardcoded into architecture documentation.

Where supported, Managed Identity / Entra authentication should be preferred over static API keys.

---

## 13. Secrets architecture

Harpocrate is the planned secret-management application for non-Azure or application-level credentials.

Potential examples include:

* external API credentials;
* Git credentials;
* MCP credentials;
* third-party service secrets;
* workspace secrets.

However, Azure-native identity should be preferred wherever possible.

Priority:

```text
Managed Identity / Entra
        ↓
preferred

Harpocrate-managed secret
        ↓
when an actual secret is required
```

Secrets must never be stored in:

* Bicep;
* `.bicepparam`;
* Git;
* documentation;
* cloud-init;
* deployment outputs.

---

## 14. Identity and RBAC model

The platform follows least-privilege principles and keeps control-plane and
workspace-provisioning responsibilities separate.

See:

- [ADR-0004 — Managed Identities and workspace provisioning RBAC](adr/0004-managed-identities-rbac.md)

Two durable User Assigned Managed Identities are defined:

```text
rg-agflow-platform-{environment}
│
├── id-agflow-control-plane-{environment}
│
└── id-agflow-workspace-provisioner-{environment}
```

For LAB:

```text
id-agflow-control-plane-lab
id-agflow-workspace-provisioner-lab
```

Both identities are long-lived Bicep-owned platform resources.

### Control-plane identity

```text
id-agflow-control-plane-{environment}
```

represents the future control-plane workload.

Milestone 3 intentionally grants it:

```text
RBAC: none
```

Permissions are introduced only by later milestones when a concrete consumer
exists.

Examples may eventually include:

- Azure Storage;
- Microsoft Foundry;
- other Azure-native services.

No permission is granted speculatively.

### Workspace provisioner identity

```text
id-agflow-workspace-provisioner-{environment}
```

is used by devpod-ui/OpenTofu to provision and destroy ephemeral workspace
resources.

Its authorization model is:

```text
id-agflow-workspace-provisioner-lab
│
├── Virtual Machine Contributor
│      │
│      └── scope:
│          rg-agflow-workspaces-lab
│
└── Agflow Workspace Subnet Joiner
       │
       └── scope:
           snet-workspaces
```

### Workspace Resource Group permissions

The workspace provisioner receives:

```text
Virtual Machine Contributor
```

on:

```text
rg-agflow-workspaces-{environment}
```

This built-in role is broader than the strict minimum VM/NIC/disk operation
set, but is substantially narrower than `Contributor`.

Its scope is restricted to the Resource Group dedicated to ephemeral workspace
resources.

`Contributor` is deliberately not used.

### Workspace subnet permission

The workspace provisioner must be able to attach workspace NICs to:

```text
snet-workspaces
```

However, `snet-workspaces` is a durable Bicep-owned shared resource.

Therefore OpenTofu must not receive:

```text
Microsoft.Network/virtualNetworks/subnets/write
Microsoft.Network/virtualNetworks/subnets/delete
```

`Network Contributor` is deliberately not used.

A custom role is defined:

```text
Agflow Workspace Subnet Joiner
```

with exactly:

```text
Microsoft.Network/virtualNetworks/subnets/read
Microsoft.Network/virtualNetworks/subnets/join/action
```

Its assignable scope covers:

```text
rg-agflow-platform-{environment}
```

but the actual role assignment is scoped only to:

```text
snet-workspaces
```

Conceptually:

```text
Workspace Provisioner
        │
        │ read + join only
        ▼
  snet-workspaces
        │
        ├── allowed: read
        ├── allowed: join
        │
        ├── not granted by this role: write
        └── not granted by this role: delete
```

This enforces the Bicep/OpenTofu ownership boundary through Azure RBAC rather
than convention alone.

### Explicitly prohibited permissions

The workspace provisioner must not receive:

- Owner;
- User Access Administrator;
- subscription-wide Contributor;
- Contributor on `rg-agflow-platform-{environment}`;
- Contributor on `rg-agflow-workspaces-{environment}`;
- Network Contributor on the VNet;
- Network Contributor on `snet-workspaces`;
- permissions over `snet-control`;
- permissions over `snet-private-endpoints`;
- `Microsoft.Authorization/roleDefinitions/write`;
- `Microsoft.Authorization/roleAssignments/write`.

Neither runtime identity owns or modifies Azure authorization policy.

### Managed Identity Operator

`Managed Identity Operator` is not granted during Milestone 3.

It may be introduced later only if OpenTofu must attach an Azure Managed
Identity to workspace VMs.

That permission belongs to the milestone introducing that concrete
requirement.

---

## 15. Future control-plane identity selection

The future control-plane VM is expected to have both User Assigned Managed
Identities attached:

```text
Control-plane VM
│
├── id-agflow-control-plane-lab
│
└── id-agflow-workspace-provisioner-lab
```

Applications running on the VM must explicitly select the identity appropriate
for their responsibility.

Normal control-plane workloads use:

```text
id-agflow-control-plane-lab
```

DevPod/OpenTofu Azure provisioning uses:

```text
id-agflow-workspace-provisioner-lab
```

The OpenTofu Azure provider must therefore be configured using the explicit:

```text
workspaceProvisionerIdentityClientId
```

Implicit Managed Identity selection must not be relied upon when several UAMIs
are attached to the same compute resource.

---

## 16. Bicep ↔ OpenTofu contract

Bicep owns shared Azure resources.

OpenTofu consumes those resources through explicit identifiers and narrowly
scoped permissions.

Conceptually:

```text
                         Bicep
                           │
          ┌────────────────┼─────────────────┐
          │                │                 │
          ▼                ▼                 ▼
 Workspace RG      Workspace subnet       UAMI
          │                │                 │
          └────────────────┼─────────────────┘
                           │
                    platform contract
                           │
                           ▼
                      devpod-ui
                           │
                           ▼
                       OpenTofu
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
          VM              NIC             Disk
                            │
                            ▼
                    snet-workspaces
```

The platform contract is expected to contain values such as:

```text
subscription ID
Azure location
workspace resource group
workspace subnet ID
workspace provisioner identity ID
workspace provisioner identity client ID
```

Bicep exposes values required by future platform consumers.

OpenTofu consumes existing shared resources but does not create, update, or
delete them.

The ownership rule remains:

```text
Bicep
→ shared platform infrastructure

OpenTofu
→ ephemeral workspace infrastructure
```

---

## 17. Bicep module architecture

The root Bicep deployment remains:

```text
targetScope = subscription
```

The intended module structure evolves incrementally.

Conceptually:

```text
infra/main.bicep
│
├── modules/resource-groups.bicep
│
├── modules/networking.bicep
│
├── modules/identities.bicep
│
└── RBAC modules
    ├── workspace resource-group assignment
    └── workspace subnet custom-role assignment
```

Cross-scope Azure resources are separated when required by Bicep or Azure
deployment-scope semantics.

The architecture favors:

- deterministic names;
- deterministic role-assignment IDs;
- single-resource ownership;
- explicit dependencies;
- environment-specific configuration through `.bicepparam`.

Implementation convenience must not weaken the Bicep/OpenTofu ownership
boundary.

---

## 18. Environment model

Supported environment values are:

```text
lab
dev
prod
```

Environment-specific platform resources include the environment in their
names.

Examples:

```text
rg-agflow-platform-lab
rg-agflow-workspaces-lab

vnet-agflow-lab

nsg-agflow-control-lab
nsg-agflow-workspaces-lab

id-agflow-control-plane-lab
id-agflow-workspace-provisioner-lab
```

Environment-specific configuration is stored in:

```text
infra/environments/{environment}/main.bicepparam
```

Initial network allocation:

```text
LAB    10.20.0.0/16

DEV    10.21.0.0/16    provisional

PROD   10.22.0.0/16    provisional
```

Network ranges must remain non-overlapping before VNet peering or other
cross-environment routing is introduced.

---

## 19. Knowledge architecture

The long-term platform architecture goes beyond a conventional document RAG.

The target is an enterprise Knowledge Compiler / Knowledge Mesh model.

Conceptually:

```text
Enterprise sources
│
├── Confluence
├── SharePoint
├── GitHub / Azure DevOps Git
├── Azure DevOps Work Items
├── Salesforce
├── Snowflake / dbt
├── Power BI
└── other enterprise sources
        │
        ▼
Domain Knowledge Compiler Workspaces
        │
        ├── curated Markdown / Wiki
        ├── ontology
        ├── provenance
        ├── validation
        └── human approval
        │
        ▼
Enterprise Knowledge Product
        │
        ├── structured source
        ├── vector projection
        └── graph projection
```

Potential target projections include:

```text
PostgreSQL
→ transactional / structured knowledge state

Qdrant
→ semantic retrieval projection

Neo4j
→ knowledge graph projection
```

These components are future architecture and are not part of the initial Azure
infrastructure milestones.

---

## 20. Deployment sequence

The platform is implemented incrementally.

```text
Milestone 1
Resource Groups
        │
        ▼
Milestone 2
Networking
        │
        ▼
Milestone 3
Managed Identities + RBAC
        │
        ▼
Milestone 4
Shared Storage
        │
        ▼
Milestone 5
Control-plane VM
        │
        ▼
Milestone 6
Microsoft Foundry
        │
        ▼
Milestone 7
Private connectivity
        │
        ▼
Milestone 8
DevPod / OpenTofu integration
        │
        ▼
Application deployment
```

Milestone ordering may evolve when a concrete dependency justifies it.

Infrastructure ownership boundaries must remain stable.

---

## 21. Current architectural boundaries

### Bicep owns

```text
Resource Groups
VNet
Subnets
NSGs
Managed Identities
Custom Azure roles
RBAC assignments
Shared storage
Control-plane VM
Microsoft Foundry foundation
Private networking
Shared outbound infrastructure
```

### OpenTofu owns

```text
Workspace VM
Workspace NIC
Workspace disk
Workspace creation
Workspace destruction
Workspace recreation
```

### Docker Compose owns

```text
Portal / devpod-ui
Docflow
RAG
PostgreSQL
Harpocrate
MCP Manager
Homepage
Caddy
application services
```

### Key rule

```text
one resource
    │
    ▼
one owner
```

No Azure resource may be managed simultaneously by Bicep and OpenTofu.

---

## 22. Architecture Decision Records

Current accepted decisions:

- [ADR-0001 — Infrastructure ownership boundaries](adr/0001-iac-ownership-boundaries.md)
- [ADR-0002 — Environment-aware Azure resource naming](adr/0002-environment-resource-naming.md)
- [ADR-0003 — Shared network foundation and outbound connectivity](adr/0003-shared-network-foundation.md)
- [ADR-0004 — Managed Identities and workspace provisioning RBAC](adr/0004-managed-identities-rbac.md)

Future significant decisions should be captured as new ADRs when they affect:

- outbound networking;
- storage architecture;
- control-plane compute;
- Microsoft Foundry integration;
- private connectivity;
- application secrets;
- DevPod/OpenTofu integration;
- persistent application data;
- major platform dependencies.

Architecture documentation describes the resulting architecture.

ADR files explain why significant architectural choices were made.

Git history records how the implementation changed over time.