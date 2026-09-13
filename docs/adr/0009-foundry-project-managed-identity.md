# ADR-0009 — Foundry Project Managed Identity

## Status

Accepted

This ADR partially supersedes [ADR-0008](0008-microsoft-foundry-foundation-model-access.md)
— **only** for the statement that the Foundry project's identity remains
`None`. Every other decision in ADR-0008 is unchanged.

## Context

Current Microsoft Foundry guidance and minimal project-creation examples
configure the `Microsoft.CognitiveServices/accounts/projects` resource with
a `SystemAssigned` managed identity. ADR-0008 originally left the project's
identity unset (`None`), reasoning that no concrete requirement for it had
been identified.

Aligning with the current, documented resource-creation shape avoids
depending on undocumented default identity behavior and keeps the project
resource consistent with the model Microsoft Foundry itself expects.

## Decision

Each Bicep-owned Foundry project receives:

```text
identity:
  type: SystemAssigned
```

This identity is created because it aligns the project resource with the
current Microsoft Foundry resource model and official creation examples,
and prepares the identity that project-level Foundry capabilities may
require. It does not, by itself, grant any access.

**No RBAC role is assigned to the project identity in Milestone 6 Phase 1.**
Permissions are added only when a concrete project capability requires
them — the same least-privilege principle already applied to the Foundry
account's own `SystemAssigned` identity in ADR-0008.

## Consequences

### Positive

- the project resource matches current Foundry guidance rather than relying
  on implicit/default identity behavior;
- the identity is available in advance for any future project-scoped
  capability, without granting any access today.

### Negative

- one more identity exists in the subscription with no assigned permissions
  today, requiring the same "created but unused" bookkeeping already
  accepted for the Foundry account's identity in ADR-0008.

## Alternatives considered

### Leave the project identity as `None` (original ADR-0008 position)

Rejected: current Microsoft Foundry documentation and minimal project
creation examples consistently configure `SystemAssigned` on the project,
making `None` a deviation from the documented model rather than a
deliberate simplification.
