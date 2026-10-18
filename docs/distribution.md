# Distribution

Transnote's Release builds, DMG creation, and GitHub Releases publishing are automated with GitHub Actions. **Unsigned builds** are currently distributed.

## Distribution flow overview

```text
vX.Y.Z tag push or workflow_dispatch
  → Tests
  → Release archive (unsigned)
  → Extract Transnote.app
  → Create DMG (Transnote.app + インストール.command + Applications link)
  → Generate SHA256 checksums
  → Generate SBOM (Transnote-<version>.cdx.json)
  → Upload to GitHub Release (DMG + .sha256 + SBOM, with hashes in the release notes)
```

GitHub Pages is deployed automatically when `site/` changes on the `main` branch, and directs users to [releases/latest](https://github.com/T3pp31/Transnote/releases/latest).

## GitHub Secrets

Unsigned distribution **requires no GitHub Secrets**. The Release workflow runs as-is.

If Developer ID signing and notarization are introduced in the future, you will need to join the [Apple Developer Program](https://developer.apple.com/programs/) and configure GitHub Secrets for the CI certificate (`APPLE_CERTIFICATE_BASE64`, etc.). For now, integrity verification is provided by distributing SHA256 checksums.

## Release steps

### Release from a tag

```bash
git tag v0.1.0
git push origin v0.1.0
```

Pushing a tag of the form `v*.*.*` triggers `.github/workflows/release.yml`.

### Manual release

1. Open **Actions → Release → Run workflow** on GitHub
2. Enter a tag name of the form `v0.1.0` in `version`
3. When the workflow completes, `Transnote-<version>.dmg` is attached to the GitHub Release

## Local helper scripts

| Script | Purpose |
| --- | --- |
| `scripts/export-release-app.sh` | Extracts `Transnote.app` from an `.xcarchive` |
| `scripts/create-dmg.sh` | Creates `Transnote-<version>.dmg` from `Transnote.app` |
| `scripts/generate-sbom.sh` | Generates an SBOM in CycloneDX JSON format with Syft |
| `scripts/install-transnote.command` | Install script bundled in the DMG (removes old version → places new version) |
| `Config/distribution.plist` | App name, former name, and install script name used for distribution |
| `Config/sbom.plist` | SBOM generation settings (Syft version, output format, paths) |

### Archive example

```bash
xcodebuild archive \
  -project LocalTranscriber.xcodeproj \
  -scheme LocalTranscriber \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/Transnote.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath DerivedData
```

### Export / DMG example

```bash
./scripts/export-release-app.sh \
  --archive build/Transnote.xcarchive \
  --output build/release

./scripts/create-dmg.sh \
  --app build/release/Transnote.app \
  --version 0.1.0 \
  --output build/dist
```

### SBOM example

CI scans `Package.resolved` (the lockfile of declared dependencies) on Ubuntu; Release scans the distributed `Transnote.app` on macOS. Components fetched at runtime, such as Whisper models, are outside the SBOM's scope. `generate-sbom.sh` reads `Config/sbom.plist` with PlistBuddy on macOS and with python3 + plistlib on Linux.

```bash
# Equivalent to CI (dependency lock only)
./scripts/generate-sbom.sh --mode ci

# Equivalent to Release (requires the .app)
./scripts/generate-sbom.sh --mode release --version 0.1.0
```

Output is written to `build/sbom/`. In CI it is saved as the artifact `sbom-cyclonedx` (retained for 30 days).

After generating, `generate-sbom.sh` verifies that there is at least one CycloneDX `components` entry of type `library`; if there are none, it exits non-zero and fails CI / Release (this prevents an empty SBOM from being left as an artifact due to a Syft regression or scan failure).

## Enabling Pages

The first time only, set the GitHub Pages Source to **GitHub Actions** in the repository settings. After that, `pages.yml` deploys `site/`.

## Artifacts

| File | Description |
| --- | --- |
| `Transnote-<version>.dmg` | Distribution DMG containing the unsigned app |
| `Transnote.dmg` | Alias DMG for the latest version (same contents as the versioned one) |
| `Transnote-<version>.dmg.sha256` | SHA256 checksum of the versioned DMG |
| `Transnote.dmg.sha256` | SHA256 checksum of the latest DMG |
| `Transnote-<version>.cdx.json` | SBOM in CycloneDX JSON format (based on the distributed binary, attached to the Release) |
| `Transnote-sbom.cdx.json` | SBOM in CycloneDX JSON format (based on the dependency lock, CI artifact) |
| `Transnote.app` | Bundle ID `com.transnote.LocalTranscriber` |
| `インストール.command` | One-click installer in the DMG ("Install.command"; removes the old version before placing the new one) |
| `初めにお読みください.txt` | Gatekeeper workaround steps for unsigned distribution ("Read Me First.txt") |
| `distribution.plist` | Distribution settings bundled in the DMG (read by the install script) |

## Notes for users

Unsigned apps may trigger a macOS Gatekeeper warning on first launch. Likewise, **インストール.command** may be blocked with "Not Opened" when double-clicked. Since right-click → Open may not work either, point users to `初めにお読みください.txt` in the DMG or the **Terminal steps** in [docs/install.md](install.md) (`xattr -cr` followed by `bash`).

After placing the app, the install script runs `xattr -cr` to remove the quarantine attribute from the app in Applications, so the first launch after installation goes smoothly.

## Verification commands

```bash
# Integrity check after download (for users)
shasum -a 256 -c Transnote-0.1.0.dmg.sha256

# SBOM validity check (for developers)
# generate-sbom.sh also checks the number of library components when it runs
jq -e '[.components[]? | select(.type == "library")] | length > 0' build/sbom/Transnote-sbom.cdx.json

hdiutil verify Transnote-0.1.0.dmg
ls -la build/release/Transnote.app/Contents/MacOS/Transnote

# Check the DMG contents
hdiutil attach Transnote-0.1.0.dmg -mountpoint /tmp/transnote-dmg
ls -la /tmp/transnote-dmg
# Should contain Transnote.app, インストール.command, 初めにお読みください.txt, distribution.plist, Applications
hdiutil detach /tmp/transnote-dmg
```
