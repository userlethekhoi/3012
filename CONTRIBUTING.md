# Contributing to 3012

Thank you for helping improve 3012.

## Before starting

1. Read `README.md`, `docs/ARCHITECTURE.md`, and `ROADMAP_3012.md`.
2. Check existing issues and pull requests.
3. Keep one pull request focused on one problem.
4. Discuss changes to package format, trust keys, access adapters, or transaction behavior before implementation.

## Development rules

- Use SwiftUI and semantic system colors for product UI.
- Keep domain models independent from views and networking.
- Prefer small types with explicit responsibilities.
- Do not add force unwraps for remote or package data.
- Do not load large packages fully into memory.
- Add validation at trust boundaries.
- Preserve accessibility, Dynamic Type, Dark Mode, and Reduce Motion behavior.
- Do not commit generated IPA/app/archive files, package payloads, credentials, signing material, or personal device data.

## Commit and pull request style

Use concise imperative commit subjects. Conventional prefixes are welcome:

- `feat:` new behavior;
- `fix:` bug fix;
- `docs:` documentation only;
- `refactor:` internal change without behavior change;
- `test:` tests;
- `build:` CI or build configuration.

A pull request should include:

- problem and intended behavior;
- screenshots for visible UI changes;
- test/build commands run;
- migration or compatibility impact;
- security considerations for catalog/package/networking changes.

## Attribution and third-party code

Do not paste code from another project without confirming its license. Add the source, copyright notice, license, and modification details to `THIRD_PARTY_NOTICES.md` in the same pull request.

## Content policy

Do not submit packages or catalog entries that distribute unauthorized paid content, cheats, credentials, private data, malware, or executable code downloaded for runtime execution.
