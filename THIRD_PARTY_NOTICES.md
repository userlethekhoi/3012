# Third-party notices and acknowledgements

## 3105

3012 is an independent remake inspired by the product experience and architecture of **3105**, developed by **YangJiii**. The 3012 maintainer thanks YangJiii and the original contributors for their work and for permitting the remake.

The clean 3012 baseline does not include legacy `.3105` packages, bundled patch payloads, release IPAs, old product assets, or the legacy exploit/access implementation.

If a future change incorporates source from 3105 or any of its upstream foundations, that change must:

1. identify the exact source and version;
2. verify that redistribution is permitted;
3. preserve required copyright and license notices;
4. document modifications;
5. update this file in the same pull request.

## Apple platform names

Apple, iOS, iPadOS, Xcode, SwiftUI, SF Symbols, and related names are trademarks of Apple Inc. 3012 is not affiliated with or endorsed by Apple.

## No bundled third-party package content

The public baseline intentionally contains no third-party patch catalog or package payload. Catalog maintainers are responsible for verifying rights to every item they publish.

## Reviewed access-provider sources

The maintainer reports direct permission from the relevant maintainers to remake and integrate the access logic, subject to removing legacy product identity and retaining acknowledgement. The following source was reviewed and pinned on 2026-08-18:

### FilzaSlop

- Repository: `https://github.com/0xjohnnydev/FilzaSlop`
- Commit: `ec490ade64b7755544833248d915e4adfc6f80d6`
- Source used: `MCMBridge.h`, `MCMBridge.m`
- 3012 files: `3012/Access/MCMBridge.h`, `3012/Access/MCMBridge.m`
- Modifications: renamed the retained lease, removed Filza integration, limited the public interface to runtime availability, bounded identifier enumeration, and read-only container-root activation; added strict host Bundle ID and path validation.
- Permission basis: maintainer-reported direct approval plus public source availability. The pinned repository contains no standalone root license file; this notice records the permission basis instead of assuming a license from repository visibility alone.

### 3105

- Repository: `https://github.com/YangJiiii/3105`
- Commit: `90ab4dd35823d58de10e6b8b78236e0e7e1ad32b`
- Files reviewed: `ThreeOneOSFive/exploit/mcm_bridge.h`, `ThreeOneOSFive/exploit/mcm_bridge.m`, `ThreeOneOSFive/exploit/bad_query.c`, `ThreeOneOSFive/helpers/AppIconHelper.m`, `ThreeOneOSFive/helpers/SupportPolicy.swift`, and read-only discovery portions of `ThreeOneOSFive/helpers/ContainerStore.swift`.
- Use in 3012: the fail-closed compatibility policy, MobileHouseArrest identity checks, bounded path-scoped grant logic, installed-app metadata lookup, and multi-source read-only discovery design are integrated behind 3012 provider contracts.
- License: GNU GPL v3. 3012 is also distributed under GNU GPL v3.
- 3012 files: `3012/Access/PathAccessBridge.h`, `PathAccessBridge.m`, `InstalledAppBridge.h`, `InstalledAppBridge.m`, and the provider/discovery integration in `3012/Services/DeviceAccessCoordinator.swift`.
- Modifications: access paths and inode fallback are allowlisted and bounded, discovery is read-only, handles are retained only for the active browser session, and all 3105 product names, `.3105` package behavior, payloads, UI, write operations, cleaner, wallpaper, and patch-workspace code are excluded from this milestone.

### FilzaJailedDS

- Repository: `https://github.com/34306/FilzaJailedDS`
- Commit: `b0802234110b581b9d185f22fbc907d7341384a3`
- Files reviewed: `README.md`, `Makefile`, and the high-level DarkSword source layout.
- Use in 3012: no kernel, sandbox-escape, XPF, vnode, offset, or injected Filza source is included yet. `DarkSwordProvider` remains disabled in the compiled support matrix until exact build/hardware rules, licensing provenance, safe lifecycle isolation, and real-device tests are complete.
- Permission basis: maintainer-reported direct approval plus public source availability. The pinned repository contains no standalone license file.
