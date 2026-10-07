# Inventory and Update Intelligence v1 (proposal)

Status: implementation proposal; this does not weaken or replace a canonical contract.

## Purpose

AssembleLink must identify software already present on a Windows workstation, preserve the locally reported version, match only trustworthy catalog identities, and check approved providers for newer versions. Failure to reach a provider must be visible and must never be reported as "current."

## Trust boundaries

- Windows uninstall registry entries are untrusted observations. Display names, publishers, and versions are treated as data, never commands.
- Catalog identity and aliases are reviewed application data. Matching is normalized exact equality only; fuzzy matches are forbidden.
- Winget is queried with an exact package ID and the explicit `winget` source.
- GitHub release checks are allowed only where the catalog names an exact repository. Responses are bounded, cached, and schema checked.
- Tokens, uninstall commands, and full install paths are not written to the software-intelligence result.

## Result contract

`assemblelink.software_intelligence.v1` contains an observation timestamp, provider health, summary counts, and items. Each item has an installed version, available version, exact catalog match (or none), freshness, and one of:

- `current`
- `update_available`
- `installed_version_unknown`
- `provider_unavailable`
- `not_installed`
- `unmatched`

`unknown`, unavailable, malformed, rate-limited, and stale states remain distinct. Results and receipts are append-only and SHA-256 sidecars are generated from the exact bytes written.

## Determinism and replay

Provider observations are time-dependent evidence, not deterministic declarations. Deterministic fixtures cover matching, version classification, stale cache handling, malformed provider data, privacy exclusions, duplicate aliases, and unavailable package managers. An update installation still requires a separately hashed plan and explicit approval.
