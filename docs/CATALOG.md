# Signed catalog format

3012 catalog schema version 1 uses a signed envelope:

```json
{
  "signed": {
    "schemaVersion": 1,
    "revision": 1,
    "channel": "stable",
    "generatedAt": "2026-08-18T00:00:00Z",
    "publisherKeyID": "production-2026",
    "patches": []
  },
  "signature": "BASE64_ED25519_SIGNATURE"
}
```

The signature is Ed25519 over the JSON encoding of `signed` produced with sorted keys and unescaped slashes. Date values are ISO-8601 strings so canonical encoding does not depend on locale or date encoder settings.

## Trust flow

1. Decode the outer document with strict application limits.
2. Validate schema version, revision, timestamps, entry counts, identifiers, HTTPS URLs, sizes, and digests.
3. Select a pinned public key by `publisherKeyID`.
4. Canonically encode the `signed` value.
5. Verify the Base64 Ed25519 signature.
6. Only then expose a `VerifiedCatalog` to the application.

The production private key must never be committed. Public keys are safe to embed in the app but key rotation must keep old keys available while supported catalogs/packages still use them.

The machine-readable schema is at `server/schemas/catalog.schema.json`.
