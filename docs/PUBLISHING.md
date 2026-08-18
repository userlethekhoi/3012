# Publishing packages and catalogs

3012 separates app releases from package releases. Updating a package or hiding
an item does not require rebuilding the IPA.

## Storage layout

Large `.3012pkg` files are stored under an immutable content-addressed key:

```text
packages/<first-two-sha256-characters>/<full-sha256>.3012pkg
catalogs/stable.json
catalogs/beta.json
```

The package uploader uses the S3-compatible API. AWS CLI automatically switches
to multipart transfer for large files, so a 200 MB package does not pass through
Git history or GitHub Actions memory. Cloudflare R2 is the documented default,
but any authorized S3-compatible store can use the same layout.

## Required GitHub configuration

Create a protected GitHub Environment named `package-publishing`, require a
reviewer if appropriate, and add:

- Secrets: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ACCOUNT_ID`,
  `R2_BUCKET`, and `CATALOG_SIGNING_KEY_BASE64`.
- Variable: `R2_PUBLIC_BASE_URL`, an HTTPS public/custom domain without a
  trailing path requirement.

`CATALOG_SIGNING_KEY_BASE64` is the Base64 raw Ed25519 private key. Keep it only
in the protected environment. The matching public key is pinned in the app.
Never paste the private key into an issue, workflow input, commit, or log.

## Package workflow

1. Build and verify a `.3012pkg` locally.
2. Attach it to a private GitHub Release used as the workflow input boundary.
3. Run **Upload immutable package** with the exact tag and asset name.
4. Copy the URL, size, and SHA-256 from the workflow summary into the appropriate
   payload under `server/catalogs/`.
5. Increment `revision`, update `generatedAt`, and review visibility/revocation.
6. Merge the payload change, then run **Publish signed catalog**.

The catalog workflow signs the canonical payload, verifies its own output with
the derived public key, and uploads only the signed envelope. Stable and beta
channels use separate object names. Clients reject a catalog revision lower
than their cached revision.

## Revocation and rollback

Set `revoked` to `true` to prevent new application of a compromised package.
Set `visible` to `false` to remove an item from normal discovery without
claiming it is unsafe. Publish an older package by creating a new, higher catalog
revision that points to the older immutable package URL; never lower the catalog
revision or overwrite an immutable package object.
