# ADR-0001 — Infrastructure ownership boundaries

## Status

Accepted

## Context

The ag-flow platform uses several infrastructure and deployment technologies:

- Azure Bicep
- OpenTofu embedded in devpod-ui
- Docker Compose

Overlapping ownership would create drift and lifecycle conflicts.

## Decision

Bicep owns long-lived Azure platform resources.

devpod-ui/OpenTofu owns ephemeral workspace resources.

Docker Compose owns application containers running on the control-plane VM.

No resource may be managed by both Bicep and OpenTofu.

## Consequences

### Positive

- clear lifecycle ownership;
- reduced state conflicts;
- workspace destruction does not affect shared infrastructure;
- Bicep remains Azure-native for the platform layer.

### Negative

- two IaC engines exist in the solution;
- explicit contracts are required between Bicep and OpenTofu.

## Alternatives considered

### Everything in OpenTofu

Rejected for now because devpod-ui already has a dedicated workspace
lifecycle while the Azure platform has a different lifecycle.

### Everything in Bicep

Rejected because workspace lifecycle is already implemented by devpod-ui
using OpenTofu.