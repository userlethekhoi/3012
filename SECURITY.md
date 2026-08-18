# Security policy for 3012

## Supported development state

3012 is currently under active redevelopment and has not published a supported public release. Security fixes apply to the current development branch until a version support table is added here.

## Reporting a vulnerability

Do not publish a vulnerability, private key, signing certificate, provisioning profile, server token, patch password, or a package containing private user data in a public issue.

Until a private reporting address is configured, contact the repository owner through a private channel and include:

- affected version or commit;
- reproduction conditions;
- expected and actual behavior;
- impact assessment;
- a minimal test package with no third-party or personal data.

Do not attach production credentials or unauthorized application data.

## Repository rules

The repository must not contain:

- IPA, app bundles, archives, signing material, or provisioning profiles;
- `.3105` or `.3012pkg` release packages;
- passwords, private keys, API tokens, or local `.env` files;
- patches without permission to use and redistribute them;
- user backups, application containers, or personal device data.

All remote catalogs and packages must eventually be verified with pinned publisher keys. A checksum stored in the same unsigned catalog is an integrity check, not proof of publisher identity.

## Package safety requirements

3012 packages must be declarative data packages. They must not execute downloaded scripts, dynamic libraries, binaries, or commands. The package validator must reject path traversal, absolute targets, symbolic links, duplicate destinations, invalid signatures, unsupported schema versions, and files exceeding configured limits.
