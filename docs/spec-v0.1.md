# v0.1 Specification

The first release is scoped as follows.

```text
Target OS: macOS 14+
Development environment: Xcode 16+
UI: SwiftUI
Transcription: WhisperKit
Input: wav, mp3, m4a, flac
Output: txt, md, json, srt, vtt
Languages: auto, ja, en
Models: tiny, base, small, large-v3 variants
Storage: local only
Network: only for model downloads
```

## Out of scope

The following are not included in v0.1.

- Video files
- Speaker diarization
- Real-time recording
- Summarization
- Custom vocabulary

## Underlying technology

WhisperKit is provided as a Swift Package from `argmaxinc/argmax-oss-swift`, and `WhisperKit` / `TTSKit` / `SpeakerKit` can be added as separate products. The official README lists the prerequisites as **macOS 14.0 or later and Xcode 16.0 or later**. ([GitHub][1])

Local audio files can be transcribed with a call such as `WhisperKit().transcribe(audioPath:)`, and formats such as WAV / MP3 / M4A / FLAC are documented. ([GitHub][1]) The WhisperKit documentation also describes real-time streaming, word-level timestamps, VAD, and model management as key features. ([Mintlify][2])

## MVP flow

```text
Select a local audio or video file
↓
Transcribe on-device with WhisperKit
↓
Display the result on screen
↓
Save as TXT / SRT / VTT / JSON
```

[1]: https://github.com/argmaxinc/argmax-oss-swift "GitHub - argmaxinc/argmax-oss-swift: On-device Speech AI for Apple Silicon · GitHub"
[2]: https://www.mintlify.com/explore/argmaxinc/WhisperKit "WhisperKit Documentation - WhisperKit"
