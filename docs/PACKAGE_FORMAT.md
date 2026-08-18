# 3012 package format

`.3012pkg` is a signed, sequential container designed for large files. The
reader verifies metadata and payloads from disk instead of loading the entire
package into memory.

## Binary layout

| Offset | Length | Value |
| --- | ---: | --- |
| `0` | 8 bytes | ASCII `3012PKG` followed by `00` |
| `8` | 8 bytes | Unsigned 64-bit manifest length, big-endian |
| `16` | variable | UTF-8 JSON `PackageDocument` |
| after manifest | variable | Entry payloads concatenated in manifest order |

The JSON document contains a `signed` manifest and a Base64 Ed25519
`signature`. The signature covers the canonical JSON encoding of `signed`.
Each entry records its exact byte length and lowercase SHA-256 digest.

## Validation rules

- Schema version must be supported and the publisher key must be pinned.
- Package identifiers must be UUIDs and entry identifiers must be unique.
- A bundle identifier plus relative path may appear only once.
- Paths must be relative and may not contain empty, `.`, `..`, or backslash
  components.
- Absolute paths, traversal, symlink entries, trailing bytes, and unknown
  operations are rejected.
- The current reader limits manifests to 2 MiB, entries to 10,000, and package
  files to 2 GiB.
- Payloads are hashed in chunks directly from disk before any transaction is
  allowed to modify a target root.

## MIME and UTI

The intended media type is `application/vnd.3012.package` and the exported
UTType is `app.3012.package`. App registration and Files import are tracked in
M4 and must be completed before the format is considered stable.

The format is versioned. Consumers must reject schema versions they do not
understand rather than attempting a best-effort import.
