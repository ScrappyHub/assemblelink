# AssembleLink Product Specification v1

## Promise

On a new Windows computer, a user chooses one or more complete work profiles, reviews a deterministic setup plan, approves it once, and AssembleLink installs or updates every automatically supported tool while clearly separating account-, license-, driver-, and manual-only work.

## Required entry points

1. **Set up this computer** — choose curated toolkits or individual tools, review, approve, execute, resume, verify.
2. **Update my tools** — discover upgrades for approved installed packages, review, approve, execute, verify.
3. **Restore a previous setup** — import an AssembleLink blueprint, validate it, resolve available catalog identities, review differences, execute.
4. **Browse all software** — search and filter the approved catalog; never send users to an unverified mirror.
5. **Build a custom toolkit** — save a selection of catalog identities without allowing arbitrary commands.

## Setup acceptance criteria

- The plan lists every selected tool, source/package identity, license class, automation status, dependencies, elevation expectation, and reboot expectation.
- Duplicate tools across toolkits are deduplicated by stable catalog ID.
- Dependency order is deterministic.
- Nothing executes until the user approves the displayed plan.
- Execution uses structured arguments, never catalog-provided command strings.
- Each item receives an outcome and verification signal.
- Progress is durably written after every item so an interrupted run can be inspected or resumed.
- Manual/account/license items never execute automatically.
- A completed run produces a JSON result and SHA-256 sidecar.
- Browser preview mode cannot execute machine commands.
- Every job toolkit resolves entirely through the reviewed software catalog and deduplicates shared foundations.
- Account-, subscription-, license-review-, driver-, and manual-only entries cannot enter the automatic executor.
- CLI inventory uses registry, exact Winget identity, or non-executing file metadata; inventory must not execute an arbitrary binary merely to obtain its version.
- Release mode restores executable engines and core catalog data from bytes embedded in the desktop binary before invoking PowerShell.

## Catalog and job coverage

- Software development: web, backend/API, native C/C++, Rust/Go, .NET, Java, Android, database, and CLI workflows.
- Cloud and infrastructure: DevOps/SRE, Kubernetes operations, containers, infrastructure-as-code, virtualization, networking, and major cloud CLIs.
- Cybersecurity: analyst, penetration-testing, traffic analysis, web assessment, password auditing, reverse-engineering, and DFIR foundations.
- Game development: Godot, Unity, Unreal, source control for large assets, native/.NET build tools, and content creation.
- AI and creative production: local AI, GPU foundations, recording, audio, image, vector, video CLI, and 3D tooling.
- The dashboard exposes reviewed categories and job families; package identity remains the installation authority.

## Supported v1 automation

- Windows 10/11 x64
- Winget-backed free/open-source or explicitly redistributable catalog entries
- Existing Winget package update detection
- Local blueprints containing catalog IDs only

## Explicit v1 boundaries

- Drivers, BIOS, paid licenses, account sign-in, Windows optional features, IDE extensions, and arbitrary scripts remain guided/manual until each has a dedicated threat model and verifier.
- macOS and Linux are not represented as supported.
- The installer must be code-signed before public distribution; an unsigned development installer is not a production release.
