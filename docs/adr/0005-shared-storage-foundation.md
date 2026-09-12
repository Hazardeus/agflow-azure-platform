# ADR-0005 — Shared Storage Foundation

## Status

Accepted

## Context

Milestone 4 introduces the durable Azure storage foundation for the ag-flow platform.

The architecture already establishes that long-lived shared Azure storage is owned by Bicep and belongs in:

```text
rg-agflow-platform-{environment}
```

However, no concrete storage consumer exists yet.

The following potential consumers belong to later milestones:

- the control-plane VM introduced in Milestone 5;
- Docker Compose applications deployed on that VM;
- backups or exports produced by control-plane workloads;
- devpod-ui/OpenTofu integration introduced in Milestone 8;
- a possible OpenTofu remote-state backend;
- future diagnostics or artifact storage.

Milestone 4 therefore follows the same incremental principle used in Milestone 3 for the control-plane managed identity: create the durable platform capability now, but do not grant permissions or create consumer-specific resources before a real consumer exists.

The storage design must also remain compatible with the future private networking milestone without introducing Private Endpoints or Private DNS prematurely.

## Decision

### One foundational Storage Account

Milestone 4 creates one general-purpose v2 Azure Storage Account in:

```text
rg-agflow-platform-{environment}
```

The account is a durable, Bicep-owned platform resource.

It is not intended to imply that all future platform storage must remain in a single account forever.

Additional Storage Accounts may be introduced later when a concrete workload requires a different:

- security boundary;
- network boundary;
- lifecycle;
- redundancy level;
- performance profile;
- blast radius;
- ownership model.

Until such a requirement exists, one foundational account keeps the platform small and avoids speculative infrastructure.

### Storage account kind

The account uses:

```text
kind: StorageV2
```

This provides the general-purpose storage foundation required for future Blob, Files, Queue, or Table use without committing Milestone 4 to one particular consumer.

The initial access tier is:

```text
Hot
```

No workload-specific tiering policy is introduced in Milestone 4.

### No data-plane resources yet

Milestone 4 creates only the Storage Account and its account-level security and data-protection configuration.

It does not create:

- Blob containers;
- Azure Files shares;
- queues;
- tables;
- OpenTofu state containers;
- backup containers;
- application-data shares.

Those resources must be introduced by the milestone that establishes the corresponding consumer and its concrete access pattern.

This avoids speculative data-plane structure and keeps ownership explicit.

### Redundancy

For LAB, the Storage Account uses:

```text
Standard_LRS
```

This is an environment-specific cost-conscious decision.

LRS is not the platform-wide production durability standard.

The storage module must expose the SKU as an environment parameter so that future environments may choose a different redundancy model.

Conceptually:

```text
LAB   -> Standard_LRS
DEV   -> TBD
PROD  -> TBD
         based on availability, durability and disaster-recovery requirements
```

Possible future choices such as ZRS, GRS, GZRS, RA-GRS, or RA-GZRS must be selected from explicit environment requirements rather than inherited from LAB.

### Naming

Azure Storage Account names must:

- be globally unique;
- contain only lowercase alphanumeric characters;
- contain between 3 and 24 characters.

The account name is deterministic and environment-aware.

The naming formula is:

```text
st{solutionName}{environmentName}{12-character deterministic subscription suffix}
```

With the current fixed solution name `agflow`, Bicep can derive this conceptually as:

```bicep
'st${solutionName}${environmentName}${take(uniqueString(subscription().id), 12)}'
```

Examples have a maximum length of 24 characters for the currently supported environment names:

```text
lab
dev
prod
```

The deterministic subscription-derived suffix provides global uniqueness without introducing random deployment-time naming.

### Tags

The Storage Account uses the common platform tagging convention:

```text
solution    = agflow
environment = {environment}
managedBy   = bicep
purpose     = storage
```

### Public network access during the foundational phase

Private connectivity is explicitly deferred to Milestone 7.

Until then:

```text
publicNetworkAccess = Enabled
```

This does not mean anonymous or unauthenticated data access is allowed.

The Storage Account must apply the following security baseline:

```text
HTTPS only
minimum TLS version = TLS 1.2
anonymous Blob public access = disabled
Shared Key authorization = disabled
```

In Bicep terms, the intended account-level posture is conceptually:

```bicep
properties: {
  publicNetworkAccess: 'Enabled'
  supportsHttpsTrafficOnly: true
  minimumTlsVersion: 'TLS1_2'
  allowBlobPublicAccess: false
  allowSharedKeyAccess: false
}
```

Public network reachability in Milestone 4 is therefore transport reachability only.

Data access must use authenticated Azure mechanisms.

### Shared Key authentication

Shared Key authorization is disabled:

```text
allowSharedKeyAccess = false
```

The preferred access model for platform consumers is Microsoft Entra ID with Managed Identity and Azure RBAC.

There is no current workload that requires account-key authentication, so enabling Shared Key pre-emptively would unnecessarily weaken the security baseline.

If a future concrete consumer cannot use Entra ID authentication, that milestone must explicitly justify any exception before Shared Key access is enabled.

### Network ACLs

Milestone 4 does not invent IP allowlists, service-endpoint rules, or subnet-based network ACLs for consumers that do not yet exist.

The account remains reachable through its authenticated public Azure endpoint until the private-connectivity design is implemented.

This follows the same incremental networking principle established by ADR-0003: network restrictions should be designed from actual traffic flows, not guessed before the consumers exist.

### Future Private Endpoint compatibility

Milestone 4 must not create:

- Private Endpoints;
- Private DNS zones;
- Private DNS links;
- storage-specific private connectivity.

These belong to Milestone 7.

The Storage Account created in Milestone 4 must remain compatible with a future design in which Blob, Files, or other required storage subresources are exposed through Private Endpoints using the already reserved:

```text
snet-private-endpoints
```

At that point, the target posture may become:

```text
publicNetworkAccess = Disabled
        +
Private Endpoint(s)
        +
Private DNS
```

The exact storage subresources requiring Private Endpoints must be determined from the consumers that actually exist at Milestone 7.

### Managed Identity and RBAC

Milestone 4 introduces no workload RBAC assignments.

In particular:

```text
id-agflow-control-plane-{environment}
```

does not receive Storage Blob Data Contributor, Storage Blob Data Reader, Storage File Data SMB Share Contributor, or any other storage data-plane role during Milestone 4.

ADR-0004 established that the control-plane identity is created without permissions until a concrete consumer requires them.

Milestone 4 preserves that least-privilege model.

The milestone that introduces a storage consumer is responsible for defining:

- which managed identity accesses the data;
- which storage service is consumed;
- which minimum built-in or custom role is required;
- the narrowest appropriate scope.

No generic storage Contributor role is granted pre-emptively.

### Data protection baseline

Blob versioning is enabled as a foundational protection mechanism.

Blob soft delete is also enabled for LAB with an initial retention period of:

```text
7 days
```

The retention value should be parameterized so that environments can adopt different values later.

These controls protect future Blob data against common accidental overwrite/delete scenarios without requiring a consumer-specific backup design.

They do not replace workload backups or disaster-recovery design.

### Lifecycle management

No lifecycle-management policy is created in Milestone 4.

No rules are introduced for:

- automatic tiering;
- automatic archival;
- age-based deletion;
- version expiry.

These rules depend on actual workload access and retention requirements and must therefore be introduced with the relevant consumer.

### Backup architecture

Milestone 4 does not create:

- Recovery Services Vault;
- Backup Vault;
- Azure Backup policy;
- workload-specific backup jobs;
- scheduled database dumps;
- PostgreSQL/Qdrant/Neo4j backup logic.

The foundational Storage Account may later become a destination for exports or backup artifacts, but that role is not assumed by Milestone 4.

The backup architecture for control-plane applications must be designed once their persistence model exists.

## Explicitly deferred decisions

### OpenTofu remote state

Whether devpod-ui/OpenTofu will use Azure Blob Storage as its remote-state backend is deferred to Milestone 8.

If selected, that milestone will define:

- the state container;
- authentication mechanism;
- state locking/concurrency behavior;
- RBAC;
- state retention/versioning requirements.

ADR-0005 does not assume that the foundational Storage Account must be used for OpenTofu state.

### Control-plane VM boot diagnostics

Boot diagnostics configuration belongs to Milestone 5.

Milestone 5 may use Azure-managed boot diagnostics or a dedicated Storage Account if a concrete requirement justifies it.

ADR-0005 does not reserve the foundational account for this purpose.

### Docker Compose persistent data

The persistence architecture for PostgreSQL/pgvector, Harpocrate, MCP Manager, Qdrant, Neo4j, or other application workloads is not decided in Milestone 4.

In particular, ADR-0005 does not decide that application or database data will be placed on Azure Files.

The control-plane compute/application design must determine whether persistent data belongs on:

- managed disks;
- Azure Files;
- Blob/object storage;
- application-native backups;
- another persistence mechanism.

### Azure Files

No Azure Files share is created in Milestone 4.

Azure Files will only be introduced when a concrete workload requires SMB/NFS semantics and the performance, locking, durability, and operational characteristics have been evaluated for that workload.

### Backup retention

Workload backup schedules and retention periods are deferred.

The 7-day Blob soft-delete configuration is a platform safety baseline, not a backup-retention policy.

### DEV and PROD redundancy

Only the LAB redundancy choice is made here.

DEV and PROD redundancy must be selected from their future durability, availability, cost, and disaster-recovery requirements.

### Private connectivity

Private Endpoints, Private DNS, and disabling public network access are deferred to Milestone 7.

## Consequences

### Positive

- The platform gains a durable shared storage foundation without coupling it prematurely to a workload.
- The Storage Account remains Bicep-owned and independent from ephemeral workspaces and Docker Compose application lifecycle.
- The account can support future Blob, Files, diagnostics, backup, or OpenTofu-state use without being recreated.
- LRS keeps LAB cost low while leaving redundancy configurable by environment.
- HTTPS-only, TLS 1.2 minimum, disabled anonymous Blob access, and disabled Shared Key authorization establish a secure baseline before any data exists.
- Managed Identity / Entra ID remains the preferred future authentication model.
- No speculative RBAC grants are introduced.
- The account remains compatible with the Private Endpoint architecture planned for Milestone 7.
- Blob versioning and soft delete provide a basic accidental-change protection layer before real workloads begin writing data.

### Negative

- Public network connectivity remains enabled until Milestone 7, even though anonymous access and Shared Key authentication are disabled.
- A single foundational account creates some shared blast radius until future workloads justify stronger isolation.
- Blob versioning and retained deleted data can increase storage consumption and cost once workloads begin writing data.
- Future consumers may require additional Storage Accounts if their security, networking, availability, or performance requirements diverge.
- No application can use the account until an appropriate future milestone creates the required data-plane resource and RBAC assignment.

## Alternatives considered

### Multiple Storage Accounts in Milestone 4

Rejected for now.

There are no concrete consumers whose isolation requirements justify multiple accounts.

Creating separate accounts for hypothetical state, backups, diagnostics, and application data would introduce unnecessary naming, RBAC, monitoring, and future Private Endpoint complexity.

Separate accounts remain valid when a future concrete requirement justifies them.

### ZRS for LAB

Rejected.

Cross-zone redundancy adds cost without a current LAB availability requirement.

The reusable module remains capable of receiving a different SKU for another environment.

### GRS/GZRS for LAB

Rejected.

Cross-region durability and disaster recovery have not been designed for LAB and would add cost and operational implications prematurely.

### Disable public network access in Milestone 4

Rejected for now.

Private Endpoints and Private DNS are explicitly deferred to Milestone 7.

Disabling public network access before an alternate network path exists would make the account unusable by future intermediate milestones.

### Network ACL deny-by-default in Milestone 4

Rejected for now.

The real consumer traffic patterns do not yet exist.

Network ACLs will be introduced when their required source networks and access paths are known.

### Enable Shared Key authorization

Rejected.

No current consumer requires account keys, while Entra ID and Managed Identity provide a stronger default security model.

Any future requirement to re-enable Shared Key must be explicitly justified.

### Grant storage RBAC to the control-plane identity now

Rejected.

The identity has no concrete storage consumer yet.

Granting data-plane permissions before need would violate the least-privilege strategy established by ADR-0004.

### Create Blob containers in Milestone 4

Rejected.

Container names, retention policies, access scopes, and consumers have not yet been established.

Containers will be created alongside their actual workloads.

### Azure Files for control-plane application persistence

Deferred rather than rejected.

No control-plane workload exists yet, and database/application persistence requirements have not been evaluated.

Selecting Azure Files now would prematurely constrain the future control-plane storage architecture.
