# AssembleLink

AssembleLink is a local-first workstation intelligence and reconstruction platform.

It scans a machine, understands installed software, hardware, drivers, and capability groups, recommends missing tools, builds approved install queues, executes user-approved installs, and stamps receipts proving what happened.

It can also analyze a local development repository for supported top-level manifests—JavaScript, Python, Rust, Go, .NET, Java, CMake, and containers—and turn the detected toolchain into approved setup recommendations without executing project files.

New-machine planning includes a desktop/laptop profile and a user-selected maximum storage allocation. AssembleLink resolves toolkit dependencies, shows a conservative application-footprint estimate, and refuses to build a setup plan above that ceiling. Estimates do not include future project data, caches, containers, virtual machines, AI models, games, or later SDK downloads.

## Documentation

- [Usage](docs/USAGE.md)
- [Runbook](docs/RUNBOOK.md)
- [Who it is for](docs/WHO_IS_IT_FOR.md)
- [Threat Model](docs/THREAT_MODEL.md)
- [Install Security Model](docs/INSTALL_SECURITY_MODEL.md)
- [Roadmap](docs/ROADMAP.md)
- [WBS](docs/WBS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [UI Product Gap](docs/UI_PRODUCT_GAP.md)
- [Changelog](CHANGELOG.md)
- [GitHub release checklist](release/GITHUB_RELEASE_CHECKLIST.md)

## Download and verification

GitHub Releases is the intended distribution channel for the Windows x64 installer. A production asset is named `AssembleLink-<version>-windows-x64-setup.exe` and is accompanied by `SHA256SUMS.txt` and `release-manifest.v1.json`.

Before running a production installer, recompute its SHA-256 checksum and confirm Windows reports a valid Atlas Systems Authenticode signature with a trusted timestamp. Assets containing `UNSIGNED-DEVELOPMENT` in the filename are test builds and must not be redistributed as production releases.

## Current direction

The Windows desktop vertical slice now supports: select a workstation capability, build an approved queue, review the exact tools, explicitly approve installation, execute through Winget, and receive a stamped result for what was installed, already current, blocked, or failed.

## Development

Requirements: Windows, PowerShell 5.1+, Node.js, Rust, WebView2, and Winget.

From `ui`:

```powershell
npm ci
npm test
npm run build
npm run desktop
```

Create the Windows installer with `npm run desktop:build`. The installer is written under `ui/src-tauri/target/release/bundle/nsis` and includes the WebView2 offline installer for clean-machine compatibility.

The browser preview is intentionally read-only. Scan, profile, and installation commands are available only through the desktop security boundary.

## Safety

- Installs require an explicit confirmation showing the queued tools.
- Automatic installs are limited to approved catalog entries with a Winget package identity.
- Licensed or source-only tools remain manual-review items.
- Every execution writes state and a local receipt.
- Installed builds keep mutable state under the current user's application-data directory.

Do not commit generated workstation state, inventories, logs, or receipts.
