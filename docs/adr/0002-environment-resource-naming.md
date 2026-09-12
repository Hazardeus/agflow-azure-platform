# ADR-0002 — Environment-aware Azure resource naming

## Status

Accepted

## Context

The ag-flow platform supports multiple environments:

- lab
- dev
- prod

Azure environments may initially share a subscription or later be deployed
into separate subscriptions.

Resource names should remain deterministic and collision-free regardless of
the subscription strategy.

Many Azure resource names are difficult or impossible to rename after creation.

## Decision

Environment is included in Azure resource names when the resource represents
an environment-specific platform capability.

Resource Group naming convention:

- `rg-agflow-platform-{environment}`
- `rg-agflow-workspaces-{environment}`

Examples:

- `rg-agflow-platform-lab`
- `rg-agflow-workspaces-lab`
- `rg-agflow-platform-prod`
- `rg-agflow-workspaces-prod`

The environment name is derived from the existing `environmentName` Bicep
parameter.

Resource names must remain deterministic and must not require manually supplied
name parameters unless Azure uniqueness requirements make this necessary.

## Consequences

### Positive

- multiple environments can coexist in one subscription;
- separate subscriptions remain supported;
- resource ownership is immediately visible from the resource name;
- naming remains deterministic;
- future environment expansion does not require renaming Resource Groups.

### Negative

- resource names are slightly longer;
- environment information is duplicated between resource names and tags.

## Alternatives considered

### Environment-independent Resource Group names

Examples:

- `rg-agflow-platform`
- `rg-agflow-workspaces`

Rejected because this would prevent multiple environments from coexisting
inside the same subscription and would couple naming to a subscription-per-
environment strategy that has not been chosen.