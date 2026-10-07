# AssembleLink 0.1.0 (pre-release, unsigned development build)

**This is a development build for review. The installer is not code-signed yet**, so Windows SmartScreen will warn you ("Windows protected your PC"). Use *More info, then Run anyway* only if the SHA-256 below matches. A signed release will follow.

AssembleLink is a local-first workstation setup tool for Windows 10 (22H2) and Windows 11, x64. It inventories your computer, shows which approved tools are installed and which have updates, and installs only the plan you review and approve. macOS and Linux are not supported.

## What is new in this build

- A menu bar (File, Logs, Drivers, Help) plus a page tab strip, and a panda guide that stays out of the way at the bottom-left and remembers when you dismiss it.
- Installed software shown as a click-through inventory room, with Installed, Available and Status columns so you can see what has an update.
- Job toolkits: "See the tools" opens a panel over the card listing each tool and its version; the recycle button checks that toolkit for updates and takes you to the normal review before anything changes.
- Install history (Logs menu): what AssembleLink installed and removed, per tool, read from its own records with SHA-256 integrity checks. Winget removes the installers it downloads, so installer files are not kept.
- Uninstall (Help menu): remove approved-catalog programs, or AssembleLink itself, silently and only after you approve. Both write a receipt.
- Engine steps are time-limited, so a stalled Winget scan can no longer hang the app.

## Verify the download

Compare the installer's SHA-256 with `SHA256SUMS.txt` before running it:

```powershell
(Get-FileHash .\AssembleLink-0.1.0-windows-x64-setup-UNSIGNED-DEVELOPMENT.exe -Algorithm SHA256).Hash
```

## Known limits

- Unsigned: expect a SmartScreen warning.
- Winget is required for automatic installs and update checks.
- The update review lists every approved update on the machine, not only one toolkit's.
- Drivers, firmware, paid licenses and account sign-in stay manual.
- Unknown update status does not mean current.
- Self-uninstall works only on an installed copy, not a development run.
