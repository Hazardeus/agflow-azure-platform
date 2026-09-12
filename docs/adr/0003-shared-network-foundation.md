# ADR-0003 — Shared network foundation and outbound connectivity

## Status

Accepted

## Context

The ag-flow Azure platform requires a shared network foundation for two different workload categories:

- long-lived control-plane workloads;
- ephemeral DevPod/OpenTofu workspaces.

Future Azure services will also use Private Endpoints.

Bicep owns shared Azure networking while devpod-ui/OpenTofu owns ephemeral workspace compute.

The network architecture must:

- preserve this infrastructure ownership boundary;
- support multiple environments;
- avoid overlapping network ranges when environments are interconnected;
- avoid implicit Azure outbound connectivity;
- provide future private connectivity;
- allow security policy to evolve when workload traffic flows are known;
- remain cost-efficient for the lab environment.

---

## Decision

### Virtual network

Each environment receives an environment-specific VNet.

Naming convention:

`vnet-agflow-{environment}`

For the lab environment:

`vnet-agflow-lab`

LAB address space:

`10.20.0.0/16`

Address spaces are environment-specific configuration and are supplied through environment-specific `.bicepparam` files.

Future environments must use non-overlapping address spaces before any VNet peering, hub-and-spoke connectivity, or other cross-environment routing is introduced.

Expected initial allocation:

- LAB: `10.20.0.0/16`
- DEV: `10.21.0.0/16`
- PROD: `10.22.0.0/16`

DEV and PROD ranges remain provisional until those environments are created.

---

## Subnets

The LAB VNet contains:

- `snet-control` — `10.20.1.0/24`
- `snet-workspaces` — `10.20.2.0/24`
- `snet-private-endpoints` — `10.20.3.0/24`

Subnet names do not contain the environment because the parent VNet already provides the environment boundary.

The subnet prefixes must be provided through environment-specific Bicep parameters rather than hardcoded into the networking module.

---

## Infrastructure ownership

Bicep owns:

- VNet;
- shared subnets;
- subnet configuration;
- Network Security Groups;
- future shared outbound networking resources;
- future Private Endpoint networking resources.

devpod-ui/OpenTofu consumes the existing `snet-workspaces` subnet.

OpenTofu must not create or manage:

- the shared VNet;
- shared subnets;
- shared NSGs;
- shared outbound networking;
- shared Private Endpoint infrastructure.

Workspace VMs, NICs, and workspace-specific disks remain owned by OpenTofu.

This reinforces the infrastructure ownership boundary established in ADR-0001.

---

## Private subnets

All subnets explicitly use:

`defaultOutboundAccess = false`

The platform must not rely on Azure implicit/default outbound connectivity.

This behavior must be defined explicitly in Bicep rather than relying on Azure defaults.

The following subnets are therefore private by design:

- `snet-control`;
- `snet-workspaces`;
- `snet-private-endpoints`.

Milestone 2 creates the private network foundation only.

It does not yet create an outbound connectivity mechanism.

---

## Outbound connectivity

The platform must not rely on Azure implicit/default outbound access.

Milestone 2 does not provision an outbound connectivity service.

The exact outbound mechanism will be selected when the first workload requiring Internet access is introduced.

For the lab environment, cost efficiency is an explicit design criterion.

Candidate outbound strategies include:

### Explicit Standard Public IP

An explicit Standard Public IP may be associated with a small number of lab workloads when this provides the simplest and most cost-efficient outbound path.

Inbound Internet access must remain blocked by NSG policy.

This option may be appropriate for:

- a single control-plane VM;
- a very small number of temporary lab workloads.

### Shared NAT Gateway

A shared NAT Gateway may be introduced when requirements justify its fixed cost.

Typical reasons include:

- multiple workloads requiring outbound connectivity;
- centralized and deterministic egress IP;
- IP allowlisting;
- simplified workspace egress management;
- avoidance of one Public IP per workload;
- operational or security requirements.

A NAT Gateway is not mandatory for the platform architecture.

### Decision timing

The outbound mechanism must be decided before deploying workloads that require access to public endpoints.

Likely outbound consumers include:

- Docker image registries;
- Linux package repositories;
- GitHub;
- Cloudflare Tunnel;
- Microsoft Foundry public endpoints;
- DevPod workspace development tools.

No workload may rely on Azure implicit/default outbound connectivity.

---

## Network Security Groups

Milestone 2 creates:

- `nsg-agflow-control-{environment}`;
- `nsg-agflow-workspaces-{environment}`.

For lab:

- `nsg-agflow-control-lab`;
- `nsg-agflow-workspaces-lab`.

They are associated respectively with:

- `snet-control`;
- `snet-workspaces`.

No custom security rules are introduced during Milestone 2 because actual workload traffic flows have not yet been finalized.

Azure default NSG rules therefore remain initially effective.

This establishes security control points but does not yet enforce strict east-west isolation between control and workspace workloads.

Explicit workload rules will be introduced when the corresponding workloads and required ports are defined.

Examples of later traffic decisions include:

- control-plane to workspace SSH;
- mTLS traffic;
- application-specific control-plane communication;
- outbound restrictions;
- service-to-service access.

No ports should be invented during Milestone 2.

---

## Private Endpoint subnet

`snet-private-endpoints` is reserved for future Azure Private Endpoints.

The subnet uses:

`privateEndpointNetworkPolicies = 'Enabled'`

This prepares the subnet for future NSG and route-table enforcement on Private Endpoint traffic.

Milestone 2 does not create:

- Private Endpoints;
- Private DNS zones;
- Private DNS links;
- an NSG for `snet-private-endpoints`;
- route tables;
- service delegations.

These resources will be introduced only when the corresponding Azure services require private connectivity.

---

## Bicep module design

Networking is implemented in:

`infra/modules/networking.bicep`

The networking module is resource-group scoped.

The repository root remains subscription scoped.

The networking module is deployed into:

`rg-agflow-platform-{environment}`

using the resource group name computed deterministically in `main.bicep`
(see ADR-0002), with an explicit `dependsOn` on the Resource Group module to
satisfy Bicep's cross-resource-group validation (BCP120).

Conceptually:

```text
infra/main.bicep
        │
        ├── resource-groups.bicep
        │       │
        │       └── rg-agflow-platform-{environment}
        │
        └── networking.bicep
                │
                ├── VNet
                ├── subnets
                └── NSGs
```

Address prefixes are passed explicitly from the environment `.bicepparam` file.

The networking module must not contain LAB-specific CIDR defaults.

---

## Bicep / OpenTofu contract

The networking module exposes internal outputs required by future platform modules.

Expected module outputs include:

- VNet name;
- VNet ID;
- control subnet ID;
- workspace subnet ID;
- private-endpoint subnet ID;
- control NSG ID;
- workspace NSG ID.

At subscription deployment level, only values with an identified external consumer should be exposed.

At minimum:

- `vnetId`;
- `workspaceSubnetId`.

`workspaceSubnetId` becomes part of the future DevPod/OpenTofu platform contract.

OpenTofu consumes the subnet reference but does not own the subnet.

---

## Tags

Network resources follow the project tagging model:

- `solution`;
- `environment`;
- `managedBy`;
- `purpose`.

Example:

```text
solution     = agflow
environment  = lab
managedBy    = bicep
purpose      = networking
```

Resource-specific `purpose` values may be used where useful, while avoiding an unnecessarily complex tagging model.

---

## Consequences

### Positive

- clear Bicep/OpenTofu network ownership;
- deterministic environment-aware VNet naming;
- explicit private-subnet behavior;
- no dependency on Azure implicit outbound access;
- outbound cost decisions can be made when workloads actually exist;
- no unnecessary NAT Gateway cost during the empty-network phase;
- no public IP required as part of Milestone 2;
- dedicated Private Endpoint capacity;
- network address spaces can vary by environment;
- future workload security rules can be introduced without restructuring the VNet.

### Negative

- workloads have no Internet connectivity until an explicit outbound mechanism is deployed;
- future workload milestones must include an outbound-connectivity decision;
- default NSG rules do not initially provide strict east-west isolation;
- the lab and production environments may ultimately use different outbound mechanisms;
- network configuration requires explicit environment CIDR management.

---

## Alternatives considered

### Azure implicit/default outbound access

Rejected.

The platform must not depend on Azure implicit outbound behavior.

Outbound access must be intentional and explicitly represented in the architecture.

### NAT Gateway during Milestone 2

Rejected for now.

No workload requiring outbound connectivity exists yet, and a NAT Gateway introduces fixed cost as soon as it is provisioned.

NAT Gateway remains a valid future option when scale, centralized egress, deterministic source IP, or operational requirements justify its cost.

### Public IP on every workload

Rejected as a general platform strategy.

It increases the number of public network resources and couples outbound networking to individual workloads.

However, an explicit Standard Public IP may still be considered for a very small number of lab workloads when it is materially cheaper and inbound Internet access remains blocked.

### Hardcoded network ranges in the networking module

Rejected.

Addressing is environment-specific configuration and belongs in `.bicepparam` files.

### Strict NSG rules during Milestone 2

Rejected.

Workload communication requirements are not sufficiently defined yet.

Security rules will be introduced alongside the workloads that require them.

---

## Deferred decisions

The following decisions are intentionally deferred:

- exact outbound mechanism for `snet-control`;
- exact outbound mechanism for `snet-workspaces`;
- whether NAT Gateway becomes justified later;
- whether individual lab workloads receive explicit Standard Public IPs;
- custom NSG rules;
- strict east-west isolation;
- NSG for `snet-private-endpoints`;
- route tables;
- Private Endpoints;
- Private DNS;
- DEV and PROD final CIDR allocations.

These decisions must be made before the corresponding infrastructure or workloads are deployed.
