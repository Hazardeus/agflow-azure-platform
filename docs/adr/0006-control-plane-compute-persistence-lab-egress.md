# ADR-0006 — Control-plane Compute, Persistence and LAB Egress

## Status

Accepted

## Context

Milestone 5 introduces the first concrete compute workload on the ag-flow
Azure platform: the control-plane VM that will eventually host the Docker
Compose application stack (ADR-0001, `ARCHITECTURE.md` §7-8).

Several prior decisions constrain this milestone:

- ADR-0001 assigns long-lived Azure infrastructure to Bicep, ephemeral
  workspace infrastructure to devpod-ui/OpenTofu, and application containers
  running on the control-plane VM to Docker Compose.
- ADR-0002 defines the deterministic, environment-aware naming convention
  this milestone's resources must follow.
- ADR-0003 created `snet-control` with `defaultOutboundAccess = false` and
  explicitly deferred the outbound-connectivity mechanism to "the milestone
  that introduces the first workload requiring public Internet access,"
  naming an explicit Standard Public IP on a single control-plane VM and a
  shared NAT Gateway as the two candidate mechanisms to choose between at
  that time. Milestone 5 is that milestone.
- ADR-0004 created `id-agflow-control-plane-{environment}` and
  `id-agflow-workspace-provisioner-{environment}` and already specified that
  the future control-plane VM would carry both UAMIs simultaneously, with
  devpod-ui/OpenTofu required to explicitly select the workspace-provisioner
  identity by client ID.
- ADR-0005 created one foundational Storage Account with no workload RBAC,
  to be granted only when a concrete consumer and access pattern exist.

Milestone 5 must decide compute lifecycle (VM size, Spot behavior), the
outbound-connectivity mechanism ADR-0003 deferred, administrative access,
persistence for future stateful application data, the OS/security baseline,
and the boundary between Bicep-owned host bootstrap and Docker
Compose-owned application deployment. These decisions are difficult or
costly to reverse once workloads depend on them, and several change
networking/security posture and the Bicep/OpenTofu/Docker Compose boundary
— both explicit ADR triggers under `AGENTS.md` and `DEVELOPMENT.md`.

This ADR does not modify or reinterpret ADR-0001 through ADR-0005; it
resolves the specific items those ADRs left open for the milestone that
introduces the control-plane VM.

## Decision

### 1. Control-plane ownership

The control-plane VM and its durable Azure infrastructure are Bicep-owned,
consistent with ADR-0001 and `ARCHITECTURE.md` §3.

Bicep owns:

- the VM;
- its NIC;
- the LAB Public IP used for explicit egress;
- OS disk configuration;
- the persistent managed data disk;
- attachment of both existing UAMIs;
- host security configuration;
- minimal host bootstrap;
- the Docker Engine / Compose v2 runtime prerequisite.

Docker Compose / the application layer owns:

- compose definitions;
- application containers;
- application networks;
- application configuration;
- application-level volume layout;
- application deployment and upgrades;
- PostgreSQL / pgvector;
- Qdrant;
- Neo4j;
- Harpocrate;
- RAG;
- MCP Manager;
- application secrets.

OpenTofu's ownership is unchanged by this ADR: ephemeral workspace VMs,
NICs, and disks only, per ADR-0001 and ADR-0004.

### 2. LAB VM compute

LAB uses:

- Ubuntu 24.04 LTS, Gen2;
- `Standard_D4as_v5`;
- Spot priority;
- eviction policy `Deallocate`.

Spot is a LAB cost optimization. It is not adopted here as the platform-wide
production availability standard.

**"Stable control plane" is clarified explicitly**: it means durable
identity, networking, and persistent disk state. It does not imply
guaranteed 24/7 compute availability. This clarification is necessary
because `ARCHITECTURE.md` describes the control plane as "stable," and that
language must not be misread as a compute-uptime guarantee once Spot is in
use.

Accepted LAB limitations:

- Azure may evict the Spot VM at any time;
- compute availability is not guaranteed;
- the VM may remain deallocated after eviction;
- Milestone 5 introduces no automatic restart/reallocation mechanism;
- operator intervention may be required to resume the VM;
- DEV/PROD compute availability strategy is deferred and must not
  automatically inherit LAB's Spot choice.

VM size, priority, and Spot configuration (`vmSize`, `vmPriority`,
`evictionPolicy`, `maxPrice`) are environment-specific Bicep parameters, not
hardcoded platform assumptions.

### 3. Networking and LAB egress

The VM uses one Bicep-owned NIC attached to `snet-control`. In LAB, the NIC
receives a Standard Public IP.

The Public IP exists solely to provide explicit outbound connectivity,
because:

- `snet-control` has `defaultOutboundAccess = false` (ADR-0003);
- the control-plane host requires outbound access for OS updates, package
  retrieval, Docker/container registry access, Git, and future application
  traffic;
- Milestone 5 LAB contains exactly one control-plane VM in `snet-control`;
- a NAT Gateway introduces a fixed-cost shared egress component that is not
  justified for a single-VM LAB environment.

**The Public IP is not an ingress or administration design.** No public SSH
rule, and no application-port ingress rule, is permitted on its account.

The existing control NSG, `nsg-agflow-control-{environment}`
(`nsg-agflow-control-lab` in LAB), receives one explicit custom rule:

```text
name: Deny-Internet-Inbound
priority: 100
direction: Inbound
access: Deny
protocol: '*'
source: Internet
sourcePort: '*'
destination: '*'
destinationPort: '*'
```

This rule exists so the platform does not rely solely on Azure's built-in
default `DenyAllInbound` rule (priority 65500) to keep the newly-added
Public IP from becoming an inbound path — consistent with the "no implicit
Azure defaults" principle already established for outbound connectivity and
Storage Account network ACLs in ADR-0003 and ADR-0005. Being stateful, this
rule does not affect return traffic for VM-initiated outbound connections,
and it does not affect Azure's platform management channels (WireServer /
IMDS), which are exempt from NSG evaluation — Run Command, Serial Console,
boot diagnostics, and platform patching are unaffected.

The existing networking module remains the sole owner of
`nsg-agflow-control-{environment}`. The Milestone 5 compute module must not
separately own or duplicate NSG child rules; the rule above is added to the
existing NSG resource in the existing networking module.

This decision resolves the outbound-connectivity question ADR-0003
deliberately deferred; it does not alter any other decision in ADR-0003.

### 4. NAT Gateway — alternative considered, not rejected platform-wide

A shared NAT Gateway on `snet-control` was evaluated as the primary
alternative.

Advantages:

- structurally outbound-only — no public IP is directly associated with the
  VM's NIC, removing that class of exposure entirely rather than mitigating
  it with an NSG rule;
- a more suitable shared-egress architecture once more than one resource in
  `snet-control` requires outbound access.

Rejected for LAB Milestone 5 because:

- `snet-control` currently hosts exactly one workload;
- NAT Gateway is a fixed-cost resource (hourly charge plus data processing)
  not justified for a single VM;
- it adds a deployable component with no current second consumer.

This rejection is scoped to LAB Milestone 5 only. NAT Gateway remains a
valid candidate for DEV, PROD, or a future `snet-control` topology with
multiple workloads, and must be re-evaluated at that time rather than
assumed away.

### 5. Administrative access

Initial LAB administration and recovery use Azure control-plane mechanisms
that do not depend on a network path through the NIC/NSG:

- Azure Run Command;
- Serial Console, where applicable.

SSH key authentication may be configured at the OS level for future use, but:

- password authentication is disabled;
- no public inbound SSH rule exists;
- the Public IP is not, and must not become, an SSH endpoint.

Azure Bastion is deferred — it would require a dedicated `AzureBastionSubnet`
not currently justified for LAB, and Run Command/Serial Console already
provide a working recovery path without one.

### 6. Managed identities

Both existing UAMIs are attached to the control-plane VM:

- `id-agflow-control-plane-{environment}`;
- `id-agflow-workspace-provisioner-{environment}`.

This was already anticipated by ADR-0004. Normal control-plane workloads use
the control-plane identity. devpod-ui/OpenTofu must explicitly select the
workspace-provisioner identity by client ID (`workspaceProvisionerIdentityClientId`)
— Azure does not infer which attached identity a workload should use when
more than one UAMI is present, and implicit/default identity selection must
not be relied upon.

No new workload RBAC is introduced in Milestone 5. In particular, the M4
Storage Account (ADR-0005) receives no role assignment merely because it
exists — Milestone 5 has no concrete storage consumer, and Azure-managed
boot diagnostics (§10) removes the one candidate reason a storage RBAC grant
might otherwise have been considered.

### 7. OS security baseline

- Ubuntu 24.04 LTS, Gen2;
- Trusted Launch, Secure Boot, and vTPM enabled (Gen2 image on a
  Trusted-Launch-capable size);
- password authentication disabled; SSH-key-capable configuration only;
- guest patching set to `AutomaticByPlatform`;
- Azure-managed boot diagnostics, with no dependency on the M4 Storage
  Account.

Exact image publisher/offer/SKU identifiers and exact Bicep API versions are
implementation details and must be verified against current stable
Azure/Bicep schemas at implementation time, not assumed from this ADR.

### 8. Persistent data disk

Future stateful application data must not depend on the OS disk. A separate,
Bicep-owned managed data disk is created.

Approved characteristics:

- durable independently of the VM's compute lifecycle;
- attached to the VM with delete behavior `Detach`, so deleting or
  recreating the VM resource never deletes the disk;
- survives Spot deallocation (Deallocate preserves attached disks) and can
  be reattached after VM recreation;
- host caching baseline of `None`, parameterized so it can be tuned once a
  concrete workload's I/O pattern is known;
- disk SKU and size are environment-specific parameters; the exact LAB
  starting values are an implementation choice within this approved model,
  not a fixed platform standard.

Stable host mount point: `/srv/agflow`.

The disk bootstrap must be idempotent and safe for both cases:

- a genuinely new, empty disk is formatted;
- an existing disk already containing data — whether reattached after a
  Spot restart or after a VM recreation — is never reformatted.

This must be enforced structurally, not only by the OS-level bootstrap
script: the data disk must be modeled as an independent
`Microsoft.Compute/disks` resource, referenced by the VM via
`createOption: Attach` at a fixed, explicitly-set LUN — not created inline
as a VM-managed disk with `createOption: Empty` — so that recreating the VM
resource reuses the same disk rather than provisioning a new one.

Application-level directory and volume organization beneath `/srv/agflow`
belongs to the later application layer, not to this ADR.

### 9. Host bootstrap

Milestone 5 performs a minimal infrastructure-readiness bootstrap only. It
may:

- prepare and mount the persistent data disk;
- install Docker Engine;
- provide the Docker Compose v2 capability.

This is host/runtime preparation, not application deployment. No
application container is deployed by Milestone 5.

Ubuntu 24.04 distribution-signed Docker packages are preferred where
technically adequate, to keep the bootstrap deterministic and reviewable
from Bicep-tracked source rather than trusting an external repository/key
fetched at boot time. If an upstream Docker apt repository proves genuinely
necessary, implementation must justify that choice explicitly and use a
deterministic, reviewable repository/key setup — an unreviewed
curl-pipe-shell installer is not permitted.

No secrets may appear in Bicep source, `.bicepparam` files, `customData` /
cloud-init, Git history, or documentation. Where bootstrap content is
substantial, it should be kept in a dedicated source/template file rather
than embedded as an opaque inline script in Bicep.

### 10. Diagnostics and monitoring

Azure-managed boot diagnostics are used. Log Analytics Workspace, Azure
Monitor Agent, and workload-specific monitoring agents are not introduced in
Milestone 5; they require a later, concrete requirement to justify them.

### 11. Explicitly deferred

The following remain explicitly out of scope for Milestone 5 and this ADR:

- Microsoft Foundry;
- Private Endpoints;
- Private DNS;
- Azure Bastion;
- NAT Gateway for LAB (remains a candidate for other environments, §4);
- DEV/PROD compute availability design;
- automatic Spot recovery/reallocation;
- Docker Compose application deployment;
- application containers;
- application secrets;
- application-specific persistent-volume layout under `/srv/agflow`;
- PostgreSQL / pgvector;
- Qdrant;
- Neo4j;
- Harpocrate;
- RAG;
- MCP Manager;
- workload storage RBAC on the M4 Storage Account;
- DevPod/OpenTofu workspace resources.

## Consequences

### Positive

- The outbound-connectivity question ADR-0003 deliberately deferred is now
  resolved with an explicit, reviewed decision rather than an implicit
  default, and the decision is scoped to LAB rather than presumed permanent.
- The Public IP's presence is paired with an explicit deny-inbound rule, so
  the platform does not depend on Azure's default NSG behavior to stay
  closed to the Internet.
- The Bicep/Docker Compose boundary from ADR-0001 is preserved with an
  explicit statement that installing the container runtime does not
  authorize deploying application containers, avoiding ownership drift as
  later milestones add real workloads.
- Persistence is decoupled from VM compute lifecycle from the outset, before
  any real database exists, avoiding a painful retrofit later.
- Both UAMIs are attached exactly as ADR-0004 anticipated, with no new RBAC
  and no change to least-privilege posture.

### Negative

- A Standard Public IP is directly associated with the control-plane NIC;
  its safety depends on the explicit NSG rule continuing to exist and not
  being weakened by a later, unrelated change — a structural egress-only
  design (NAT Gateway) would not have this dependency, at higher fixed cost.
- Host-level Docker Engine installation via Bicep-owned bootstrap adds an
  external package dependency (Ubuntu's Docker packages) to infrastructure
  provisioning, which is not validated by `az bicep lint`/`build`.
- LAB has no automatic recovery from Spot eviction; an operator must notice
  and restart the VM.

## Alternatives considered

### Regular (pay-as-you-go) VM instead of Spot

Rejected for LAB. Spot is materially cheaper and acceptable given the
accepted-limitations model in §2; DEV/PROD may choose differently, and that
choice is deliberately left open rather than decided here.

### NAT Gateway instead of a Public IP on the NIC

Considered and rejected for LAB only, per §4 — not cost-justified for a
single VM. Remains available for future environments or once `snet-control`
hosts multiple workloads.

### Relying on the default NSG deny instead of an explicit Internet-deny rule

Rejected. This would have made the platform's Internet-inbound safety an
implicit consequence of Azure's default rule ordering rather than a
declared, reviewable decision — inconsistent with the "no implicit Azure
defaults" principle already used for outbound connectivity (ADR-0003) and
Storage Account network ACLs (ADR-0005).

### Public inbound SSH rule

Rejected. There is no requirement for direct Internet SSH access; Run
Command and Serial Console provide sufficient LAB administration and
recovery without exposing port 22 to the Internet.

### Azure Bastion in Milestone 5

Rejected for now. It requires a new `AzureBastionSubnet` and recurring cost
not currently justified when Run Command and Serial Console already meet
the LAB administration need. May be reconsidered when interactive SSH
becomes a concrete requirement.

### OS disk only, no separate data disk

Rejected. Tying future application state to the OS disk would couple
database/application persistence to OS-level lifecycle events (image
changes, VM rebuilds), which is unnecessary and harder to reverse once real
data exists. A decoupled managed disk avoids this at negligible extra cost.

### Azure Files for application persistence

Rejected as premature. No concrete application access pattern exists yet;
deciding a shared-filesystem model now would be speculative, echoing the
same reasoning ADR-0005 used to defer data-plane structure until a real
consumer exists.

### Deferring Docker runtime installation entirely

Considered. Rejected in favor of installing Docker Engine/Compose v2 in
Milestone 5's bootstrap, because the control-plane host would otherwise
require a separate, undefined mechanism to install it later, and the
runtime itself is host preparation rather than an application deployment
concern. The ownership boundary in §1 and §9 is the safeguard against this
decision eroding into Bicep owning application deployment.

### Application deployment through Bicep

Rejected outright and permanently out of scope for this ADR. Docker Compose
remains the sole owner of application containers, configuration, and
secrets, per ADR-0001.

## References

- ADR-0001 — Infrastructure ownership boundaries
- ADR-0003 — Shared network foundation and outbound connectivity
- ADR-0004 — Managed Identities and workspace provisioning RBAC
- ADR-0005 — Shared Storage Foundation
