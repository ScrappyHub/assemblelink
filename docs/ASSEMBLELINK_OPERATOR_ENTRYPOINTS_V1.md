# AssembleLink Operator Entrypoints v1

## Purpose

This document defines the authoritative operator-facing entrypoints for the current recovered AssembleLink removable-media handoff and local-store slice.

Canonical local repo root:
- `C:\dev\assemblelink`

Project identity:
- AssembleLink
- standalone Atlas Systems instrument
- node toolbelt link for bringing proper tools and governed handoff materials onto new nodes

## Authoritative operator entrypoints

### Echo — export packet to USB
- Script: `C:\dev\toolbelt\scripts\_RUN_toolbelt_copy_packet_to_usb_v2.ps1`
- Role: copy verified packet from Echo source outbox to removable media outbox
- Proven boundary: USB copy complete and verified on removable media

### Receiving node — one-button ingest from USB
- Script: `C:\dev\assemblelink\scripts\_RUN_dev_onebutton_ingest_latest_toolbelt_usb_v1.ps1`
- Role: resolve removable media, verify source packet, copy to inbox, verify destination, write receipt
- Proven success token:
  - `CLEAR_OK_DEV_GREEN`

### Receiving node — localize inbox packet to store
- Script: `C:\dev\assemblelink\scripts\_RUN_dev_localize_toolbelt_packet_v1.ps1`
- Role: re-verify inbox packet, copy to store, re-verify store copy, write receipt
- Proven success token:
  - `CLEAR_OK_DEV_LOCALIZED`

### Receiving node — seal inbox packet
- Script: `C:\dev\assemblelink\scripts\_RUN_vader_seal_toolbelt_inbox_v1.ps1`
- Role: verify inbox packet and write seal receipt bundle
- Proven success token:
  - `CLEAR_OK_VADER_SEALED`

## Rules

- These scripts are the current authoritative operator entrypoints for the recovered AssembleLink slice.
- Scratch patchers, temporary repair scripts, and one-off shell fragments are not operator entrypoints.
- Success tokens are authoritative only when emitted by these runners after verification completes.
- Future renames should move these entrypoints toward AssembleLink-native script names without changing verified behavior.

## Remaining cleanup

- promote AssembleLink-native script names where safe
- retire recovery-only scratch drift
- harden auto USB detection with negative vectors
- add operator failure-case proofs
