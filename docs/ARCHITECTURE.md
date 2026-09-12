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
rg-agflow-platform
```

contains durable platform infrastructure such as:

* VNet;
* control-plane VM;
* Foundry;
* shared storage;
* platform Managed Identities;
* future Private Endpoints and DNS resources.

```text
rg-agflow-workspaces
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
vnet-agflow
10.20.0.0/16
│
├── snet-control
│   10.20.1.0/24
│
├── snet-workspaces
│   10.20.2.0/24
│
└── snet-private-endpoints
    10.20.3.0/24
```

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

The platform should use least privilege.

At minimum, separate identities are expected for:

```text
Control-plane identity

Workspace provisioning identity
```

The DevPod/OpenTofu provisioning identity should receive only the permissions required to create workspace resources.

Expected boundary:

```text
Workspace provisioner
      │
      ├── Contributor
      │     on rg-agflow-workspaces
      │
      └── limited network permission
            on snet-workspaces
```

It should not receive broad Contributor rights over:

* `rg-agflow-platform`;
* Foundry;
* control-plane VM;
* platform secrets;
* the entire subscription.

Exact RBAC roles will be designed and recorded when that milestone is implemented.

---

## 15. Bicep ↔ OpenTofu contract

Bicep owns shared Azure resources.

OpenTo
