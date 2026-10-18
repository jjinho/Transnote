import XCTest
@testable import LocalTranscriber

@MainActor
final class MainWindowViewModelProgressTests: XCTestCase {
    private var audioURL: URL!
    private var viewModel: MainWindowViewModel!

    override func setUpWithError() throws {
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data(count: 64))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: audioURL)
    }

    func testPartialTextUpdatesDuringTranscription() async throws {
        // Given: a mock Transcriber that emits partialText twice
        let mock = MockProgressTranscriber(
            partialTexts: ["Hello", "Hello world"],
            finalText: "Hello world final",
            delayNanoseconds: 50_000_000
        )
        viewModel = MainWindowViewModel(transcriber: mock)
        configureForTranscription()

        // When
        viewModel.startTranscription()

        // Then: the first partialText is reflected
        try await waitUntil { self.viewModel.transcriptText == "Hello" }
        XCTAssertEqual(viewModel.uiState, .transcribing)
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertFalse(viewModel.canExport)

        // Then: the second partialText is reflected
        try await waitUntil { self.viewModel.transcriptText == "Hello world" }
        XCTAssertFalse(viewModel.canExport)

        // Then: after completion, it is overwritten by the final Transcript
        try await waitUntil { self.viewModel.uiState == .done }
        XCTAssertEqual(viewModel.transcriptText, "Hello world final")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "Hello world final")
        XCTAssertTrue(viewModel.canExport)
    }

    func testPartialTextWithOnlySpecialTokenArtifactsDoesNotUpdateTranscript() async throws {
        let mock = MockProgressTranscriber(
            partialTexts: ["<|startoftranscript|><|nocaptions|><|endoftext|>"],
            finalText: "final",
            delayNanoseconds: 50_000_000,
            finalDelayNanoseconds: 500_000_000
        )
        viewModel = MainWindowViewModel(transcriber: mock)
        configureForTranscription()

        viewModel.startTranscription()

        try await waitUntil { self.viewModel.uiState == .transcribing }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.transcriptText, "")
        try await waitUntil { self.viewModel.uiState == .done }
        XCTAssertEqual(viewModel.transcriptText, "final")
    }

    func testStartTranscriptionClearsPreviousResult() async throws {
        // Given: a previous transcription result remains
        let mock = MockProgressTranscriber(
            partialTexts: [],
            finalText: "new result",
            delayNanoseconds: 100_000_000
        )
        viewModel = MainWindowViewModel(transcriber: mock)
        configureForTranscription()
        viewModel.transcriptText = "previous result"
        viewModel.currentTranscript = Transcript(
            sourceFileName: "old.wav",
            fullText: "previous result"
        )

        // When
        viewModel.startTranscription()

        // Then: the previous result is cleared immediately after starting
        XCTAssertEqual(viewModel.transcriptText, "")
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertFalse(viewModel.canExport)

        try await waitUntil { self.viewModel.uiState == .done }
        XCTAssertEqual(viewModel.transcriptText, "new result")
    }

    func testModelDownloadButtonIsShownForModelThatIsNotDownloaded() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.downloadedModelIDs = []

        XCTAssertTrue(viewModel.shouldShowModelDownloadButton)
        XCTAssertTrue(viewModel.canDownloadSelectedModel)
    }

    func testModelDownloadButtonIsHiddenForDownloadedModel() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.downloadedModelIDs = ["base"]

        XCTAssertFalse(viewModel.shouldShowModelDownloadButton)
        XCTAssertFalse(viewModel.canDownloadSelectedModel)
    }

    func testModelDownloadButtonRemainsShownButCannotRunWhileDownloading() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.downloadedModelIDs = []
        viewModel.simulateModelDownloadForTesting()

        XCTAssertTrue(viewModel.shouldShowModelDownloadButton)
        XCTAssertFalse(viewModel.canDownloadSelectedModel)
    }

    func testModelDownloadGuidanceIsShownForModelThatIsNotDownloaded() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.downloadedModelIDs = []

        XCTAssertEqual(
            viewModel.modelDownloadGuidance,
            L(
                "初回はモデルのダウンロードが必要です（音声は端末内で処理し、通信はダウンロード時のみ）",
                comment: "Model download onboarding guidance"
            )
        )
    }

    func testModelDownloadGuidanceIsHiddenForDownloadedModel() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.downloadedModelIDs = ["base"]

        XCTAssertNil(viewModel.modelDownloadGuidance)
    }

    func testCancelActionLabelsSwitchForModelDownload() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.simulateModelDownloadForTesting()

        XCTAssertEqual(
            viewModel.cancelActionAccessibilityLabel,
            L("ダウンロードをキャンセル", comment: "Cancel model download accessibility label")
        )
        XCTAssertEqual(viewModel.cancelMenuTitle, viewModel.cancelActionAccessibilityLabel)
        XCTAssertEqual(
            viewModel.cancelActionHelp,
            L("ダウンロードをキャンセル（Esc）", comment: "Cancel model download shortcut help")
        )
    }

    func testCancelActionLabelsStayOnTranscriptionDuringTranscription() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.uiState = .transcribing
        

        XCTAssertEqual(
            viewModel.cancelActionAccessibilityLabel,
            L("文字起こしをキャンセル", comment: "Cancel transcription accessibility label")
        )
        XCTAssertEqual(viewModel.cancelMenuTitle, viewModel.cancelActionAccessibilityLabel)
        XCTAssertEqual(
            viewModel.cancelActionHelp,
            L("文字起こしをキャンセル（Esc）", comment: "Cancel transcription shortcut help")
        )
    }

    func testCanCopyTranscriptRequiresNonEmptyResult() {
        viewModel = MainWindowViewModel()
        XCTAssertFalse(viewModel.canCopyTranscript)

        viewModel.currentTranscript = Transcript(sourceFileName: "a.wav", fullText: "text")
        viewModel.transcriptText = "text"
        XCTAssertTrue(viewModel.canCopyTranscript)
    }

    func testRecoverableModelNotDownloadedErrorUsesInlineBannerOnly() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )
        viewModel.downloadedModelIDs = []

        viewModel.startTranscription()

        XCTAssertEqual(
            viewModel.inlineErrorTitle,
            L("モデル未ダウンロード", comment: "Model not downloaded title")
        )
        XCTAssertNotNil(viewModel.inlineErrorMessage)
        XCTAssertNil(viewModel.criticalErrorMessage)
        XCTAssertEqual(viewModel.uiState, .idle)
    }

    func testStartTranscriptionDisabledReasonTracksBlockingCondition() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.downloadedModelIDs = ["base"]

        // No file selected: reason points at the missing file
        XCTAssertEqual(
            viewModel.startTranscriptionDisabledReason,
            L("音声ファイルを選択してください", comment: "Select an audio file")
        )

        // File selected: no blocking condition remains, start is available
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )
        XCTAssertNil(viewModel.startTranscriptionDisabledReason)
        XCTAssertTrue(viewModel.canStartTranscription)
    }

    func testModelDownloadSuccessToastMessageWhenFileIsSelected() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )

        XCTAssertEqual(
            viewModel.modelDownloadSuccessToastMessage(),
            L(
                "モデルのダウンロードが完了しました。文字起こしを開始できます。",
                comment: "Model download success toast when file is selected"
            )
        )
    }

    func testModelDownloadSuccessToastMessageWhenNoFileIsSelected() {
        AppSettings.shared.selectedModelID = "base"
        viewModel = MainWindowViewModel()

        XCTAssertEqual(
            viewModel.modelDownloadSuccessToastMessage(),
            L(
                "モデルのダウンロードが完了しました。音声ファイルを選択してください。",
                comment: "Model download success toast when no file is selected"
            )
        )
    }

    func testHasPlayableSegmentsReturnsFalseForEmptySegments() {
        let transcript = Transcript(sourceFileName: "test.wav", fullText: "hello", segments: [])

        XCTAssertFalse(MainWindowViewModel.hasPlayableSegments(in: transcript))
    }

    func testHasPlayableSegmentsReturnsTrueWhenSegmentTextExists() {
        let transcript = Transcript(
            sourceFileName: "test.wav",
            fullText: "hello",
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "hello")]
        )

        XCTAssertTrue(MainWindowViewModel.hasPlayableSegments(in: transcript))
    }

    private func configureForTranscription() {
        AppSettings.shared.selectedModelID = "base"
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )
        viewModel.downloadedModelIDs = ["base"]
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
        XCTFail("Condition not met within timeout")
    }
}

private final class MockProgressTranscriber: Transcriber, @unchecked Sendable {
    private let partialTexts: [String]
    private let finalText: String
    private let delayNanoseconds: UInt64
    private let finalDelayNanoseconds: UInt64
    private var activeTasks: [UUID: Task<Transcript, Error>] = [:]
    private let lock = NSLock()

    init(
        partialTexts: [String],
        finalText: String,
        delayNanoseconds: UInt64,
        finalDelayNanoseconds: UInt64 = 0
    ) {
        self.partialTexts = partialTexts
        self.finalText = finalText
        self.delayNanoseconds = delayNanoseconds
        self.finalDelayNanoseconds = finalDelayNanoseconds
    }

    func transcribe(
        _ job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript {
        let task = Task<Transcript, Error> {
            for (index, text) in partialTexts.enumerated() {
                try Task.checkCancellation()
                progressHandler?(
                    .make(
                        phase: .transcribing,
                        fraction: Double(index + 1) / Double(partialTexts.count + 1),
                        modelDisplayName: job.modelDisplayName,
                        partialText: text
                    )
                )
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }

            if finalDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: finalDelayNanoseconds)
            }

            try Task.checkCancellation()
            return Transcript(
                sourceFileName: job.sourceFileName,
                fullText: finalText
            )
        }

        lock.lock()
        activeTasks[job.id] = task
        lock.unlock()

        defer {
            lock.lock()
            activeTasks.removeValue(forKey: job.id)
            lock.unlock()
        }

        return try await task.value
    }

    func cancel(jobID: UUID) {
        lock.lock()
        let task = activeTasks[jobID]
        lock.unlock()
        task?.cancel()
    }
}
