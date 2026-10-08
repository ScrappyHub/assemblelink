# Security Policy

Do not publish workstation profiles, inventories, receipts, or logs with personal paths or machine identifiers.

Report suspected command execution, catalog provenance, installer verification, or privilege-boundary vulnerabilities privately to the project maintainers. Do not open a public issue containing secrets or exploit details.

Report privately through GitHub private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability** (https://github.com/ScrappyHub/assemblelink/security/advisories/new). Include affected version, reproduction steps, and impact, but no real workstation profiles, receipts, or personal paths.

AssembleLink must require explicit approval before installation, use approved package identities, preserve Windows elevation prompts, and write an outcome receipt for every execution attempt.

Production Windows downloads must have a valid Authenticode signature, a trusted timestamp, a matching SHA-256 entry, and a release manifest. No signing route is in place yet, so only unsigned previews labelled `UNSIGNED-DEVELOPMENT` are published; they are test builds, not production releases. Verify the SHA-256 before running a preview, and treat unsigned or checksum-mismatched files as untrusted.
