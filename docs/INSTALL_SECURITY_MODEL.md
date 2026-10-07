# Install Security Model

## Flow

Approved catalog -> capability queue -> user review -> explicit execute -> admin prompt if needed -> winget or official source -> verification signal -> outcome classification -> receipt.

## Outcome classes

- installed_or_updated
- installed_or_already_present
- already_current
- blocked_file_lock
- requires_admin
- requires_reboot
- hash_verification_failed
- manual_review_required
- install_failed

## Receipt fields

- run_id
- UTC timestamp
- capability_id
- tool name
- source
- winget ID or official source
- duration
- exit code
- classified status
- hash verification signal
- action required
- output tail
- state path
