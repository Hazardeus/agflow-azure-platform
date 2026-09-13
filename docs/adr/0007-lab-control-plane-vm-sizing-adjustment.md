# ADR-0007 — LAB Control-plane VM Sizing Adjustment

## Status

Accepted

## Context

[ADR-0006](0006-control-plane-compute-persistence-lab-egress.md) selected
`Standard_D4as_v5` with Spot priority for the LAB control-plane VM.

Running `az deployment sub what-if` against the actual subscription surfaced
a hard provider-validated quota constraint that was not known at the time
ADR-0006 was written:

```text
QuotaExceeded — LowPriorityCores
Location: SwedenCentral
Current Limit: 3
Current Usage: 0
Additional Required: 4
```

`Standard_D4as_v5` requires 4 vCPUs of Spot (`LowPriorityCores`) quota. The
subscription's current `LowPriorityCores` quota in Sweden Central is 3,
which is one vCPU short. This is a subscription/region capacity fact, not a
template defect — `az bicep lint`/`build`/`build-params` all passed before
this failure occurred at Azure preflight validation.

`Standard_D2as_v5` (same `standardDASv5Family`, 2 vCPUs, Gen2, Spot-eligible,
Trusted-Launch-capable, no regional restrictions — verified via
`az vm list-skus` for Sweden Central) requires only 2 vCPUs of
`LowPriorityCores` quota, which fits within the current limit of 3 with
headroom to spare.

This ADR changes only the initial LAB VM sizing decision. It does not
reconsider, and does not silently rewrite, any other part of ADR-0006:
Spot priority, `Deallocate` eviction, `maxPrice`, the Public IP egress
design, the explicit `Deny-Internet-Inbound` NSG rule, identity attachment,
the independent persistent data disk, or the Docker/Compose host bootstrap
all remain as ADR-0006 decided.

## Decision

For LAB, the control-plane VM size changes from `Standard_D4as_v5` to:

```text
Standard_D2as_v5
```

with `vmPriority = Spot` and `evictionPolicy = Deallocate` unchanged.

This ADR does **not**:

- switch LAB to Regular priority;
- request a quota increase;
- change the deployment region;
- change any other ADR-0006 decision (persistence, egress, NSG, identities,
  security baseline, host bootstrap boundary).

`Standard_D4as_v5` remains a valid future LAB scale-up option once the
subscription's `LowPriorityCores` quota is increased and/or LAB workload
demand justifies the larger size. Choosing to scale up is deferred, not
rejected.

DEV/PROD VM sizing remains explicitly undecided and is not addressed by
this ADR — it must be selected from DEV/PROD's own requirements and quota
posture when those environments are implemented, not inherited from this
LAB-specific adjustment.

The VM size remains an environment-specific Bicep parameter
(`vmSize`), consistent with ADR-0006 — this ADR changes the LAB parameter
value, not the reusable `control-plane-compute.bicep` module, which
continues to accept `vmSize` as an input with no hardcoded default.

## Scope relative to ADR-0006

This ADR **partially supersedes** ADR-0006: specifically, the sentence in
ADR-0006 §2 selecting `Standard_D4as_v5` for LAB. All other decisions in
ADR-0006 remain in effect unchanged and unreviewed by this ADR. ADR-0006 is
not superseded as a whole and must not be rewritten; its LAB VM size
reference should be read together with this ADR.

## Consequences

### Positive

- LAB can now pass Azure preflight validation and be deployed without
  requesting a quota increase or weakening the approved Spot/eviction/egress
  design.
- The reusable compute module and its parameter contract are unaffected —
  only the LAB `.bicepparam` value changes.
- `Standard_D4as_v5` remains available as a documented future step rather
  than being discarded.

### Negative

- LAB now runs with half the vCPU (2 vs 4) and half the memory (8 GiB vs
  16 GiB) originally targeted in ADR-0006, which may be insufficient once
  the Docker Compose application stack (Postgres ×2, Qdrant, Neo4j, etc.) is
  actually deployed in a later milestone — that milestone must reassess
  whether `Standard_D2as_v5` is still adequate.

## Alternatives considered

### Request a `LowPriorityCores` quota increase to keep `Standard_D4as_v5`

Rejected for now — explicitly out of scope per this change's approval; also
introduces an external, asynchronous dependency (Azure quota approval) that
would block LAB progress indefinitely.

### Switch LAB to Regular (non-Spot) priority to keep `Standard_D4as_v5`

Rejected — explicitly out of scope per this change's approval; would also
reopen the Spot-cost decision ADR-0006 already made for LAB without a
concrete reason to reverse it.

### Change region

Rejected — explicitly out of scope per this change's approval; the platform
region (`swedencentral`) is an existing, unrelated decision.

## References

- ADR-0006 — Control-plane Compute, Persistence and LAB Egress (LAB VM size
  portion superseded by this ADR)
