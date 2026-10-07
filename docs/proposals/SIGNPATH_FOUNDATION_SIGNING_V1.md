# SignPath Foundation Signing v1 (proposal)

Status: implementation proposal; does not weaken or replace a canonical contract. Supersedes the "open question" in MICROSOFT_STORE_AND_DEV_SIGNING_V1.md.

## Why

No-cost requirement. SignPath Foundation provides free, publicly trusted Authenticode signing for qualifying open-source projects. The private key stays in SignPath's HSM, which matches the post-2023 hardware-key rule and removes the long-lived PFX secret (a Critical threat-model row).

## Eligibility (SignPath terms, verify at application time)

- OSI-approved license, no commercial dual-licensing, no proprietary components.
- Project already released, actively maintained, documented, with verifiable reputation.
- Team owns the repository and signs only its own binaries built from it.
- Certificate is issued to SignPath Foundation, so the publisher shown to users is SignPath Foundation, not Atlas Systems.
- No malware or potentially unwanted behaviour. Data collection must be disclosed and disableable (AssembleLink is local-first, no telemetry).
- MFA for all team members on SignPath and the repository.
- Open-source policy requires every job before the signing request to run on GitHub-hosted runners (the existing workflow already uses windows-2022).

## Owner decisions required first

1. Choose an OSI license (checklist item currently open) and add LICENSE.
2. Make the repository public.
3. Accept that the signer identity is "SignPath Foundation".
4. Eligibility risk: "already released" may require a prior public release; a clearly labelled UNSIGNED-DEVELOPMENT pre-release may be needed to apply.

## Workflow change (after approval)

Replace PFX import and certificateThumbprint steps in prepare-signed-release.yml with: build unsigned NSIS, actions/upload-artifact, SignPath submit-signing-request (secret SIGNPATH_API_TOKEN, org/project/policy slugs as variables), download signed artifact, then the existing verify_release_artifact_v1.ps1, stage_release_v1.ps1 and draft release. The runtime exe inside the installer must be signed too, so the signing request covers both.

## Gate changes required

verify_release_artifact_v1.ps1 and stage_release_v1.ps1 currently expect an explicit certificate thumbprint. They must accept an expected-signer subject (SignPath Foundation) instead. The trusted-timestamp requirement and fail-closed behaviour are unchanged.

## Threat model deltas

- Removes: GitHub holding a signing PFX.
- Adds: SignPath API token exposure (scoped to submitter on one project); signer-identity mismatch (gate pins subject); dependency on a third-party signing service availability (release blocks, never falls back to unsigned).

## Free fallback if ineligible

Ship only UNSIGNED-DEVELOPMENT builds (release_eligible: false) with SHA256SUMS; users see a SmartScreen warning. Not a public release under the project's own gate.
