# Microsoft Store Channel and Development Signing v1 (proposal)

Status: implementation proposal; this does not weaken or replace a canonical contract. The canonical release path (NSIS, Authenticode with trusted timestamp, GitHub draft release, 12-case clean-machine matrix) is unchanged.

## Findings

- Tauri 2 bundles EXE and MSI only. It does not emit MSIX. (Tauri docs: distribute/microsoft-store.)
- The Tauri Store route submits the existing NSIS installer as an unpackaged Win32 app. The Store requires that installer to be code-signed by a trusted CA and to support silent install (`/S`). The Store does not sign the EXE for us, so this route does not remove the need for a trusted Authenticode certificate.
- The Store requires the WebView2 offline installer mode. The current configuration already uses it.
- Store policy 10.2.4.1 requires non-integrated dependencies to be disclosed in the first two lines of the listing description. AssembleLink depends on Winget (App Installer) and installs third-party software, so the listing must say so. Policy fit for an app whose purpose is installing other software must be confirmed with Partner Center before investing in the channel.
- A true MSIX build would be a second packaging pipeline. MSIX runs the app in a package identity with a read-only install directory, which interacts with the packaged-engine reseed model and the admin-elevated Winget execution. It would need its own threat-model rows and clean-machine matrix.

## Decision options

1. Dev signing only (self-signed): supported by the current PFX workflow. Output must stay `UNSIGNED-DEVELOPMENT` and `release_eligible: false`. Never a public release.
2. Store as an additional channel for the NSIS installer: needs a trusted signature anyway, plus Partner Center enrollment, a Store listing, and dependency disclosure. No MSIX.
3. True MSIX: separate pipeline, deferred. Not proposed for v0.1.0.

## Proposed changes if option 1 and 2 are accepted

- Add `tauri.microsoftstore.conf.json` (merge-only config; NSIS target, offline WebView2, publisher name distinct from product name).
- Add a documented, non-release `scripts/release/new_dev_signing_cert_v1.ps1` that creates a self-signed code-signing certificate in the CurrentUser store for local pipeline tests only.
- Release checklist: add a Store submission section gated on the existing signed, clean-machine-validated candidate. The Store receives the same bytes as the GitHub draft; no rebuild.
- Threat model rows: Store channel substitution, listing dependency disclosure, self-signed certificate leaking into a release.

## Invariants preserved

- Unsigned or self-signed artifacts fail the public release gate.
- The Store is a distribution channel, never a signing authority for the canonical gate.
- No rebuild after clean-machine validation.

## Open question for the owner

Which trusted signing option (Azure Artifact Signing, OV with cloud signing, EV) will produce the signature the Store and GitHub both require? That decision gates both channels.

Status (2026-10-08): SignPath Foundation declined the project for insufficient public track record. Azure Artifact Signing was set up and validated for an individual, but individual validation places the legal name and locality in the certificate subject, which the maintainer chose not to publish. Remaining routes: an organization identity (for example an LLC) validated through Azure Artifact Signing, or reapplying to SignPath later. Until then only unsigned previews are published.
