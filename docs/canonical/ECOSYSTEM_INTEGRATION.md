# Ecosystem Integration — AssembleLink

## Canonical service identity

| Field | Value |
|---|---|
| Service ID | `assemblelink` |
| Canonical name | AssembleLink |
| Ecosystem layer | `development.workstation-orchestration` |
| Standalone-first | `true` |

## Role

Local-first workstation orchestration and capability-reconstruction platform.

## This service owns

- Workstation intelligence
- Capability inventory
- Toolchain discovery
- Governed software acquisition
- Repository requirement analysis
- Environment reconstruction
- Local execution profiles

## This service does not own

- Repository governance
- Runtime monitoring
- Application deployment policy

## Upstream services

- `contract-registry`
- `archive-recall`

## Downstream consumers or operators

- `developers`
- `operators`
- `proteusops`

## Contract families

- `workstation.*`
- `capability.*`
- `toolchain.*`
- `acquisition.*`
- `environment.*`
- `receipt.*`

## Integration rules

1. This repository must remain independently understandable, testable, buildable, and releasable.
2. Ecosystem integrations extend capability but do not replace standalone correctness.
3. Integrations use explicit, versioned schemas and receipts.
4. No undocumented database sharing, hidden filesystem coupling, or implicit trust is permitted.
5. Producer claims must be independently verified by the receiving boundary where verification is required.
6. Integration failure must not silently corrupt local authoritative state.
7. Missing upstream services must produce an explicit unavailable, unknown, deferred, or failed state according to the local contract.
8. This repository's current implementation must not be treated as the complete product definition.

## Authoritative ecosystem sources

- `C:\dev\_ecosystem\SERVICE_MAP.md`
- `C:\dev\_ecosystem\service.registry.json`
- `C:\dev\_ecosystem\AGENT_POLICY.md`
- `C:\dev\_ecosystem\SHARED_INVARIANTS.md`

## Change governance

Changes to this service's ecosystem role, ownership boundaries, upstream dependencies, or downstream responsibilities require:

1. A proposal under `docs\proposals`.
2. A documented compatibility impact.
3. Updated service-map and registry entries.
4. Updated positive and negative integration tests.
5. A new service-map receipt.
