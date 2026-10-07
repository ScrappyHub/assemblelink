# AssembleLink Local-First Law v1

AssembleLink is a local-first desktop workstation bootstrap and governance instrument.

## Law

- AssembleLink must not require a hosted server.
- The production UI must run as a local desktop application / EXE.
- PowerShell command modules are the local execution backend.
- Vite/dev server usage is development-only preview behavior.
- Workstation inventory, receipts, profiles, plans, and manifests are stored locally under the repo/workstation state paths.
- Network use is allowed only for explicit package acquisition or user-approved sync/update checks.
- No always-on cloud dependency is allowed for Tier-0 correctness.

## Production target

The production target is:

- local EXE launcher
- local command execution
- local receipts
- local profiles
- optional package downloads via approved installers
- optional future sync/export, never mandatory hosting

## Success token

ASSEMBLELINK_LOCAL_FIRST_LAW_OK
