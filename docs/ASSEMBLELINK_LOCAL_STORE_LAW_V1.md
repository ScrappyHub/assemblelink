# AssembleLink Local Store Law v1

Status: locked once proven by selftest and receipts

## Purpose

AssembleLink local store is the deterministic on-machine packet store for verified inbound packets within the standalone Atlas Systems instrument.

## Canonical location

- Root: `C:\dev\assemblelink\toolbelt\store`
- Packet directory: `C:\dev\assemblelink\toolbelt\store\<packet_id>`

## Required packet files

Each stored packet directory must contain at minimum:

- `manifest.json`
- `packet_id.txt`
- `sha256sums.txt`
- `payload\...`

## Identity law

- `packet_id.txt` is the authoritative packet identifier for the local store copy.
- The packet directory leaf name must equal the trimmed contents of `packet_id.txt`.
- If `manifest.json` contains `packet_id`, it must match the directory leaf and `packet_id.txt`.

## Verification law

Before a packet is considered localized:

1. Source packet directory must exist.
2. Source packet must contain `manifest.json`, `packet_id.txt`, and `sha256sums.txt`.
3. Every entry in `sha256sums.txt` must resolve to a file under the packet root.
4. Every resolved file hash must match its recorded SHA-256.
5. The destination store copy must be re-verified using the same rules.

## Store behavior

- Localization is copy-only.
- Existing destination packet directory may be replaced only as a full packet unit.
- No partial success is allowed.
- A receipt must be written only after destination verification passes.

## Receipt law

Localization receipt must include at minimum:

- schema
- packet_id
- utc
- source path
- destination path
- destination manifest SHA-256
- destination sha256sums SHA-256

## Non-goals

- No install/apply side effects
- No mutation of packet contents
- No trust in removable media after localization completes

## Success token

Canonical success token for localization flow:

`CLEAR_OK_DEV_LOCALIZED`
