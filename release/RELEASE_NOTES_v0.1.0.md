# AssembleLink 0.1.0

AssembleLink is a local-first Windows workstation setup and reconstruction dashboard. It inventories the computer, identifies managed development tools, checks approved update providers, assembles job-focused toolkits, and executes only the installation plan the user explicitly approves.

## Highlights

- One dashboard for software development, cybersecurity, game development, infrastructure, AI, and creative toolkits.
- 72 reviewed catalog entries and 21 curated job toolkits.
- Live hardware, driver, software, and version inventory.
- Managed tools, unrecognized application candidates, and SDK/runtime/system components are shown separately.
- Deterministic setup plans, durable progress, safe resume, machine blueprints, and sealed receipts.
- Packaged WebView2 offline installer for clean or disconnected Windows installation.

## Windows requirements

- Windows 10 22H2 or Windows 11, x64.
- Internet access is required to download software from approved providers. AssembleLink itself can install without downloading WebView2.
- Winget is required for automatic software installation and approved update checks.

## Verify the download

Compare the installer SHA-256 value with `SHA256SUMS.txt`, then verify that Windows reports a valid Atlas Systems Authenticode signature and trusted timestamp. Do not install a production release that is unsigned or whose checksum differs.

## Important boundaries

- Drivers, firmware, paid licenses, account sign-in, optional Windows features, and arbitrary scripts remain guided/manual.
- Unknown update status does not mean current.
- Workstation assurance does not claim malware absence, network security, or firmware freshness.
