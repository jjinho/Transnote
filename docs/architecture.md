# Architecture

Transnote (internal app name: LocalTranscriber) is designed as a native macOS app built with **SwiftUI + WhisperKit**. Python and Rust are not used in v1.

## Recommended app structure (implemented)

```text
LocalTranscriber/
├─ LocalTranscriberApp.swift
├─ Presentation/
│  ├─ MainWindowView.swift
│  ├─ MainWindowViewModel.swift
│  ├─ FileDropView.swift
│  ├─ TranscriptEditorView.swift
│  ├─ SettingsView.swift
│  ├─ StatusBarView.swift
│  ├─ ToastView.swift
│  ├─ UpdateCheckViewModel.swift
│  └─ TranscriptionCommands.swift
│
├─ Domain/
│  ├─ TranscriptionJob.swift
│  ├─ Transcript.swift
│  ├─ TranscriptSegment.swift
│  ├─ AppSettings.swift
│  ├─ ExportFormat.swift
│  └─ TranscriptionProgress*.swift
│
├─ Services/
│  ├─ WhisperKitTranscriber.swift
│  ├─ AudioFileService.swift
│  ├─ AudioImportService.swift
│  ├─ ExportService.swift
│  ├─ ModelAvailabilityService.swift
│  ├─ ModelDownloadService.swift
│  ├─ AudioPlayerService.swift
│  ├─ DropImportService.swift
│  ├─ DropURLParser.swift
│  ├─ DropFileNameResolver.swift
│  ├─ AudioFileNameResolver.swift
│  └─ SecurityScopedFileAccess.swift
│
├─ Infrastructure/
│  ├─ AppDirectories.swift
│  ├─ Logger.swift
│  ├─ ErrorMapper.swift
│  └─ AppVersion.swift
│
└─ Tests/
   ├─ ExportServiceTests.swift
   ├─ TranscriptModelTests.swift
   ├─ TranscriptionSmokeTests.swift
   └─ ... (unit tests)
```

## Key module design (implemented)

### WhisperKitTranscriber

All code that touches WhisperKit directly is confined here.

Responsibilities:

```text
- WhisperKit initialization
- Model selection
- Language selection
- Transcribing audio files
- Progress notifications
- Cancellation
- Error formatting
```

Interface:

```swift
protocol Transcriber {
    func transcribe(_ job: TranscriptionJob, progressHandler: @Sendable (TranscriptionProgressUpdate) -> Void?) async throws -> Transcript
    func cancel(jobID: UUID)
}
```

WhisperKit can automatically select and download the recommended model for the device when no model is specified, and its examples also show specifying a model explicitly with `WhisperKitConfig(model:)`. ([GitHub][1])

### ModelAvailabilityService / ModelDownloadService

Model management matters a great deal for UX.

Implemented:

```text
- List of available models
- Not downloaded / downloaded state
- Model download
- Model folder selection (deterministic on tied scores)
- Model file integrity verification
```

Planned (not implemented):

```text
- Model size display
- Recommended model display
- Model deletion
- Model preparation on first launch
```

Initial lineup:

| Display name              | Intended use                  |
| ------------------------- | ----------------------------- |
| Tiny                      | Smoke testing, fast preview   |
| Base                      | Lightweight use               |
| Small                     | Everyday use                  |
| Large v3 Turbo compressed | Accuracy-focused              |
| Large v3 Turbo            | High-performance Macs         |

The official README recommends `large-v3-v20240930_626MB` for multilingual accuracy and `tiny` as the fastest workflow for debugging. ([GitHub][1])

### AudioFileService / AudioImportService

Handles audio and video files.

Currently implemented:

```text
- wav
- mp3
- m4a
- flac
```

Planned (not implemented):

```text
- mp4
- mov
- Audio extraction
- Audio waveform preview
```

The input examples WhisperKit documents are WAV / MP3 / M4A / FLAC, so these four formats are officially supported first. ([Mintlify][2])

### ExportService

Export is implemented in-house for stability rather than depending on WhisperKit.

Supported formats:

```text
- TXT
- Markdown
- SRT
- VTT
- JSON
```

`Transcript` is easiest to work with in this shape:

```swift
struct Transcript: Codable, Identifiable {
    let id: UUID
    let sourceFileName: String
    let language: String?
    let createdAt: Date
    var fullText: String
    var segments: [TranscriptSegment]
}

struct TranscriptSegment: Codable, Identifiable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
}
```

Subtitle editing that requires word-level timestamps can wait until v1.1 or later. The WhisperKit documentation presents word-level timestamps as a key feature, but segment-level granularity is sufficient for the MVP. ([Mintlify][2])

## Screen design

### MainWindow (implemented)

```text
┌──────────────────────────────────────────────┐
│ Toolbar: Model / Language / Start / Save     │
├──────────────────────────────────────────────┤
│ Transcript editor (segment playback)         │
│ (history and file list not implemented)      │
├──────────────────────────────────────────────┤
│ Progress bar / status / cancel               │
└──────────────────────────────────────────────┘
```

### Required UI

| UI               | Contents                                                     |
| ---------------- | ------------------------------------------------------------ |
| File input       | Drag & drop, file selection                                  |
| Model selection  | Tiny / Base / Small / Large variants                         |
| Language         | Auto / Japanese / English                                    |
| Results          | Editable text view                                           |
| Progress         | Initializing, downloading model, transcribing, complete      |
| Save             | TXT / SRT / VTT / JSON                                       |
| History          | Past transcription results (not implemented)                 |

The macOS App Sandbox restricts an app's file access, so the design works with files and folders the user selects. To save an output location for persistent access, the design assumes security-scoped bookmarks. ([Apple Developer][3])

[1]: https://github.com/argmaxinc/argmax-oss-swift "GitHub - argmaxinc/argmax-oss-swift: On-device Speech AI for Apple Silicon · GitHub"
[2]: https://www.mintlify.com/explore/argmaxinc/WhisperKit "WhisperKit Documentation - WhisperKit"
[3]: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox "Accessing files from the macOS App Sandbox"
