# 3012 architecture

## Principles

3012 uses a feature-oriented SwiftUI structure with explicit trust boundaries. Views render state; networking downloads bytes to files; validators decide whether remote data is trusted; transactions own every filesystem mutation.

The codebase favors:

- native platform APIs;
- small dependency surface;
- file-based processing for large content;
- deterministic and reversible mutations;
- visible attribution and reviewable security decisions.

## Layers

```text
Features (SwiftUI)
    ↓
Application state / use cases
    ↓
Domain models and validation
    ↓
Infrastructure (network, disk, keys)
    ↓
Access adapter and transaction boundary
```

### App

Owns application entry, root navigation, dependency composition, environment values, and lifecycle integration.

### DesignSystem

Contains colors, typography, spacing, shapes, reusable controls, and accessibility defaults. It must not import feature models or networking types.

### Features

Each feature owns its views and presentation state. Features communicate through explicit application services rather than reaching into another feature's storage.

### Models

Contains value types used by domain behavior. Remote DTOs should be decoded and validated before conversion to trusted domain models.

The trust and package primitives live in `Packages/ThreeZeroOneTwoCore`, a Foundation/CryptoKit Swift Package with its own unit tests. Keeping this layer independent from SwiftUI allows CI to test security-sensitive parsing and verification before the app target is built.

### Infrastructure (planned)

- Catalog client and cache.
- Background download coordinator.
- Streaming digest verifier.
- Publisher key store.
- Package archive reader.
- Local metadata and package storage.

### Transaction boundary (planned)

All target mutations must pass through one transaction service. It is responsible for validation, preflight disk checks, backup, journal persistence, ordered writes, rollback, and restore.

## Trust model

Remote content is untrusted until all required checks succeed:

1. HTTPS transport completes.
2. Catalog schema and limits are valid.
3. Catalog signature matches a pinned publisher key.
4. Package size and streaming digest match catalog metadata.
5. Package signature and manifest are valid.
6. Every target and payload entry passes path and size validation.

A checksum delivered inside the same unsigned document cannot establish publisher identity.

## Large-file policy

Files are downloaded to a temporary URL and processed in chunks. Domain APIs accept file URLs or streams, not a complete package `Data` value. The app estimates download, extraction, and backup space before starting and removes incomplete temporary content after cancellation or verification failure.

## Compatibility policy

Package and catalog formats are versioned independently from the app. New formats require explicit compatibility handling; released files are immutable. Revocation is metadata, not deletion of a user's local backup.
