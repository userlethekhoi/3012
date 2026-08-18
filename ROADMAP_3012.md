# 3012 roadmap

Last updated: 2026-08-18

This file is the public progress tracker. Mark an item complete only after the relevant build or test passes.

## Current checkpoint

- Status: **M2 in progress — clean app shell and UI foundation**
- Current release: `0.1.0-dev`
- Next engineering task: catalog models, trust configuration, and a file-based background download boundary.
- Known limitation: this environment cannot run Xcode; the GitHub Actions build is the first macOS compile gate.

## M1 — Clean public baseline

- [x] Remove legacy release artifacts and package repositories from source control.
- [x] Create a new repository structure and security policy.
- [x] Record origin, author, license, and attribution.
- [x] Add contribution and development documentation.

## M2 — Native app shell

- [x] Create `3012.xcodeproj` and shared scheme.
- [x] Add Store, Installed, Downloads, and Settings navigation.
- [x] Add semantic colors and reusable cards/status/empty states.
- [x] Add mock data without legacy payloads.
- [x] Add a real app icon.
- [ ] Add visual QA screenshots.
- [x] Pass the first macOS/Xcode CI build.
- [~] Add test coverage: core Swift Package unit tests added; UI test target remains.

## M3 — Signed online catalog and large downloads

- [x] Define and version the catalog JSON Schema.
- [~] Pin catalog publisher public keys: trust API complete; production key provisioning remains.
- [x] Verify Ed25519 catalog signatures.
- [x] Add ETag/cache behavior.
- [ ] Add background download tasks with pause/resume/retry.
- [ ] Persist task state across relaunch.
- [x] Verify SHA-256 by streaming from disk.
- [x] Test a package of at least 200 MB without loading it fully into memory.

## M4 — `.3012pkg`

- [ ] Finalize package extension, magic, UTI, and MIME type.
- [ ] Define manifest schema and per-file digests.
- [ ] Implement file-based inspect, verify, import, and remove.
- [ ] Reject traversal, absolute paths, symlinks, duplicate targets, and unsupported versions.
- [ ] Add Files import and package preview.

## M5 — Transaction and restore

- [ ] Implement backup and transaction journal.
- [ ] Apply changes deterministically.
- [ ] Roll back partial failures.
- [ ] Restore original files and remove only files created by the transaction.
- [ ] Integrate an access adapter only after its license and platform requirements are documented.

## M6 — Publishing

- [ ] Configure authorized object storage for immutable package versions.
- [ ] Add multipart upload tooling for large files.
- [ ] Generate size/digest metadata and sign catalogs in CI.
- [ ] Support stable/beta channels, hidden items, revocation, and rollback.

## M7 — Release quality

- [x] Add unsigned IPA workflow.
- [ ] Add secret-safe signed archive/export workflow.
- [ ] Test accessibility, memory, interrupted downloads, low storage, invalid signatures, and restore.
- [ ] Publish a release candidate before `1.0.0`.

## Progress log

### 2026-08-18

- Replaced the legacy workspace with a clean 3012 SwiftUI baseline.
- Added public documentation and transparent attribution to 3105/YangJiii.
- Added the first unsigned IPA GitHub Actions workflow.
- Did not migrate legacy patch payloads or access/exploit source.
- Fixed the first CI compile failure caused by an extra closing brace in `SettingsView.swift`.
- Verified GitHub Actions run `32113488367`: Release build, unsigned IPA packaging, and artifact upload succeeded.
- Added the final 3012 app icon and aligned the UI palette to blue, black, white, and system green states.
- Added rolling `dev-latest` prerelease publishing on every successful `main` build and versioned releases for `v*` tags.
- Verified run `32115618138` and prerelease `dev-latest`; the rolling release contains `3012-unsigned.ipa`.
- Added `ThreeZeroOneTwoCore` with unit-tested Ed25519 catalog verification, canonical JSON, atomic catalog cache, streaming SHA-256, and the catalog JSON Schema.
