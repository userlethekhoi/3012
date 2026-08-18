# 3012 roadmap

Last updated: 2026-08-18

This file is the public progress tracker. Mark an item complete only after the relevant build or test passes.

## Current checkpoint

- Status: **M10 in progress — M9 architecture is built; read-only Device Access awaits real-device validation**
- Current release: `0.1.0-dev`
- Last verified build: GitHub Actions `32129414693` (`19e8bfa`), including localization validation, Core access-router tests, both app targets, two IPA packages, and Latest release publishing.
- Next engineering task: sign Device Access without changing its MobileHouseArrest identity, validate read-only discovery on real devices, and record exact device/build results before enabling writes or DarkSword.
- Known limitation: this environment cannot run Xcode; the GitHub Actions build is the first macOS compile gate.

## Decisions locked for the next session

These decisions should not be reopened unless a concrete technical blocker is found.

### Package and update model

- Keep `.3012pkg` as the only native 3012 patch-package extension.
- Keep the exported UTType `app.3012.package` and MIME type `application/vnd.3012.package`.
- Do not create provider-specific extensions such as `.ios17`, `.mha`, or `.darksword`.
- Access-provider compatibility and patch-content compatibility are separate gates.
- Catalogs, packages, visibility, revocation, and compatibility metadata may update from the server without rebuilding the IPA.
- Native access providers, bridges, and exploit primitives must never be downloaded and executed from the catalog. Adding support for a new iOS build requires code review and a new IPA.

### Product and signing flavors

- Maintain one shared SwiftUI/product codebase with two build flavors:
  - `3012 Standard`: normal 3012 bundle identifier; Files-based access and normal signing.
  - `3012 Device Access`: `com.apple.mobile.MobileHouseArrest` Bundle ID and matching CodeDirectory identifier for the MobileHouseArrest route.
- Do not replace the Standard build; both variants share catalog, package, transaction, backup, restore, and UI code.
- Update the signed-export workflow and provisioning-profile mapping only after the Device Access target exists.

### Device/provider routing

- Detect the exact iOS version, build number, machine identifier, architecture, signing identity, and runtime probe result.
- Do not select a provider from the marketing chip name or iOS major version alone.
- Use a compiled fail-closed support matrix. A signed server policy may disable a known build but may not enable a provider absent from the IPA.
- Provider order is capability-driven, not package-driven:
  - `StandardFilesProvider`
  - `MobileHouseArrestProvider`
  - `DarkSwordProvider`
- If a provider fails before mutation, the router may fall back to Files access. If a kernel/access attempt has started, do not try another privileged provider in the same session; require a fresh session/restart.
- Never publicly claim a continuous iOS 17–27 range until every advertised build/device combination passes real-device tests.

### Upstream and attribution

- The maintainer reports explicit permission to use/remake the relevant 3105, FilzaSlop, and FilzaJailedDS work.
- Before importing source, record the exact upstream repository, commit, files, permission basis, and modifications in `THIRD_PARTY_NOTICES.md`.
- Remove upstream product branding, payloads, sample mods, and UI identity from the app.
- Keep the required acknowledgements in README/third-party notices and preserve any copyright/license notices required by the granted terms.

### Visual direction

- Delete the current `PREVIEW` badge, gradient hero, mock categories, mock patch rows, and `PatchSummary.previewItems`.
- White/system background is primary; use `systemBackground`, `systemGroupedBackground`, and `secondarySystemGroupedBackground`.
- Use a light system-blue accent. Blue is for actions/selection, green for supported/success/enabled, red for errors/unavailable, and yellow/orange only for real warnings.
- No decorative gradients, neon, purple, oversized marketing cards, or non-functional sections.
- Use native SF Pro through semantic SwiftUI fonts for normal content.
- Use SF Mono (`.system(..., design: .monospaced)`) for device identifiers, iOS build, bundle/signing identity, provider names, paths, hashes, transaction IDs, and session logs.

### Navigation direction

- Keep the visible product compact:
  - Home: device, iOS/build, signing, provider, support/probe status.
  - Files: App Data Browser when a provider is available.
  - Patches: Online, Manual, Installed/Restore in one feature area.
  - Settings: language, appearance, catalog channel, app/upstream information.
- Session Logs opens from a terminal button on Home rather than becoming another tab.
- Use `NavigationSplitView` on regular-width iPad and native compact navigation on iPhone.

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
- [~] Add Files import and package preview: bounded unverified preview added; trusted import remains blocked on production public-key provisioning.
- [x] Add local manual patch creation for large files selected through Files.

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
- [~] Add secret-safe signed archive/export workflow: protected workflow added; real certificate/profile run remains.
- [~] Test accessibility, memory, interrupted downloads, low storage, invalid signatures, and restore: automated large-file, invalid-signature, interrupted-state, and partial-rollback coverage added; device accessibility and low-storage tests remain.
- [ ] Publish a release candidate before `1.0.0`.

## M8 — UI reset and parity foundation (in progress)

- [x] Remove `PREVIEW`, hero gradient, mock categories, mock patch rows, and obsolete preview copy.
- [x] Replace Store mock data with a real Home/Dashboard feature.
- [x] Rework `AppTheme` to white/system surfaces with a lighter system-blue accent and semantic state colors.
- [x] Standardize SF Pro typography and SF Mono technical-value/log typography.
- [~] Add `DeviceProfileService` for machine identifier, iOS version/build, architecture, app version, and Bundle ID; authoritative signing-identity reporting remains for the Device Access flavor.
- [x] Add Compatibility Center models and UI; initially report Standard Files capability only.
- [x] Add a bounded, privacy-filtered, rotating `SessionLogger` and terminal-style `SessionLogView` with copy/export.
- [x] Add English, Vietnamese, and Simplified Chinese localization using String Catalogs; all visible legacy views and service-owned operation messages now use the selected app language.
- [x] Refresh README/USAGE text that still describes the app as an empty UI preview.
- [x] Add unit tests for Standard Files support policy and log redaction/rotation.
- [x] Pass core tests, Xcode device build, IPA packaging, and Latest release update for the first M8 batch (`32125571050`).

## M9 — Access-provider architecture

- [x] Define `DeviceAccessProvider`, `AccessProbe`, `AccessLease`, capability, and failure-stage contracts.
- [x] Add `AccessProviderRouter` with exact build/device/signing checks and fail-closed behavior.
- [x] Wrap the existing Files picker route as `StandardFilesProvider`.
- [x] Create separate `3012 Standard` and `3012 Device Access` targets/schemes.
- [~] Configure Device Access Bundle ID and CodeDirectory identity as `com.apple.mobile.MobileHouseArrest`; unsigned build identity is configured, signer preservation remains a distribution requirement.
- [x] Keep all SwiftUI features independent from `/var/...`, MCM, kernel, and exploit calls through the coordinator/provider boundary.
- [x] Add read-only provider mocks and router tests before importing privileged source.

## M10 — Device Access providers and compatibility matrix

- [x] Record approved upstream commits/files and attribution before publishing the port.
- [~] Port the MobileHouseArrest/MCM bridge behind `MobileHouseArrestProvider`; source is isolated to Device Access and awaits CI/device validation.
- [~] Implement read-only app discovery and bundle-ID-to-container resolution first; UI and bounded discovery are implemented, real-device validation remains.
- [ ] Add runtime read/write probes without destructive test writes outside a dedicated safe probe location.
- [ ] Connect verified container roots to the existing transaction engine only after read-only browsing is stable.
- [ ] Port the approved DarkSword path as an isolated provider for exact verified iOS 17/18/build/device combinations.
- [ ] Maintain a build-number and hardware test matrix; never infer support from a broad version range.
- [ ] Add a signed remote kill switch that can only disable providers/builds.
- [ ] Test app-container discovery, patch, rollback, restore, reboot/session failure, and changed-container UUID behavior on real devices.

## M11 — 3105 feature parity with 3012 identity

- [ ] App Data Browser: stable bundle identity, search, preview, multi-tab navigation, copy/move/rename/import/export, and safe conflict handling.
- [ ] Patch workspace: Online, Manual, Installed, import/export, folder/file rules, compatibility preview, transaction history, and restore.
- [ ] Limited Cleaner: only explicitly scoped cache/tmp locations, size preview, selection, confirmation, and logs.
- [ ] Wallpaper Lab as an optional, isolated module with its own compatibility checks and restore records.
- [ ] Responsive iPhone/iPad navigation and accessibility QA.
- [ ] Do not restore legacy `.3105` branding, payloads, bundled mods, old assets, or upstream UI.

## M12 — Online production and long-term upstream tracking

- [ ] Provision R2/S3, public HTTPS domain, protected signing keys, stable/beta catalogs, and pinned production public keys.
- [ ] Connect the real signed catalog to Home/Patches and remove all remaining mock content.
- [ ] Add package/app-version/capability compatibility rules without tying packages to provider names.
- [ ] Add an upstream provenance manifest pinned to reviewed commits; never auto-merge upstream code.
- [ ] Review upstream changes on a schedule and port only tested, attributed changes.
- [ ] Publish separate Standard and Device Access release assets with unambiguous signing/install notes.

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
- Added manual large-file patching through Files with streaming local package creation, preflight storage checks, transaction backup/rollback, installed history, and guarded restore.
- Verified GitHub Actions run `32122072821`; manual patch unit tests, iOS build, IPA packaging, and Latest release publishing succeeded.
- Agreed next-session direction: remove preview/mock UI, adopt white/system-blue native styling and SF Pro/SF Mono typography, add device/log/language/support foundations, then implement capability-routed Device Access providers behind separate build flavors.
- Replaced preview/mock Store content with a real Home dashboard, Files/Patches navigation, actual device/build/provider status, and terminal-style redacted rotating session logs.
- Added the English/Vietnamese/Simplified Chinese String Catalog foundation and verified Xcode/IPA/release workflow run `32125571050` for commit `a0bed0d`.
- Moved log redaction/rotation and Standard Files support policy into the testable Core package; all Core tests, device build, IPA packaging, and Latest release publishing passed in run `32125959014` for commit `5426855`.
- Completed the M9 provider contracts, fail-closed support matrix/router, separate Standard and Device Access targets, and router tests.
- Added a provenance-pinned MobileHouseArrest bridge and bounded read-only app-container browser for Device Access; no write or DarkSword path is enabled.
- Fixed mixed in-app languages across every tab, added a CI localization completeness validator, and replaced the source-code setting with author and Telegram contact details.
- Verified both app targets and published `3012-unsigned.ipa` plus `3012-DeviceAccess-unsigned.ipa` in run `32129414693` for commit `19e8bfa`.
