# Roadmap

## Implementation phases

### Phase 1: Minimal CLI / service validation

Before building the GUI, confirm that WhisperKit can be called from Swift code to transcribe audio.

Tasks:

```text
- Create the Xcode project
- Add WhisperKit via Swift Package
- Transcribe one sample audio file
- Get fullText
- Check whether segment information is available
- Compare speed across Tiny / Base / Large variants
```

Done when:

```text
- A local audio file can be transcribed from Swift
- A model can be specified
- Japanese audio produces practically usable results
- Error details can be obtained on failure
```

### Phase 2: GUI MVP

Next, build the SwiftUI screens.

Tasks:

```text
- Create the main window
- File selection
- Drag & drop
- Model selection
- Language selection
- Start transcription
- Display results
- Cancel
```

History and complex model management are not added yet at this stage.

Done when:

```text
- Choosing a file and pressing a button transcribes it
- The UI does not freeze during processing
- Processing can be cancelled
- The transcript can be copied
```

### Phase 3: Export

Tasks:

```text
- TXT export
- Markdown export
- JSON export
- SRT export
- VTT export
```

Done when:

```text
- Subtitles with segment-level timestamps can be saved
- The user can choose the save location
- Save failures produce clear error messages
```

### Phase 4: Model management

This is where it starts to feel like a real app.

Tasks:

```text
- Show the model-not-ready state
- First-time download flow
- Download progress
- Model deletion
- Recommended model display
- Free disk space check
```

WhisperKit documents automatic model downloads from Hugging Face and support for custom models. ([Mintlify][2]) However, with commercial use and distribution in mind, the app should make model license notices, storage location, and deletion explicit.

### Phase 5: History and project storage

Tasks:

```text
- Transcription history
- Source file name
- Creation date and time
- Model used
- Language
- Formats exported
- Edited text
```

Storage location:

```text
~/Library/Application Support/LocalTranscriber/
├─ Models/
├─ Transcripts/
├─ Exports/
└─ history.sqlite
```

SwiftData makes implementation easy, but if data migration and backups become priorities, raw SQLite or an SQLite wrapper such as GRDB are also candidates. SwiftData is sufficient for the MVP.

### Phase 6: Long-audio support

This phase is important if the app is used for meeting transcripts.

Tasks:

```text
- Validate with 30 / 60 / 120 minute audio
- Measure memory usage
- Save intermediate results
- Crash recovery
- Consider enabling VAD
- Mitigate hallucinations during silence
```

WhisperKit lists VAD as a feature. ([Mintlify][2]) However, rather than configuring VAD in detail from the start of the MVP, it is better to first get things working with default settings, then tune after looking at accuracy issues in silent stretches.

### Phase 7: Distribution

Tasks:

```text
- Release build
- DMG creation
- GitHub Actions release workflow
- Publish DMG to GitHub Releases
- Direct users from GitHub Pages to releases/latest
- (Optional) Developer ID signing and notarization
```

Done when:

```text
- Pushing a v*.*.* tag publishes Transnote-{version}.dmg to GitHub Releases
- GitHub Pages has a download path and installation guide
- With unsigned distribution, the workflow runs without GitHub Secrets
```

Unsigned DMGs are currently distributed. Because Gatekeeper shows a warning on first launch, the installation guide tells users to right-click → Open.

If a smoother installation experience is needed in the future, consider signing with Developer ID and submitting to Apple's notarization service. Apple explains that for Developer ID–signed software distributed outside the Mac App Store, notarization lets Gatekeeper confirm the software has not been tampered with and is not known malware. ([Apple Developer][4])

## Proposed development schedule

|  Period | Scope                  | Deliverable                                  |
| ------: | ---------------------- | -------------------------------------------- |
|  Week 1 | WhisperKit validation  | Transcribe one audio file from Swift         |
|  Week 2 | GUI MVP                | File selection → transcription → display     |
|  Week 3 | Export                 | TXT / Markdown / JSON / SRT / VTT            |
|  Week 4 | Model management       | Model download, selection, deletion          |
|  Week 5 | History and settings   | History, save location, language setting     |
|  Week 6 | Long-audio testing     | Stable with audio of 60 minutes or more      |
|  Week 7 | Distribution prep      | Unsigned DMG, GitHub Releases / Pages        |
|  Week 8 | Beta                   | Testing with real users                      |

## Extensions after v1

| Feature                | Priority | Approach                              |
| ---------------------- | -------: | ------------------------------------- |
| Video file support     |     High | Extract audio with AVFoundation       |
| Real-time recording    |     High | WhisperKit streaming                  |
| Speaker diarization    | Med–High | Evaluate SpeakerKit                   |
| Custom vocabulary      |   Medium | Correct proper nouns in post-processing |
| Subtitle editor        |   Medium | Segment editing UI                    |
| Meeting minutes        |   Medium | Local LLM or manual templates         |
| Menu bar app           |  Low–Med | For dictation use                     |

`argmax-oss-swift` includes SpeakerKit as well as WhisperKit, and the official README covers speaker diarization too. ([GitHub][1]) However, diarization makes the UI and data structures considerably more complex, so it should wait until after the MVP.

## Implementation priority

The fastest path to something usable, in order:

```text
1. Add WhisperKit via Swift Package
2. Transcribe a fixed audio file
3. File selection in SwiftUI
4. Show the transcript in a TextEditor
5. Save as TXT
6. Save as SRT / VTT
7. Model selection
8. History
9. Long-audio support
10. DMG distribution
```

## Version plan

The best approach for this project is to start with **SwiftUI + WhisperKit only**.

```text
v0.1: File selection → transcription → save as TXT
v0.2: SRT / VTT / JSON, model selection
v0.3: History, settings, long-audio support
v0.4: Model management, stronger error handling
v1.0: Stabilized distribution flow (signing optional)
v1.1: Video support, speaker diarization, recording
```

Python and Rust are better left out at this stage. The sound approach is to **build the MVP in Swift alone, and consider adding a Rust / whisper.cpp backend once WhisperKit's limits become clear**.

[1]: https://github.com/argmaxinc/argmax-oss-swift "GitHub - argmaxinc/argmax-oss-swift: On-device Speech AI for Apple Silicon · GitHub"
[2]: https://www.mintlify.com/explore/argmaxinc/WhisperKit "WhisperKit Documentation - WhisperKit"
[4]: https://developer.apple.com/support/developer-id/ "Developer ID - Support"
