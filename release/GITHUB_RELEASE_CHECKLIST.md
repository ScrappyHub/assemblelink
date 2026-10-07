# GitHub Release Checklist

## Repository

- [x] Restore or initialize valid Git metadata.
- [x] Configure the intended GitHub remote.
- [x] Project license: MIT (see LICENSE). Required for the SignPath Foundation free-signing route.
- [ ] Enable branch protection and require the test workflow.
- [ ] Review `SECURITY.md` contact instructions.

## GitHub secrets

- [ ] `WINDOWS_CERTIFICATE`: base64-encoded trusted code-signing PFX.
- [ ] `WINDOWS_CERTIFICATE_PASSWORD`: PFX password.

## Candidate

- [ ] Run the `Prepare signed Windows release` workflow.
- [ ] Confirm the draft installer and runtime both have the expected signer.
- [ ] Confirm the trusted timestamp is present.
- [ ] Download the draft asset and independently recompute `SHA256SUMS.txt`.
- [ ] Run all 12 controlled clean-machine cases against the exact signed candidate.
- [ ] Verify the matrix status reports 12/12 and `release_ready: true`.

## Publication

- [ ] Attach the completed clean-machine matrix proof and workstation proof.
- [ ] Review release notes and limitations.
- [ ] Publish the existing draft; do not rebuild after clean-machine validation.
- [ ] Test the public download, signature, installation, startup, inventory, and uninstall once more.
