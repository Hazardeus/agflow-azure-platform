# ADR-0004 — Managed Identities and workspace provisioning RBAC

## Status

Accepted

## Context

Milestone 3 introduces the identity and RBAC foundation for the ag-flow
platform. Two distinct consumers need an Azure identity:

- the future control-plane VM (Milestone 5), which will eventually run
  Docker Compose applications and may need access to Storage, Microsoft
  Foundry, or other platform services;
- devpod-ui/OpenTofu, which provisions and destroys ephemeral workspace
  resources (VM, NIC, disk) in `rg-agflow-workspaces-{environment}` and
  attaches workspace NICs to the Bicep-owned `snet-workspaces` subnet.

These two consumers must not share an identity and must not share RBAC
scope. In particular, ADR-0001 requires that a resource is never managed by
both Bicep and OpenTofu — `snet-workspaces` is Bicep-owned, and OpenTofu must
only be able to *consume* it (attach NICs), never modify or delete it.

No suitable built-in role grants exactly "join this subnet, read-only"
without also granting write/delete or unrelated scope. The closest built-in
role, Network Contributor, also grants `Microsoft.Network/virtualNetworks/subnets/write`
and `.../subnets/delete` on its assigned scope. Granting it — even scoped to
a single subnet — would let the workspace provisioner modify or delete
Bicep-owned networking, which is unacceptable under ADR-0001.

A second built-in candidate, `Windows 365 Network User`, grants exactly
`Microsoft.Network/virtualNetworks/subnets/read` and
`.../subnets/join/action` with no write/delete — but it is a
Windows-365/Cloud-PC-specific built-in role (intended for the Windows 365
first-party service principal on an Azure network connection) and also
grants `Microsoft.Network/virtualNetworks/read` and
`.../virtualNetworks/usages/read` at whatever scope it is assigned, which is
broader than the workspace provisioner needs. Reusing a service-specific
built-in role outside its intended product is not appropriate here. See
"Alternatives considered" below.

Azure evaluates `Microsoft.Network/virtualNetworks/subnets/join/action` at
the scope of the **target subnet**, not at the scope of the resource being
created (confirmed against Microsoft documentation and a documented
`LinkedAccessCheckFailed` error referencing the subnet's own resource ID).
This means the join permission cannot be granted merely by scoping a role to
`rg-agflow-workspaces-{environment}`; it requires a separate role assignment
scoped directly to `snet-workspaces`, which lives in
`rg-agflow-platform-{environment}`.

## Decision

### Managed identities

Two user-assigned managed identities (UAMI) are created in
`rg-agflow-platform-{environment}`:

- `id-agflow-control-plane-{environment}`
- `id-agflow-workspace-provisioner-{environment}`

Both are durable, Bicep-owned platform resources, consistent with
`ARCHITECTURE.md` §3 ("Bicep owns ... Managed Identities; RBAC").

User-assigned identities are chosen over system-assigned for:

- lifecycle independence — the identities can be created in Milestone 3
  before the control-plane VM exists (Milestone 5);
- stable principal IDs / client IDs that do not change if the VM is
  recreated;
- the ability to attach more than one identity to the same VM, so the
  control-plane VM can eventually present two independently-scoped
  identities to two different consumers (itself, and devpod-ui/OpenTofu).

A hybrid design — a system-assigned identity on the control-plane VM plus
one user-assigned identity for the workspace provisioner — is technically
possible: a VM can have a system-assigned identity and one or more
user-assigned identities attached simultaneously. This hybrid was
considered and rejected in favor of two UAMIs, because the control-plane
identity itself also benefits from the same lifecycle independence and
stable, pre-existing principal/client IDs described above (it can be
created in Milestone 3, before the VM exists in Milestone 5, and its
references do not change if the VM is later recreated). Using UAMI for both
identities keeps the identity model uniform and avoids mixing two different
identity kinds for what are otherwise symmetric platform identities.

### Control-plane identity

`id-agflow-control-plane-{environment}` is created with **no RBAC role
assignments** in Milestone 3. Its future consumers (Storage, Microsoft
Foundry, etc.) do not exist yet, and granting permissions ahead of a
concrete need would violate least privilege. Permissions are added
incrementally by the milestone that introduces each real consumer.

### Workspace provisioner identity

`id-agflow-workspace-provisioner-{environment}` receives exactly two role
assignments.

#### 1. Virtual Machine Contributor on the workspace resource group

| | |
|---|---|
| Role | Virtual Machine Contributor |
| Role definition ID | `9980e02c-c2be-4d73-94e8-173b1dc7cf3c` |
| Scope | `rg-agflow-workspaces-{environment}` |

Verified against the current Azure built-in roles reference. Virtual Machine
Contributor covers `Microsoft.Compute/virtualMachines/*`,
`Microsoft.Compute/disks/*`, and `Microsoft.Network/networkInterfaces/*` —
but it also includes permissions beyond strict VM/NIC/disk management, such
as `Microsoft.Compute/availabilitySets/*`, `Microsoft.Compute/virtualMachineScaleSets/*`,
`Microsoft.Compute/cloudServices/*`, and join/read actions on load balancers,
public IP addresses, and network security groups. This broader-than-strictly
-needed permission set is accepted here because the assignment is restricted
to the dedicated ephemeral workspace resource group only — none of these
additional permissions extend outside `rg-agflow-workspaces-{environment}`,
and no more precise built-in role exists for VM+NIC+disk management.
Contributor is explicitly not used instead, because it would additionally
grant access to unrelated resource types (storage accounts, key vaults,
etc.) in that resource group, not just compute/network resources.

#### 2. Custom role on the workspace subnet

Network Contributor is **not** used for the subnet, because it grants
`subnets/write` and `subnets/delete` in addition to `subnets/join/action`.
Since `snet-workspaces` is Bicep-owned, granting write/delete on it to the
OpenTofu identity would let ephemeral-workspace tooling modify or delete
shared, durable networking — a direct violation of the ADR-0001 ownership
boundary.

Instead, a custom role is introduced:

| | |
|---|---|
| Role name | `Agflow Workspace Subnet Joiner` |
| Actions | `Microsoft.Network/virtualNetworks/subnets/read`, `Microsoft.Network/virtualNetworks/subnets/join/action` |
| NotActions | none |
| Assignable scope | `rg-agflow-platform-{environment}` (the resource group containing `vnet-agflow-{environment}` / `snet-workspaces`) |
| Assignment scope | `snet-workspaces` only (not the VNet, not the resource group) |

The custom role definition is durable Bicep-owned platform infrastructure,
in the same sense as the VNet and subnets it governs. Its assignable scope
must include the platform resource group so the role can be assigned at the
subnet underneath it; the actual assignment is still scoped down to the
single subnet resource, not the resource group or VNet.

This gives the workspace provisioner the ability to consume the subnet
(read it, join resources to it) without any ability to write or delete it.

### Deployment prerequisite

Creating the custom role definition and both role assignments requires the
deployment principal (the human or CI identity running `az deployment`) to
hold `Microsoft.Authorization/roleDefinitions/write` (to create the custom
role) and `Microsoft.Authorization/roleAssignments/write` (to assign roles)
at the relevant scopes. This is an operational prerequisite for whoever runs
the Milestone 3 deployment — it must not be granted to either runtime UAMI.
Neither `id-agflow-control-plane-{environment}` nor
`id-agflow-workspace-provisioner-{environment}` may hold
`Microsoft.Authorization/roleDefinitions/write` or
`Microsoft.Authorization/roleAssignments/write` at any scope, as that would
allow either identity to grant itself further permissions.

### Explicitly rejected

The workspace provisioner identity does not and must not receive:

- Owner
- User Access Administrator
- subscription-wide Contributor
- Contributor on `rg-agflow-platform-{environment}`
- Contributor on `rg-agflow-workspaces-{environment}`
- Network Contributor on the VNet
- Network Contributor on `snet-workspaces`
- any permission on `snet-control`
- any permission on `snet-private-endpoints`

No subscription-level workload permission is required by either identity.

### Managed Identity Operator

Not introduced in Milestone 3. This role would only be needed if OpenTofu
must attach a managed identity to the workspace VMs it creates — that is not
a current requirement and workspace VM design is out of scope for
Milestone 3. It will be introduced in whichever future milestone
concretely requires it.

### Future control-plane VM (Milestone 5)

The control-plane VM will have both UAMIs attached simultaneously. Because
more than one user-assigned identity can be attached to the same VM, a
workload must explicitly select which one to authenticate as — Azure does
not infer this automatically. devpod-ui/OpenTofu must be configured with the
`workspaceProvisionerIdentityClientId` output value (e.g. as the `client_id`
passed to `DefaultAzureCredential` / the `azurerm` provider's managed
identity configuration) and must not rely on implicit/default identity
selection.

### Outputs

The identity module will eventually expose:

- `controlPlaneIdentityId`
- `controlPlaneIdentityPrincipalId`
- `controlPlaneIdentityClientId`
- `workspaceProvisionerIdentityId`
- `workspaceProvisionerIdentityPrincipalId`
- `workspaceProvisionerIdentityClientId`

## Consequences

### Positive

- Workspace provisioning is confined to `rg-agflow-workspaces-{environment}`
  plus read/join-only access to one subnet — no path exists from the
  workspace provisioner identity to platform resources, Foundry, secrets, or
  the subscription.
- The Bicep/OpenTofu ownership boundary from ADR-0001 is enforced by RBAC,
  not just by convention: OpenTofu is structurally unable to write or delete
  `snet-workspaces`.
- The control-plane identity carries no unused permissions, avoiding
  privilege drift ahead of real requirements.
- User-assigned identities give Milestone 5 a stable, pre-existing set of
  principal/client IDs to attach to the control-plane VM without needing to
  create or recreate identities at VM deployment time.

### Negative

- A custom role definition is introduced, adding one more piece of
  Bicep-owned infrastructure to maintain (versus relying solely on built-in
  roles).
- Two role assignments (RG-scoped and subnet-scoped) are required for the
  workspace provisioner instead of one, adding a small amount of Bicep
  module complexity.

## Alternatives considered

### Contributor on `rg-agflow-workspaces-{environment}`

Rejected. Grants access to any resource type in the resource group, not just
the VM/NIC/disk resources OpenTofu actually manages.

### Network Contributor scoped to `snet-workspaces`

Rejected. Grants `subnets/write` and `subnets/delete` on Bicep-owned
networking, violating the ADR-0001 ownership boundary even though the grant
would be limited to a single subnet.

### System-assigned identity for the control-plane VM (hybrid design)

Rejected, though technically possible (a VM may carry a system-assigned
identity alongside one or more user-assigned identities). Not chosen because
the control-plane identity would then not exist until the Milestone 5 VM is
created, losing the lifecycle independence and stable principal/client ID
references that motivate UAMI for the workspace provisioner. Using UAMI
uniformly for both identities avoids this asymmetry.

### Windows 365 Network User for the workspace subnet

Rejected. Its action list (`subnets/read`, `subnets/join/action`) matches
what is needed, but it is a Windows 365/Cloud-PC-specific built-in role not
intended for general-purpose subnet consumption, and it additionally grants
`virtualNetworks/read` and `virtualNetworks/usages/read` at whatever scope
it is assigned — broader than the workspace provisioner requires. The
purpose-built custom role is used instead.

### Granting Managed Identity Operator in Milestone 3

Rejected for now. No concrete consumer (a workspace VM needing an attached
identity) exists yet; introducing it would be speculative.
