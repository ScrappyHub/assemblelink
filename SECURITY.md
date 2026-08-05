# Security Policy

Do not publish workstation profiles, inventories, receipts, or logs with personal paths or machine identifiers.

Report suspected command execution, catalog provenance, installer verification, or privilege-boundary vulnerabilities privately to the project maintainers. Do not open a public issue containing secrets or exploit details.

AssembleLink must require explicit approval before installation, use approved package identities, preserve Windows elevation prompts, and write an outcome receipt for every execution attempt.

Production Windows downloads must have a valid Atlas Systems Authenticode signature, a trusted timestamp, a matching SHA-256 entry, and a release manifest. Treat unsigned or checksum-mismatched files as untrusted.
