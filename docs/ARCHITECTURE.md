# AssembleLink Architecture

## Trusted desktop runtime

The production executable embeds an explicit allowlist of catalogs and PowerShell engine files. Startup writes only those reviewed files to per-user application data. Repository-wide script or manifest trees are never packaged or copied. Desktop commands invoke fixed script paths, and installation scripts construct Winget argument arrays from approved package identities rather than executing catalog or manifest command text.

Repository analysis reads bounded, supported top-level project manifests without executing project content. It emits `assemblelink.repository_requirements.v1`, maps detected toolchains to approved catalog IDs, and seals the result with a receipt and SHA-256 sidecar.

## Layers

Installed UI -> narrow Tauri IPC commands -> trusted embedded engines/catalog -> per-user state and hashed receipts.

Bundled public-state JSON is preview/demo material only. Installed machine intelligence comes from desktop IPC and fails closed when local collection is unavailable.

## Engines

- al_system_profile_v1.ps1
- al_workstation_health_v1.ps1
- al_capability_resolver_v1.ps1
- al_driver_profile_v1.ps1 (`assemblelink.driver_profile.v2`)
- al_recommended_actions_v1.ps1
- al_install_plan_from_capability_v1.ps1
- al_install_queue_v1.ps1
- al_install_queue_execute_v1.ps1

## State artifacts

- system_profile.latest.json
- workstation_health.latest.json
- capability_graph.latest.json
- driver_profile.latest.json
- recommended_actions.latest.json
- install_queue.<capability>.latest.json
- install_queue_execution.<capability>.latest.json

## Receipts

Receipts live under proofs/receipts.

Release mode restores trusted engine and catalog bytes from the compiled executable before operations. Mutable observations remain under the per-user runtime and never replace embedded executable policy.
