# 3012 roadmap

Last updated: 2026-08-18

This file is the public progress tracker. Mark an item complete only after the relevant build or test passes.

## Current checkpoint

- Status: **M5 in progress — transactional package apply and restore**
- Current release: `0.1.0-dev`
- Next engineering task: finish the transaction recovery boundary, then connect background downloads and Files import to the app.
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
- [~] Add background download tasks with pause/resume/retry: app integration added; CI and device interruption tests remain.
- [~] Persist task state across relaunch: atomic state store and background session reconnection added; device test remains.
- [x] Verify SHA-256 by streaming from disk.
- [x] Test a package of at least 200 MB without loading it fully into memory.

## M4 — `.3012pkg`

- [x] Finalize package extension, magic, UTI, and MIME type.
- [x] Define manifest schema and per-file digests.
- [~] Implement file-based inspect, verify, import, and remove: inspect/verify complete; library import/remove remains.
- [x] Reject traversal, absolute paths, symlinks, duplicate targets, and unsupported versions.
- [ ] Add Files import and package preview.

## M5 — Transaction and restore

- [x] Implement backup and transaction journal.
- [x] Apply changes deterministically.
- [x] Roll back partial failures.
- [x] Restore original files and remove only files created by the transaction.
- [ ] Integrate an access adapter only after its license and platform requirements are documented.

## M6 — Publishing

- [ ] Configure authorized object storage for immutable package versions.
- [x] Add multipart upload tooling for large files.
- [~] Generate size/digest metadata and sign catalogs in CI: tooling/workflows added; protected secrets and production-key provisioning remain.
- [x] Support stable/beta channels, hidden items, revocation, and rollback.

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
- Added the signed, sequential `.3012pkg` reader, package schema, streaming payload verification, and adversarial path/length tests.
- Verified GitHub Actions run `32117550487` after the package-format milestone.
- Added a target-root-scoped transaction engine with preflight validation, backups, an atomic journal, deterministic apply, rollback, and restore tests.
- Verified GitHub Actions run `32117922769` after the transaction/restore milestone.
- Added a persisted background `URLSession` download manager with pause/resume/retry, streaming integrity verification, and download-state UI.
- Verified GitHub Actions run `32118654663`; core tests, app integration, IPA packaging, and rolling release publishing passed.
- Added content-addressed S3/R2 package upload and protected Ed25519 catalog publishing workflows for large online packages.
