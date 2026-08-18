# Development guide

## Local setup

1. Install Xcode 16 or newer.
2. Clone the repository.
3. Open `3012.xcodeproj`.
4. Select the shared `3012` scheme.
5. Build an iOS 16+ simulator destination.

The project currently has no external package dependency.

## Build verification

Simulator build:

```bash
xcodebuild \
  -project 3012.xcodeproj \
  -scheme 3012 \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

Unsigned device build:

```bash
xcodebuild \
  -project 3012.xcodeproj \
  -scheme 3012 \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build
```

Simulator names depend on the installed Xcode runtime. GitHub Actions uses the generic device build to avoid that dependency.

## Adding source files

Until the project moves to filesystem-synchronized groups, a new Swift file must be added both to its repository folder and to the target's Sources build phase in Xcode.

## UI review checklist

- Light and Dark Mode.
- Small iPhone and regular-width iPad.
- Dynamic Type accessibility sizes.
- VoiceOver labels and reading order.
- Reduce Motion.
- Empty, loading, error, offline, and long-text states.

## Security review checklist

- Identify every new trust boundary.
- Bound input counts and byte sizes before allocation.
- Avoid force unwraps for decoded/remote values.
- Keep private keys out of source and workflow logs.
- Process package payloads as files/streams.
- Verify before import and preflight before mutation.
- Record third-party source and license in the same change.

## Release workflow

The checked-in workflow only produces an unsigned IPA. A future signed release job must use a temporary keychain, tag/manual triggers, protected environments, and secrets unavailable to fork pull requests.
