# Transnote

An on-device transcription app for macOS. It processes local audio files with WhisperKit and displays and exports the results. Audio data stays on the device and is never sent to the cloud. The network is used only for the initial download of Whisper models.

The internal app name is LocalTranscriber; the public name is Transnote. The current version is **v0.1.5**.

<p align="center">
  <img src="Transnote.png" alt="Transnote" width="128" height="128">
</p>

## Download

| Method | Link |
| --- | --- |
| Latest DMG | [GitHub Releases (latest)](https://github.com/T3pp31/Transnote/releases/latest) |
| Distribution page | [GitHub Pages](https://t3pp31.github.io/Transnote/) |

> ⚠️ **You may see a "malware" warning on first launch, but Transnote is not malware.**
> Transnote is distributed without Apple's paid developer certification (code signing), so macOS Gatekeeper reports that it "cannot verify that it is free of malware." This is a standard safety notice shown for all unsigned apps, not a virus detection. Close it with "Done" and continue with the steps below.
>
> Note: this guidance applies **to Transnote only**. If another app shows a similar warning, always confirm that its source is trustworthy.

### Installation (summary)

Because the app is distributed unsigned, **インストール.command** ("Install.command") may not run when double-clicked or opened via right-click → Open. **Running it from Terminal is the reliable method.**

1. Open the DMG and read **初めにお読みください.txt** ("Read Me First.txt")
2. Run the following in Terminal, one line at a time:

```bash
xattr -cr "/Volumes/Transnote/"
bash "/Volumes/Transnote/インストール.command"
```

3. Eject the DMG
4. If a Gatekeeper warning appears on first launch, right-click → Open
5. Download a Whisper model the first time you use the app

See [docs/install.md](docs/install.md) for details.

## Key features

| Feature | Description |
| --- | --- |
| File selection / drag & drop | Supports wav / mp3 / m4a / flac |
| On-device transcription | Local processing with WhisperKit |
| Model selection / download | Tiny / Base / Small / Large v3 Turbo (compressed) / Large v3 Turbo |
| Language selection | Auto / Japanese / English |
| UI languages | Japanese and American English (follows the macOS language setting; other languages fall back to English) |
| Progress display / cancel | Shows each phase, from preparing to transcribing |
| View / edit / copy results | Transcripts can be edited in place |
| Word confidence scores | Per-word confidence (0–1) in the JSON export; low-confidence words flagged in the segment view |
| Segment playback | Plays audio for timestamped segments |
| Export | TXT / Markdown / JSON / SRT / VTT |
| Update check | Checks GitHub Releases at launch |

## Privacy

- Audio file contents are processed on the device and are not sent to external servers
- The network is used only to download Whisper models and to check for updates
- Runs in the App Sandbox

## Status

| Item | State |
| --- | --- |
| Version | v0.1.5 |
| UI/UX improvements (v0.1.5) | Tracked in [#114](https://github.com/T3pp31/Transnote/issues/114); PRs [#115](https://github.com/T3pp31/Transnote/pull/115)–[#132](https://github.com/T3pp31/Transnote/pull/132) opened |
| Implementation | SwiftUI app, tests, and CI in operation |
| Distribution | Unsigned DMG (GitHub Actions → GitHub Releases / Pages) |

### Upcoming

| Version | Scope |
| --- | --- |
| v0.3 | History, settings screen, long-audio support |
| v0.4 | Improved model management and error handling |
| v1.0 | Stabilized distribution flow (signing optional) |
| v1.1 | Video support, speaker diarization, recording |

See [docs/roadmap.md](docs/roadmap.md) for details.

## Tech stack

| Area | Technology |
| --- | --- |
| UI | SwiftUI |
| Transcription | [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) 0.18.0 (pinned in Package.resolved) |
| Audio processing | AVFoundation |
| Settings | `Config/Defaults.plist` + UserDefaults |
| Persistence | File system (`~/Library/Application Support/LocalTranscriber/`) |
| Testing | XCTest |
| CI/CD | GitHub Actions (macOS 15, Xcode 16.4) |
| Distribution | Unsigned DMG + `インストール.command` |

Python and Rust are not used in the app. Python 3 is used to regenerate the Xcode project.

## Requirements

| Item | Version |
| --- | --- |
| macOS | 14.0 or later |
| Xcode | 16.0 or later (CI uses 16.4) |

WhisperKit is provided as a Swift Package from `argmaxinc/argmax-oss-swift` and is pinned to version 0.18.0 (revision `e2adabb`) in `LocalTranscriber.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Prerequisites follow the official README.

## Project structure

```text
Transnote/
├── LocalTranscriber/       # App (Domain / Services / Presentation)
├── LocalTranscriberTests/  # Unit and integration tests
├── Config/                 # App and distribution settings
├── docs/                   # Design and operations docs
├── scripts/                # Build and distribution scripts
├── site/                   # GitHub Pages landing page
└── .github/workflows/      # CI / Release / Pages
```

## Building for development

```bash
# To regenerate the Xcode project
python3 scripts/generate_xcodeproj.py

# Tests (unsigned)
xcodebuild test \
  -project LocalTranscriber.xcodeproj \
  -scheme LocalTranscriber \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath DerivedData

# Debug build
xcodebuild build \
  -project LocalTranscriber.xcodeproj \
  -scheme LocalTranscriber \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Release builds and DMG creation run automatically in GitHub Actions when a `v*.*.*` tag is pushed. No GitHub Secrets are needed because distribution is unsigned. See [docs/distribution.md](docs/distribution.md) for operational details.

## Documentation

| File | Contents |
| --- | --- |
| [docs/install.md](docs/install.md) | Installation steps for end users |
| [docs/distribution.md](docs/distribution.md) | Release builds and DMG distribution |
| [docs/architecture.md](docs/architecture.md) | App structure, module design, screen design |
| [docs/roadmap.md](docs/roadmap.md) | Implementation phases, schedule, extension plans |
| [docs/spec-v0.1.md](docs/spec-v0.1.md) | v0.1 specification and scope |

## References

- [WhisperKit (argmax-oss-swift)](https://github.com/argmaxinc/argmax-oss-swift) — Swift Package, model management, transcription API
- [WhisperKit documentation](https://www.mintlify.com/explore/argmaxinc/WhisperKit) — Streaming, VAD, timestamps
- [File access in the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) — Reference for the security-scoped bookmark design
- [Developer ID](https://developer.apple.com/support/developer-id/) — Signing and notarization for distribution outside the Mac App Store
