# AssembleLink — WBS / Status v1

## Project identity

AssembleLink is a standalone Atlas Systems instrument.

It is the node toolbelt link for bringing the proper tools and governed handoff materials onto new nodes for operator workflows such as:

- pipelines
- forensics
- cybersecurity
- software development
- related node bootstrap and handoff work

Canonical local repo root:
- `C:\dev\assemblelink`

## Current recovered scope

Recovered and proven packet:
- `e3c7f30f970a9d1b5aa72f09e579406522bfcbaeda385e4a4fe98e1352be1b17`

Recovered and proven flow:
1. Packet built on Echo
2. Packet copied to USB outbox
3. Vader ingests from USB and verifies
4. Vader writes ingest receipt
5. Vader seals ingest result
6. Dev ingests from USB and verifies
7. Dev localizes packet into local store
8. Dev writes localization receipt

## Canonical locations for the recovered slice

### Echo source packet
- `C:\dev\toolbelt\packets\outbox\<packet_id>`

### USB outbox
- `<USB>:\echo_transport\toolbelt\outbox\<packet_id>`

### Local inbox on node
- `C:\dev\assemblelink\toolbelt\inbox\<packet_id>`

### Local store on node
- `C:\dev\assemblelink\toolbelt\store\<packet_id>`

### Local receipts
- `C:\dev\assemblelink\toolbelt\inbox\_receipts\...`
- `C:\dev\assemblelink\toolbelt\store\_receipts\...`

## WBS

### AL-01 Packet export from source node
Status: GREEN
- Source packet exists
- Packet contains `manifest.json`, `packet_id.txt`, `sha256sums.txt`, payload
- USB export runner proven

### AL-02 USB verification on export
Status: GREEN
- Destination USB copy hash-verified
- `packet_id.txt` matched folder
- transfer receipt written
- safe unplug boundary proven

### AL-03 Node ingest from USB
Status: GREEN
- USB source verified on ingesting node
- `packet_id.txt` matched folder
- inbox copy verified
- ingest receipt written

### AL-04 Node seal / proof boundary
Status: GREEN
- inbox packet verified
- seal receipt written
- sealed success token emitted

### AL-05 Dev ingest from USB
Status: GREEN
- one-button ingest runner proven
- explicit USB drive letter path proven
- destination verify pass proven
- ingest receipt written

### AL-06 Dev localization to store
Status: GREEN
- localized into deterministic store root
- store copy re-verified
- localization receipt written

### AL-07 Automatic USB detection hardening
Status: PARTIAL
- explicit `-UsbDriveLetter` path is proven
- automatic detection path now has a recovered working overwrite
- still needs dedicated negative-vector proofing and final cleanup

### AL-08 Repo identity cleanup
Status: IN PROGRESS
- dedicated `C:\dev\assemblelink` home now exists
- recovered slice copied into AssembleLink home
- remaining file and naming cleanup still needed

### AL-09 One-button end-to-end operator path
Status: PARTIAL
- ingest side one-button path is proven
- localization path is proven
- still need one clearly promoted authoritative operator path per node role

### AL-10 Negative vectors / failure proofing
Status: TODO
- no usb detected
- wrong usb detected
- outbox missing
- packet folder missing
- `packet_id` mismatch
- missing manifest
- missing `sha256sums.txt`
- destination mismatch
- receipt absence / partial copy boundaries

## Definition of Done for this slice

AssembleLink removable-media handoff and local-store slice is done when:

1. Source node can export a packet to USB with deterministic verification and receipt
2. Receiving node can ingest from USB, verify, receipt, and seal deterministically
3. Dev can ingest from USB deterministically with one authoritative runner
4. Dev can localize into store with deterministic re-verification and receipt
5. Each boundary emits a clear success token
6. Safe unplug boundary is explicit and only emitted after verification and receipt
7. Automatic USB detection is robust or intentionally disabled in favor of explicit drive input
8. Authoritative runners are promoted and scratch drift is retired
9. Negative vectors exist for expected operator and media failure modes
10. Naming, docs, and repo structure are aligned to AssembleLink

## Progress estimate

Recovered removable-media handoff and local-store slice:
- about 70% complete

What is proven:
- export
- USB verify
- node ingest
- node seal
- dev ingest
- dev localization

What remains:
- authoritative runner cleanup
- auto-detect hardening proof
- negative vectors
- repo naming cleanup
- final operator-ready documentation

## Canonical success tokens observed

- `CLEAR_OK_TO_UNPLUG_USB`
- `CLEAR_OK_VADER_SEALED`
- `CLEAR_OK_DEV_GREEN`
- `CLEAR_OK_DEV_LOCALIZED`
