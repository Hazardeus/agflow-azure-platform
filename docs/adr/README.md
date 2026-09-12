# Architecture Decision Records

Architecture Decision Records document important architectural decisions for this repository.

## ADR lifecycle

Statuses may include:

- Proposed
- Accepted
- Superseded
- Rejected

Accepted ADRs are historical records and should not be silently rewritten when the underlying decision changes.

A new ADR should supersede the previous one.

## ADR index

| ADR | Decision | Status |
|---|---|---|
| [ADR-0001](0001-iac-ownership-boundaries.md) | Infrastructure ownership boundaries | Accepted |
| [ADR-0002](0002-environment-resource-naming.md) | Environment-aware Azure resource naming | Accepted |
| [ADR-0003](0003-shared-network-foundation.md) | Shared network foundation and outbound connectivity | Accepted |
| [ADR-0004](0004-managed-identities-rbac.md) | Managed Identities and workspace provisioning RBAC | Accepted |
| [ADR-0005](0005-shared-storage-foundation.md) | Shared Storage Foundation | Accepted |
| [ADR-0006](0006-control-plane-compute-persistence-lab-egress.md) | Control-plane Compute, Persistence and LAB Egress | Accepted |
| [ADR-0007](0007-lab-control-plane-vm-sizing-adjustment.md) | LAB Control-plane VM Sizing Adjustment (partially supersedes ADR-0006 LAB VM size only) | Accepted |