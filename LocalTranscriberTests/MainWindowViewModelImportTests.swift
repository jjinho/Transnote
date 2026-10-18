import XCTest
@testable import LocalTranscriber

@MainActor
final class MainWindowViewModelImportTests: XCTestCase {
    private var importsRoot: URL!
    private var sourceRoot: URL!
    private var viewModel: MainWindowViewModel!

    override func setUpWithError() throws {
        importsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        viewModel = MainWindowViewModel(
            audioImportService: AudioImportService(importsRoot: importsRoot)
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: importsRoot)
        try? FileManager.default.removeItem(at: sourceRoot)
    }

    func testSelectFileImportsExtensionlessM4APlaceholderName() throws {
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertTrue(viewModel.selectedFile?.fileName.hasSuffix(".m4a") == true)
        XCTAssertTrue(
            viewModel.selectedFile?.url.path.hasPrefix(importsRoot.path) == true
        )
    }

    func testSelectFileImportsPlaceholderDropNameWithPreferredFileName() throws {
        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("fake audio".utf8))

        viewModel.selectFile(url: sourceURL)

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSelectFileImportsPlaceholderDropNameWithDropPreferredFileName() throws {
        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("fake audio".utf8))

        viewModel.selectFile(url: sourceURL, preferredFileName: "recording.m4a")

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertEqual(viewModel.selectedFile?.fileName, "recording.m4a")
    }

    func testSelectFileImportsPlaceholderDropNameWithM4AContent() throws {
        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertEqual(viewModel.selectedFile?.fileName, "imported-audio.m4a")
    }

    private func seedExistingTranscriptResult() {
        viewModel.currentTranscript = Transcript(
            sourceFileName: "old.wav",
            fullText: "existing text"
        )
        viewModel.transcriptText = "existing text"
    }

    func testSelectFileAppliesImmediatelyWhenThereIsNoExistingResult() throws {
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertNotNil(viewModel.selectedFile)
    }

    func testSelectFileAwaitsConfirmationWhenAnExistingResultIsPresent() throws {
        seedExistingTranscriptResult()
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        let previousFile = viewModel.selectedFile

        viewModel.selectFile(url: sourceURL)

        // Confirmation is pending, file not switched yet
        XCTAssertTrue(viewModel.confirmFileImport)
        XCTAssertNotNil(viewModel.pendingFileImport)
        XCTAssertEqual(viewModel.selectedFile, previousFile)
        XCTAssertEqual(viewModel.transcriptText, "existing text")
    }

    func testApplyPendingFileImportReplacesResultAfterConfirmation() throws {
        seedExistingTranscriptResult()
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)
        viewModel.applyPendingFileImport()

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertEqual(viewModel.transcriptText, "")
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
    }

    func testCancelPendingFileImportKeepsExistingResult() throws {
        seedExistingTranscriptResult()
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        let previousFile = viewModel.selectedFile

        viewModel.selectFile(url: sourceURL)
        viewModel.cancelPendingFileImport()

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertEqual(viewModel.selectedFile, previousFile)
        XCTAssertEqual(viewModel.transcriptText, "existing text")
    }

    // MARK: - file change race regression (#246)

    func testFileSelectionIsIgnoredWhileTranscriptionIsRunning() async throws {
        let gate = AsyncGate()
        let transcriber = MockTranscriber(gate: gate)
        let vm = MainWindowViewModel(
            transcriber: transcriber,
            audioImportService: AudioImportService(importsRoot: importsRoot)
        )

        AppSettings.shared.selectedModelID = "base"
        vm.downloadedModelIDs = ["base"]
        let sourceURL = sourceRoot.appendingPathComponent("race.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("audio".utf8))
        vm.selectFile(url: sourceURL)

        vm.startTranscription()
        XCTAssertTrue(vm.isBusy)

        let before = vm.selectedFile?.url
        let replacement = sourceRoot.appendingPathComponent("other.wav")
        FileManager.default.createFile(atPath: replacement.path, contents: Data("x".utf8))
        vm.selectFile(url: replacement)

        XCTAssertEqual(vm.selectedFile?.url, before)
        gate.open()
    }
}

// Async gate that can wait for completion
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            self.continuation = cont
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        continuation?.resume()
        continuation = nil
        lock.unlock()
    }
}

// Mock Transcriber for tests
final class MockTranscriber: Transcriber, @unchecked Sendable {
    private let gate: AsyncGate
    init(gate: AsyncGate) { self.gate = gate }
    func transcribe(_ job: TranscriptionJob, progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?) async throws -> Transcript {
        await gate.wait()
        return Transcript(sourceFileName: job.sourceFileName, fullText: "done")
    }
    func cancel(jobID: UUID) {}
}

