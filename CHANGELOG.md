# Changelog

All notable AssembleLink changes are documented here.

## 0.1.0 - Release candidate

### Added

- Windows desktop dashboard for workstation setup, updates, software inventory, drivers, toolkits, and reconstruction blueprints.
- Curated catalog with 72 reviewed entries, 21 job toolkits, 34 categories, and nine job families.
- Local software/version intelligence with managed, application-candidate, developer-component, driver-component, and system-component classification.
- Approval-bound Winget planning and execution with durable progress, interruption recovery, verification, and receipts.
- Native workstation assurance that verifies sealed system, driver, software, and catalog evidence.
- Clean-machine release matrix auditing and fail-closed Authenticode gates.

### Security

- Packaged scripts, catalogs, and manifests are restored from trusted application resources at startup.
- Fixture evidence is rejected by live workstation assurance.
- Unknown provider/update state is never represented as current.
- Browser preview cannot execute workstation commands.

### Release blockers

- Production publication requires a trusted Authenticode certificate and timestamp.
- Eleven controlled clean-machine scenarios remain pending.
