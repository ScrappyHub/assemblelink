# SignPath Foundation application text (draft)

Copy these answers into the SignPath Foundation OSS application form. Verify each requirement against their current terms before submitting.

**Project name:** AssembleLink

**Repository:** https://github.com/ScrappyHub/assemblelink

**License:** MIT (see `LICENSE`)

**Short description:** AssembleLink is a local-first Windows 10/11 x64 workstation setup tool (Tauri 2, PowerShell, Winget). It inventories a computer, shows which approved tools are installed and which have updates, and installs only the plan the user reviews and approves. Every run writes a SHA-256 sealed receipt. macOS and Linux are intentionally unsupported.

**Why it is a good fit:** It is open source under the MIT license, publicly developed, and has no paid tier. Users run an installer on their own machines and need to be able to tell that the installer is genuine, which is what code signing provides. At present builds are published as unsigned previews (`UNSIGNED-DEVELOPMENT`), which triggers Windows SmartScreen warnings.

**Release process:** Releases are built by a GitHub Actions workflow (`prepare-signed-release.yml`). It runs the UI tests, `npm audit`, the Rust tests, `cargo fmt`, `cargo clippy` and `cargo audit`, the PowerShell tests, and the repository's UI and security audits before producing the NSIS installer. The installer is staged with a `SHA256SUMS.txt` file and a release manifest, and the release gate rejects an unsigned or checksum-mismatched production build.

**What would be signed:** The NSIS installer `AssembleLink_<version>_x64-setup.exe` and the packaged application executable, built from tagged commits on `main` only.

**Signing integration plan:** Replace the workflow's base64 PFX import with a SignPath request (upload artifact, submit signing request, download signed artifact). The release scripts will then pin the expected signer subject instead of a certificate thumbprint. No signing key is stored in GitHub.

**Security posture:** Private vulnerability reporting is enabled (see `SECURITY.md`). The application requires explicit approval before any install or uninstall, restricts actions to a reviewed catalog of package identities, and keeps a threat model in `docs/THREAT_MODEL.md`.

**Team and MFA:** Single maintainer (ScrappyHub). CONFIRM BEFORE SUBMITTING: two-factor authentication is enabled on the GitHub account (and will be on SignPath).

**Acknowledgements to confirm:** The signer shown to users will be "SignPath Foundation", not the project name. The project agrees to SignPath Foundation's code signing policy and to display it (for example on the README).
